#!/bin/bash
set -e

echo "1. Pulling latest images..."
sudo docker compose pull

echo "2. Deploying/Updating Swarm Stack..."
sudo docker stack deploy --with-registry-auth -c docker-compose.yml minitwit_stack

echo "Deploy finished!"