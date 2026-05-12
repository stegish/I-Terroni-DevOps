# DigitalOcean cloud firewall — applied at the platform edge, before
# packets ever reach the droplet. Belt-and-braces with the per-host ufw
# rules in main.tf, and the only thing that reliably blocks Docker's
# iptables bypass for ports we never want exposed (Prometheus, Grafana,
# Loki — see SECURITY.md §2.A and the lecture's ElasticSearch ransom story).

resource "digitalocean_firewall" "minitwit" {
  name = "minitwit-swarm"

  droplet_ids = concat(
    [digitalocean_droplet.manager.id],
    digitalocean_droplet.worker[*].id,
  )

  # --- Inbound from the public internet ---
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # --- Inbound between cluster members only (swarm overlay) ---
  # Restricted by tag so a stray droplet on the same VPC can't join.
  inbound_rule {
    protocol    = "tcp"
    port_range  = "2377"
    source_tags = ["minitwit"]
  }

  inbound_rule {
    protocol    = "tcp"
    port_range  = "7946"
    source_tags = ["minitwit"]
  }

  inbound_rule {
    protocol    = "udp"
    port_range  = "7946"
    source_tags = ["minitwit"]
  }

  inbound_rule {
    protocol    = "udp"
    port_range  = "4789"
    source_tags = ["minitwit"]
  }

  # --- Outbound: unrestricted (apt, docker pull, certbot, etc.) ---
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
