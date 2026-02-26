#!/bin/bash

set -e

echo "Inizio il deploy delle nuove immagini Docker..."

cd /vagrant

sudo docker-compose pull

sudo docker-compose up -d

echo "Deploy completato con successo!"