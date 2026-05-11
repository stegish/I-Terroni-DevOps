output "manager_ip" {
  description = "Public IPv4 of the swarm manager. Use this as DROPLET_IP in CI."
  value       = digitalocean_droplet.manager.ipv4_address
}

output "worker_ips" {
  description = "Public IPv4 addresses of all worker nodes."
  value       = digitalocean_droplet.worker[*].ipv4_address
}

output "ssh_manager" {
  description = "Convenience SSH command to reach the manager."
  value       = "ssh -i ${var.ssh_private_key_path} root@${digitalocean_droplet.manager.ipv4_address}"
}
