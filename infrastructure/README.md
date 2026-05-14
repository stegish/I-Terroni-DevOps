# Infrastructure as Code — Terraform

This directory replaces the single-droplet [Vagrantfile](../Vagrantfile) with a
declarative, multi-node Terraform setup that matches what `docker-compose.yml`
actually requires: **1 swarm manager + N workers** (default 2).

The Vagrantfile is kept for single-node local experiments; production
infrastructure is created from here.

---

## What gets created

| Resource                                | Count       | Purpose                                                      |
| --------------------------------------- | ----------- | ------------------------------------------------------------ |
| `digitalocean_droplet.manager`          | 1           | Swarm manager + observability stack (prometheus/grafana/loki) |
| `digitalocean_droplet.worker`           | `var.worker_count` (2) | Run minitwit replicas                              |
| `digitalocean_firewall.minitwit`        | 1           | Cloud firewall on every droplet                              |

What is **not** created here:
- The managed MySQL database (created once in the DO UI; its `DATABASE_URL`
  lives in `.env` and in GitHub Secrets).
- The SSH key (uploaded once in the DO UI; referenced via `data` block).
- TLS certificates (issued by certbot via [scripts/setup-tls.sh](../scripts/setup-tls.sh)
  on first boot of nginx).

---

## Prerequisites

- Terraform ≥ 1.5 (or [OpenTofu](https://opentofu.org/) — drop-in compatible).
- A DigitalOcean account, an API token, and an SSH key registered in the DO UI.
- Your matching private key on disk.

---

## First-time setup

```bash
cd infrastructure/
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars (ssh_private_key_path, ssh_key_name)

export TF_VAR_do_token=dop_v1_xxxxxxxx   # never put this in a file

terraform init
terraform plan
terraform apply
```

`terraform output manager_ip` gives you the public IP of the manager. Put
that value into the `DROPLET_IP` GitHub secret so CI/CD can SSH in.

---

## Daily operations

| Action                     | Command                                                        |
| -------------------------- | -------------------------------------------------------------- |
| Bring everything up        | `./bring-up.sh` (apply + scp + deploy.sh)                      |
| Tear everything down       | `./teardown.sh` (destroy with confirmation)                    |
| Preview a change           | `terraform plan`                                                |
| Add a worker               | edit `worker_count` in `terraform.tfvars`, `terraform apply`   |
| SSH to manager             | `$(terraform output -raw ssh_manager)`                         |

The `bring-up.sh` / `teardown.sh` pair exists specifically for the
exam-prep flow ([slides §33](../IaC.pdf)): tear down to stop paying when
the simulator is off, bring up in one command for the demo.

---

## State and team sharing

By default state is local in `terraform.tfstate`. **It is gitignored**
because Terraform writes resolved attributes (including the worker join
token after a re-apply, and any sensitive values) into it.

For team collaboration, switch to a remote backend. The block is
pre-written and commented in [versions.tf](versions.tf) — uncomment it
and create a DigitalOcean Spaces bucket. The S3 protocol that DO Spaces
implements gives you the atomic compare-and-swap that Terraform needs
for state locking.

If you don't bother with remote state, the team-coordination rule is the
same as for any single-source-of-truth artifact: **only one person runs
`terraform apply` at a time**, and they hand the resulting `.tfstate` to
the next operator (private channel, never git). For an apply rate of
once a month this is fine — see the lecture notes on the GitHub-as-state
pattern.

---

## Why this and not just Vagrant

Vagrant is excellent for a single VM. As soon as you have a topology
(manager + workers, dependencies, firewall as a separate object, DNS
records that point to a droplet's IP), the right abstraction is
Terraform's resource graph: it computes the partial order, parallelises
independent creations, and tracks the diff between what you wrote and
what exists.

Both approaches are kept on disk. Use Vagrant for a quick disposable
node when you want to debug a Dockerfile in isolation; use Terraform for
the real cluster.

---

## Known leaky abstractions

Two parts of this setup deliberately fall outside Terraform's state
tracking, and that's a tradeoff to be aware of (Spolsky's *Law of Leaky
Abstractions*):

1. **`provisioner "remote-exec"` in [main.tf](main.tf)** — the apt /
   docker / `swarm init` / `swarm join` commands run via SSH and their
   results are not stored. If `swarm join` fails halfway through,
   Terraform marks the droplet as *tainted* and recreates it on the next
   apply rather than trying to resume. The `|| true` guards make
   re-applies safe on already-converged nodes.
2. **The MySQL database is not in Terraform.** It was provisioned via the
   DO UI before we adopted IaC, and migrating it now would mean
   downtime. New resources should go through Terraform.

Both points are discussed in the report's IaC section.
