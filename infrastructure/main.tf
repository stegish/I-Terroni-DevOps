data "digitalocean_ssh_key" "default" {
  name = var.ssh_key_name
}


# Manager droplet — hosts swarm control plane + prometheus/grafana/loki..
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

  provisioner "remote-exec" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -y",
      "apt-get install -y docker.io docker-compose-plugin git ufw certbot unattended-upgrades",
      "systemctl enable --now docker",
      # Firewall on the host. Docker bypasses ufw via iptables, so this only
      # protects host-bound sockets
      "ufw --force reset",
      "ufw default deny incoming",
      "ufw default allow outgoing",
      "ufw allow 22/tcp",
      "ufw allow 80/tcp",
      "ufw allow 443/tcp",
      # Swarm control-plane ports (manager <-> nodes)
      "ufw allow 2377/tcp",
      "ufw allow 7946",
      "ufw allow 4789/udp",
      "ufw --force enable",
      "dpkg-reconfigure -f noninteractive unattended-upgrades",
      # Initialize the swarm
      "docker swarm init --advertise-addr ${self.ipv4_address} || true",
    ]
  }

  # Pull the worker join token back to the local machine so the worker
  # droplets can use it
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/.tokens
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -i ${var.ssh_private_key_path} root@${self.ipv4_address} \
          'docker swarm join-token worker -q' > ${path.module}/.tokens/worker_token
    EOT
  }
}

# Worker droplets — run the minitwit replicas + per-node agents.
# count = var.worker_count
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
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update -y",
      "apt-get install -y docker.io docker-compose-plugin ufw unattended-upgrades",
      "systemctl enable --now docker",
      "ufw --force reset",
      "ufw default deny incoming",
      "ufw default allow outgoing",
      "ufw allow 22/tcp",
  # Swarm overlay/data ports.
  # Workers don't expose 80/443 because ingress handles external traffic.
  # Only the manager runs nginx and publishes these ports.
      "ufw allow 2377/tcp",
      "ufw allow 7946",
      "ufw allow 4789/udp",
      "ufw --force enable",
      "dpkg-reconfigure -f noninteractive unattended-upgrades",
      "docker swarm join --token $(cat /root/worker_token) ${digitalocean_droplet.manager.ipv4_address}:2377 || true",
    ]
  }
}
