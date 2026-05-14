variable "do_token" {
  description = "DigitalOcean API token. Set via TF_VAR_do_token env var."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region for all droplets."
  type        = string
  default     = "fra1"
}

variable "ssh_key_name" {
  description = "Name of the SSH key already registered in DigitalOcean (data lookup, not created here)."
  type        = string
  default     = "minitwit"
}

variable "ssh_private_key_path" {
  description = "Local path to the matching private key. Used by provisioners to SSH into the droplets."
  type        = string
}

variable "manager_size" {
  description = "Droplet size for the swarm manager (runs prometheus/grafana/loki — needs more RAM)."
  type        = string
  default     = "s-2vcpu-2gb"
}

variable "worker_size" {
  description = "Droplet size for the swarm workers (run minitwit replicas)."
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "worker_count" {
  description = "Number of worker droplets to create."
  type        = number
  default     = 2
}

variable "image" {
  description = "Base image. Provisioning installs Docker on top."
  type        = string
  default     = "ubuntu-24-04-x64"
}
