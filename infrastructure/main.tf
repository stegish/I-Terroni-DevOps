#  __  __ _       _ _____         _ _
# |  \/  (_)_ __ (_)_   _|_      _(_) |_
# | |\/| | | '_ \| | | | \ \ /\ / / | __|
# | |  | | | | | | | | |  \ V  V /| | |_
# |_|  |_|_|_| |_|_| |_|   \_/\_/ |_|\__|
#
# Declarative infrastructure for the MiniTwit swarm cluster on DigitalOcean.
# 1 manager (observability stack) + N workers (app replicas).

# Reference an SSH key already registered in DigitalOcean rather than
# uploading a new one — keeps the public key out of state and out of git.
data "digitalocean_ssh_key" "default" {
  name = var.ssh_key_name
}

# ---------------------------------------------------------------------------
# Manager droplet — hosts swarm control plane + prometheus/grafana/loki.
# Sized larger because the observability stack is RAM-hungry.
# ---------------------------------------------------------------------------
resource "digitalocean_droplet" "manager" {
  name     = "minitwit-swarm-manager"
  image    = var.image
  region   = var.region
  size     = var.manager_size
  ssh_keys = [data.digitalocean_ssh_key.default.fingerprint]
  tags     = ["minitwit", "swarm-manager"]

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = file(var.ssh_private_key_path)
    timeout     = "3m"
  }

  # Install Docker + tooling. Same set the Vagrantfile installs, kept in
  # sync intentionally — see infrastructure/README.md for the rationale.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      # Wait for cloud-init / unattended-upgrades to release the dpkg lock,
      # otherwise apt-get install races them and silently fails to install docker.
      "cloud-init status --wait || true",
      "while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 3; done",
      "apt-get update -y",
      # docker-compose-plugin isn't in Ubuntu 24.04 default repos; we only need
      # the engine here since deploy.sh uses `docker stack deploy` (built-in).
      "apt-get install -y docker.io git ufw certbot unattended-upgrades",
      "systemctl enable --now docker",
      # Firewall on the host. Docker bypasses ufw via iptables, so this only
      # protects host-bound sockets — see SECURITY.md §2.A.
      "ufw --force reset",
      "ufw default deny incoming",
      "ufw default allow outgoing",
      "ufw allow 22/tcp",
      "ufw allow 80/tcp",
      "ufw allow 443/tcp",
      # minitwit app published directly via Swarm ingress (bypasses nginx).
      "ufw allow 8080/tcp",
      # Swarm control-plane ports (manager <-> nodes)
      "ufw allow 2377/tcp",
      "ufw allow 7946",
      "ufw allow 4789/udp",
      "ufw --force enable",
      "dpkg-reconfigure -f noninteractive unattended-upgrades",
      # Initialize the swarm. --force-new-cluster makes this idempotent on
      # re-provision: a node that's already a manager just stays one.
      "docker swarm init --advertise-addr ${self.ipv4_address} || true",
    ]
  }

  # Pull the worker join token back to the local machine so the worker
  # droplets can use it. Pattern from the IaC slides (slide 22).
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/.tokens
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -i ${var.ssh_private_key_path} root@${self.ipv4_address} \
          'docker swarm join-token worker -q' > ${path.module}/.tokens/worker_token
    EOT
  }
}

# ---------------------------------------------------------------------------
# Worker droplets — run the minitwit replicas + per-node agents.
# count = var.worker_count, so scaling is a one-line change.
# ---------------------------------------------------------------------------
resource "digitalocean_droplet" "worker" {
  count    = var.worker_count
  name     = "minitwit-swarm-worker-${count.index}"
  image    = var.image
  region   = var.region
  size     = var.worker_size
  ssh_keys = [data.digitalocean_ssh_key.default.fingerprint]
  tags     = ["minitwit", "swarm-worker"]

  # Workers can only join after the manager has produced a join token.
  depends_on = [digitalocean_droplet.manager]

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.ipv4_address
    private_key = file(var.ssh_private_key_path)
    timeout     = "3m"
  }

  # Copy the join token produced by the manager onto this node.
  provisioner "file" {
    source      = "${path.module}/.tokens/worker_token"
    destination = "/root/worker_token"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      "cloud-init status --wait || true",
      "while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 3; done",
      "apt-get update -y",
      "apt-get install -y docker.io ufw unattended-upgrades",
      "systemctl enable --now docker",
      "ufw --force reset",
      "ufw default deny incoming",
      "ufw default allow outgoing",
      "ufw allow 22/tcp",
      # minitwit is published with mode: ingress, so the routing mesh opens
      # :8080 on every node — workers need it through ufw too, even though
      # the replicas all run here.
      "ufw allow 8080/tcp",
      # Swarm overlay/data ports. Workers don't need 80/443 — those are only
      # published by nginx on the manager.
      "ufw allow 2377/tcp",
      "ufw allow 7946",
      "ufw allow 4789/udp",
      "ufw --force enable",
      "dpkg-reconfigure -f noninteractive unattended-upgrades",
      # Join the swarm. `|| true` so a re-apply on an already-joined node
      # doesn't fail the whole plan.
      "docker swarm join --token $(cat /root/worker_token) ${digitalocean_droplet.manager.ipv4_address}:2377 || true",
    ]
  }
}
