terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }

  # Backend left intentionally local by default. To share state across the
  # team, switch to a remote backend (DigitalOcean Spaces is S3-compatible)
  # and uncomment the block below. State files contain secrets (SSH keys,
  # tokens) — never commit terraform.tfstate to git.
  #
  # backend "s3" {
  #   endpoint                    = "https://fra1.digitaloceanspaces.com"
  #   region                      = "us-east-1"   # required dummy for DO Spaces
  #   bucket                      = "iterroni-tfstate"
  #   key                         = "minitwit/terraform.tfstate"
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  # }
}

provider "digitalocean" {
  token = var.do_token
}
