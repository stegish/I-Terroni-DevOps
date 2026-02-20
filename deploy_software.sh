#!/bin/bash

set -e

echo "🚀 Starting deployment to DigitalOcean Droplet..."

# 1. sync the latest local files
echo "syncing project files to the server..."
vagrant rsync

# 2. execute Docker commands
echo "building and starting Docker containers on the server..."
vagrant ssh -c "
  cd /vagrant
  
  # Ensure the data folder exists for the SQLite database volume
  mkdir -p tmp
  
  # Stop any running containers, rebuild the image, and start them in detached mode
  sudo docker-compose down
  sudo docker-compose up -d --build
"

# fetch the public IP
echo "deployment successful"
PUBLIC_IP=$(vagrant ssh -c "curl -s ifconfig.me" 2>/dev/null | tr -d '\r')

echo "======================================================="
echo "MiniTwit App is live at: http://${PUBLIC_IP}:8080"
echo "Simulator API is at:     http://${PUBLIC_IP}:8080/"
echo "======================================================="