#!/bin/bash
set -e
cd /vagrant
sudo docker compose pull
sudo docker compose up -d
echo "Deploy completato con successo!"