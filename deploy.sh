#!/bin/bash
set -e

echo "2. Updating Docker Configs..."
# Docker configs are immutable: to update, create a new one and remove the old one
if sudo docker config inspect promtail_config > /dev/null 2>&1; then
  sudo docker config rm promtail_config
fi
sudo docker config create promtail_config ./logging/promtail-config.yml

echo "3. Deploying/Updating Swarm Stack..."
sudo docker stack deploy --with-registry-auth -c docker-compose.yml minitwit_stack

echo "Deploy finished!"
