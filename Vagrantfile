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
    provider.image = 'ubuntu-22-04-x64'
    provider.region = 'fra1'
    provider.size = 's-1vcpu-1gb'
  end

  config.vm.provision "shell", inline: <<-SHELL
    export DEBIAN_FRONTEND=noninteractive
    echo "Updating system..."
    apt-get update
    
    echo "Installing Docker and Docker Compose..."
    apt-get install -y docker.io docker-compose-plugin git
    
    systemctl enable docker
    systemctl start docker
    
    echo "Server provisioned successfully!"
  SHELL
end