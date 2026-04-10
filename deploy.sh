#!/bin/bash
set -e

echo "1. download images..."
sudo docker compose pull

echo "2. initializing docker Swarm..."
if ! sudo docker info | grep -q "Swarm: active"; then
    sudo docker swarm init --advertise-addr eth0 || true
fi
echo "3. start Swarm..."
sudo docker compose down || true
sudo docker stack deploy -c docker-compose.yml minitwit_stack

echo "Deploy finished!"