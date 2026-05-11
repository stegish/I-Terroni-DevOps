# Infrastructure as Code

## 1. What we built and why

Our final infrastructure is described declaratively with **Terraform** in
[`infrastructure/`](../infrastructure/). A single `terraform apply` produces
the full topology that `docker-compose.yml` requires:

- **1 swarm manager** (`s-2vcpu-2gb`) running the observability stack
  (Prometheus, Grafana, Loki) and the nginx ingress.
- **2 swarm workers** (`s-1vcpu-1gb`) running the three `minitwit`
  replicas plus per-node agents (`node-exporter`, `promtail`).
- A **DigitalOcean cloud firewall** attached to all three droplets,
  restricting public ingress to 22/80/443 and allowing the swarm overlay
  ports (2377/tcp, 7946/tcp+udp, 4789/udp) only between droplets tagged
  `minitwit`.
- Optional **DNS A records** (apex + `www`) pointing to the manager,
  created only when `var.domain_name` is set.

Two helper scripts wrap the apply for the operator:

- [`infrastructure/bring-up.sh`](../infrastructure/bring-up.sh) —
  `terraform apply` + scp of the deploy artifacts + `bash deploy.sh` on
  the manager. One command takes us from "nothing" to "live cluster".
- [`infrastructure/teardown.sh`](../infrastructure/teardown.sh) —
  `terraform destroy` with a confirmation prompt, so the cluster can be
  shut down between the simulator stop and the exam day without paying
  for idle droplets.

The original [`Vagrantfile`](../Vagrantfile) is kept on disk for quick
single-node experiments, but production infrastructure now goes through
Terraform.

## 2. Why we chose Terraform over Bash / Vagrant

We considered three options the lecture material proposed: shell scripts
calling `doctl`, Vagrant, and Terraform.

