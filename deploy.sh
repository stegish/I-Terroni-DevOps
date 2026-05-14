#!/bin/bash
set -e

# Export all variables from .env into the current shell so that sudo -E passes
# them to docker stack deploy for docker-compose.yml variable substitution.
# Without this, mandatory variables like GF_SECURITY_ADMIN_PASSWORD and
# SECRET_KEY would be unset and the deploy would fail at the :? check.
if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

# nginx bind-mounts /etc/letsencrypt and /var/www/certbot from the host.
# On a fresh droplet these don't exist yet (setup-tls.sh creates them on
# first TLS bootstrap), and the swarm scheduler rejects the nginx task
# with "bind source path does not exist". Pre-create the dirs as empty —
# nginx in HTTP-only mode tolerates them being empty.
sudo mkdir -p /etc/letsencrypt /var/www/certbot

echo "1. Computing promtail config version..."
HASH=$(sha256sum ./logging/promtail-config.yml | cut -c1-8)
export PROMTAIL_CONFIG_NAME="promtail_config_${HASH}"

# nginx is bind-mounted from ./nginx/nginx.conf. Bind-mount content changes
# don't alter the swarm service spec, so swarm wouldn't restart nginx on a
# redeploy. Inject the config hash as a label so any change (e.g. after
# scripts/setup-tls.sh has rewritten nginx.conf to HTTPS mode) forces a
# rolling restart of the nginx service.
NGINX_CONFIG_VERSION="$(sha256sum ./nginx/nginx.conf | cut -c1-8)"
export NGINX_CONFIG_VERSION

echo "2. Ensuring config '${PROMTAIL_CONFIG_NAME}' exists..."
if ! sudo docker config inspect "$PROMTAIL_CONFIG_NAME" > /dev/null 2>&1; then
  sudo docker config create "$PROMTAIL_CONFIG_NAME" ./logging/promtail-config.yml
fi

# mysqld-exporter v0.15+ dropped DATA_SOURCE_NAME. Render a .my.cnf from
# the credentials in .env and store it as a versioned Docker secret so the
# exporter can read it from /run/secrets/mysqld_exporter_mycnf.
echo "2b. Building mysqld-exporter .my.cnf secret..."
: "${MYSQLD_EXPORTER_USER:?MYSQLD_EXPORTER_USER must be set in .env}"
: "${MYSQLD_EXPORTER_PASSWORD:?MYSQLD_EXPORTER_PASSWORD must be set in .env}"
: "${MYSQLD_EXPORTER_HOST:?MYSQLD_EXPORTER_HOST must be set in .env}"

# MYSQLD_EXPORTER_HOST may contain :port (legacy DSN format) or just the
# hostname. Split it so my.cnf gets `host` and `port` cleanly.
MYSQLD_HOST_PART="${MYSQLD_EXPORTER_HOST%%:*}"
MYSQLD_PORT_PART="${MYSQLD_EXPORTER_HOST##*:}"
if [ "$MYSQLD_HOST_PART" = "$MYSQLD_PORT_PART" ]; then
  MYSQLD_PORT_PART="${MYSQLD_EXPORTER_PORT:-25060}"
fi

MYCNF_CONTENT="[client]
user=${MYSQLD_EXPORTER_USER}
password=${MYSQLD_EXPORTER_PASSWORD}
host=${MYSQLD_HOST_PART}
port=${MYSQLD_PORT_PART}
tls=skip-verify
"
MYCNF_HASH=$(printf '%s' "$MYCNF_CONTENT" | sha256sum | cut -c1-8)
export MYSQLD_EXPORTER_MYCNF_NAME="mysqld_exporter_mycnf_${MYCNF_HASH}"

if ! sudo docker secret inspect "$MYSQLD_EXPORTER_MYCNF_NAME" > /dev/null 2>&1; then
  printf '%s' "$MYCNF_CONTENT" | sudo docker secret create "$MYSQLD_EXPORTER_MYCNF_NAME" -
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

echo "5b. Cleaning up old mysqld_exporter_mycnf secrets..."
for s in $(sudo docker secret ls --filter name=mysqld_exporter_mycnf_ --format '{{.Name}}'); do
  if [ "$s" != "$MYSQLD_EXPORTER_MYCNF_NAME" ]; then
    sudo docker secret rm "$s" 2>/dev/null || true
  fi
done

echo "Deploy finished!"