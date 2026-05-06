# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  #use a "dummy" box because DigitalOcean handles the actual OS image
  config.vm.box = "digital_ocean"
  config.vm.box_url = "https://github.com/devopsgroup-io/vagrant-digitalocean/raw/master/box/digital_ocean.box"

  #use the DigitalOcean provider
  config.vm.provider :digital_ocean do |provider, override|
    #read secrets from environment variables!
    provider.token = ENV['DO_TOKEN']
    provider.ssh_key_name = ENV['DO_SSH_KEY_NAME']
    
    #point vagrant to local private key to connect to the server
    override.ssh.private_key_path = ENV['DO_SSH_KEY_PATH']

    #server configuration
    provider.image = 'ubuntu-24-04-x64'
    provider.region = 'fra1'
    provider.size = 's-1vcpu-1gb'
  end

  config.vm.provision "shell", inline: <<-SHELL
    export DEBIAN_FRONTEND=noninteractive
    echo "Updating system..."
    apt-get update

    # Note: nginx itself runs INSIDE the docker swarm (see docker-compose.yml).
    # We install only certbot here, on the host, so scripts/setup-tls.sh can
    # run certbot in webroot mode against the running swarm nginx.
    echo "Installing Docker, Docker Compose, certbot, ufw..."
    apt-get install -y docker.io docker-compose-plugin git ufw certbot

    systemctl enable docker
    systemctl start docker

    echo "Configuring ufw firewall (deny by default, allow only 22/80/443)..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP (ACME challenge + redirect)'
    ufw allow 443/tcp comment 'HTTPS'
    ufw --force enable
    ufw status verbose

    # NOTE: Docker bypasses ufw by writing to iptables directly. The ufw rules
    # above only protect the host's own listening sockets. Container ports are
    # additionally restricted by binding them to 127.0.0.1 in docker-compose.yml.
    # See SECURITY.md §2.A for the rationale.

    echo "Enabling unattended-upgrades for OS security patches..."
    apt-get install -y unattended-upgrades
    dpkg-reconfigure -f noninteractive unattended-upgrades

    echo "Server provisioned successfully!"
  SHELL
end