| Concern                              | Bash + `doctl` | Vagrant         | Terraform        |
| ------------------------------------ | -------------- | --------------- | ---------------- |
| Multi-node topology with deps        | manual ordering | one VM at a time, no graph | first-class (`depends_on`, implicit refs) |
| State diff (what's drifted?)         | none           | `.vagrant/` is opaque | explicit `terraform plan` |
| Remove resource = it gets destroyed  | no             | no              | yes              |
| Cloud firewall as a separate object  | another script | not modeled     | a `resource` block |
| Provider portability                 | DO-specific    | DO-specific (plugin) | swap provider, keep structure |

The decisive factor was the **partial-order resource graph**. The
docker-compose stack we already had assumes a `node.role == manager`
exists *and* at least two `node.role == worker` nodes have joined the
swarm before any service can be scheduled. In Bash that's hand-coded
sequencing with sleeps and SSH retries; in Terraform it's
`depends_on = [digitalocean_droplet.manager]` plus a `local-exec` that
saves the join token.

We didn't pick Vagrant for the production setup because Vagrant is a
single-VM tool by design. Spinning up three nodes in Vagrant works (one
`config.vm.define` block each) but you give up exactly the things
Terraform gives you: the diff against current state, parallel creation
of independent resources, and the ability to model non-VM things
(firewall, DNS) as first-class siblings of the VMs.

## 3. Tradeoffs we accepted

### 3.1 Leaky abstractions

Joel Spolsky's *Law of Leaky Abstractions* is alive in our setup:

- **The `remote-exec` provisioner is outside Terraform's state.** The
  apt installs, the `docker swarm init`, the `docker swarm join` — none
  of these are tracked. Terraform knows the droplet exists; it does not
  know whether docker is healthy on it. If a `remote-exec` fails halfway
  through, Terraform taints the droplet and recreates it on the next
  apply, which is correct but expensive. We made every command
  idempotent (`|| true` on `swarm init`/`join`, `ufw --force reset`)
  so a re-apply on an already-converged droplet is a no-op.
- **The MySQL database is not in Terraform.** It was provisioned in the
  DigitalOcean UI before we adopted Terraform; bringing it under
  Terraform later is feasible (`digitalocean_database_cluster`) but
  would require an `import` step and a maintenance window. We left it
  out and document this in the infra README.

These are exactly the kinds of "the abstraction leaks here" boundaries
the lecture warned about. The fix in both cases would be to push more
work into a true configuration-management tool (Ansible, cloud-init) or
into an immutable image built with Packer, instead of streaming shell
commands over SSH from a provisioner. We considered this, decided the
extra moving part wasn't worth it for a 3-node cluster, and noted the
limitation.

### 3.2 State sharing

The default backend is **local**, which means the `terraform.tfstate`
file lives on whoever last ran `apply`. This is the simplest possible
setup and matches the lecture's pragmatic conclusion: if applies happen
once a month, a local state file passed by hand is fine.

If we needed real concurrent collaboration, the path is documented in
[`versions.tf`](../infrastructure/versions.tf): switch to a DigitalOcean
Spaces backend (S3-compatible), which gives Terraform the atomic
compare-and-swap it needs for state locking. We chose not to bring
this in by default because:

- The state file contains secrets (resolved API responses), so we'd
  need to pin down access control on the bucket — a setup cost we
  didn't yet need.
- Two of us on the team apply ~weekly; collisions haven't happened.

We deliberately did **not** put the state file in our git repository
even though it's private. The HashiCorp docs are explicit that state
contains secrets ([reference](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)),
and git has no locking — two pushes can race.

### 3.3 Vendor lock

Terraform is no longer fully open source (BUSL since 2023). For our
horizon this is fine: the same `.tf` files run unchanged under
**OpenTofu**, the open-source fork. If we ever needed to migrate, the
move is `s/terraform/tofu/` in the scripts. We mention this in the
infra README.

## 4. What happens if `apply` crashes

We thought through the failure modes the lecture raised:

- **Crash after a droplet is created but before its IP is recorded in
  state.** The next `terraform plan` queries the DO API for the actual
  state and detects the drift; the next `apply` either adopts the
  resource or recreates it depending on whether it matches the spec.
- **Crash inside a `remote-exec`.** The droplet is marked tainted.
  Next apply destroys it and tries again from scratch. Slower than
  Bash retry-on-failure, but predictable.
- **Loss of the local state file.** This is the only genuinely bad
  case, and the answer is: keep a remote backend (Spaces) or back up
  `terraform.tfstate` out-of-band. With state lost, the only recovery
  path is `terraform import` for every existing resource — possible but
  tedious.

## 5. Deployment view

```
                                Internet
                                    |
                                    | 80/443
                                    v
                  +----------------------------------------+
                  |  digitalocean_firewall "minitwit"      |
                  |  in:  22, 80, 443  (any source)        |
                  |       2377/tcp, 7946/tcp+udp, 4789/udp |
                  |       (only from tag=minitwit)         |
                  +----------------------------------------+
                                    |
              +---------------------+---------------------+
              |                                           |
              v                                           v
  +------------------------+        +-----------------------------------+
  |  manager droplet       |        |  worker droplets  (count = 2)     |
  |  s-2vcpu-2gb           |        |  s-1vcpu-1gb each                 |
  |  ----------------      |        |  ----------------                 |
  |  docker (swarm init)   |<------>|  docker (swarm join)              |
  |  nginx       :80/:443  |  2377  |  minitwit replicas  (3 total,     |
  |  prometheus  :9090*    |  7946  |   spread 2/1 across the workers)  |
  |  grafana     :3000*    |  4789  |  node-exporter   (mode: global)   |
  |  loki        :3100*    |        |  promtail        (mode: global)   |
  |  certbot (host)        |        |                                   |
  +------------------------+        +-----------------------------------+
              |
              | * bound to 127.0.0.1 only — reach via ssh -L tunnel
              v
        operator laptop

  Out of IaC scope (managed in DO UI):
    +-----------------------------+
    |  DigitalOcean Managed MySQL | <----- DATABASE_URL in .env / GH Secrets
    +-----------------------------+
```

This corresponds to the **Allocation viewpoint** in the architecture-
documentation lecture: it shows where each software artifact runs and
which network paths exist between nodes. A UML deployment diagram in
the report uses the same topology with proper `node` / `artifact`
notation.

## 6. CI/CD integration

GitHub Actions still SSHes into the manager using the IP stored in
`secrets.DROPLET_IP`. The promotion path from Terraform output to that
secret is currently manual (`terraform output -raw manager_ip` →
copy/paste). Two improvements we considered but did not implement:

- A `terraform_remote_state` data source consumed by an Action that
  reads the manager IP from Spaces at deploy time — removes the manual
  step.
- A `digitalocean_reserved_ip` resource attached to the manager — keeps
  the IP stable across droplet recreations, so the GH secret never has
  to change. This is the cleanest fix and is the natural next step.

We didn't ship them now because the manager IP changes only when we
explicitly destroy and recreate the manager, which we do roughly once
per semester.
