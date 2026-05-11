# DNS — only created if var.domain_name is set. Lets us swap out the
# manager's IP at the apply level without humans clicking around in the
# DigitalOcean DNS UI.
#
# Assumes the domain is already on DigitalOcean nameservers. If it isn't,
# delete this file or set var.domain_name = "".

resource "digitalocean_record" "apex" {
  count  = var.domain_name == "" ? 0 : 1
  domain = var.domain_name
  type   = "A"
  name   = "@"
  value  = digitalocean_droplet.manager.ipv4_address
  ttl    = 60
}

resource "digitalocean_record" "www" {
  count  = var.domain_name == "" ? 0 : 1
  domain = var.domain_name
  type   = "A"
  name   = "www"
  value  = digitalocean_droplet.manager.ipv4_address
  ttl    = 60
}
