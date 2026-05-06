#!/bin/bash
set -e

echo "1. Computing promtail config version..."
HASH=$(sha256sum ./logging/promtail-config.yml | cut -c1-8)
export PROMTAIL_CONFIG_NAME="promtail_config_${HASH}"

# nginx is bind-mounted from ./nginx/nginx.conf. Bind-mount content changes
# don't alter the swarm service spec, so swarm wouldn't restart nginx on a
# redeploy. Inject the config hash as a label so any change (e.g. after
# scripts/setup-tls.sh has rewritten nginx.conf to HTTPS mode) forces a
# rolling restart of the nginx service.
export NGINX_CONFIG_VERSION="$(sha256sum ./nginx/nginx.conf | cut -c1-8)"

echo "2. Ensuring config '${PROMTAIL_CONFIG_NAME}' exists..."
if ! sudo docker config inspect "$PROMTAIL_CONFIG_NAME" > /dev/null 2>&1; then
  sudo docker config create "$PROMTAIL_CONFIG_NAME" ./logging/promtail-config.yml
fi

# Run schema migration ONCE before any app container starts.
# Done here (not on app boot) so the 3 swarm replicas don't race on
# CREATE TABLE and trigger MySQL error 1684.
echo "3. Running schema initialization (one-shot)..."
sudo docker pull michaelfant/minitwitimage:latest
sudo docker run --rm --env-file .env michaelfant/minitwitimage:latest \
  python -c "from db import init_db; init_db()"

echo "4. Deploying/Updating Swarm Stack (nginx config v=${NGINX_CONFIG_VERSION})..."
sudo -E docker stack deploy --with-registry-auth -c docker-compose.yml minitwit_stack

echo "5. Cleaning up old promtail configs..."
for c in $(sudo docker config ls --filter name=promtail_config_ --format '{{.Name}}'); do
  if [ "$c" != "$PROMTAIL_CONFIG_NAME" ]; then
    sudo docker config rm "$c" 2>/dev/null || true
  fi
done

echo "Deploy finished!"