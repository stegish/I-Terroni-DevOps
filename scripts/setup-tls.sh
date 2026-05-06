#!/bin/bash
# Bootstrap a Let's Encrypt TLS certificate for this droplet, then upgrade
# nginx/nginx.conf from HTTP-only to HTTPS-with-redirect.
#
# Run ONCE on the swarm manager droplet, after the stack is already deployed
# and reachable on port 80. Uses certbot's webroot mode, so the running
# nginx container serves the ACME challenge — no service downtime required.
#
# Usage:  sudo bash scripts/setup-tls.sh <domain>
#
# After it succeeds, you must:
#   1. git add nginx/nginx.conf  &&  git commit  &&  git push
#      (so the next CI deploy preserves the HTTPS config)
#   2. docker service update --force minitwit_stack_nginx
#      (so nginx reloads with the new config)
#
# Renewal is automatic — certbot's systemd timer reissues the cert every 60
# days and the deploy hook reloads nginx.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <domain>" >&2
  exit 1
fi

DOMAIN="$1"

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root (try: sudo $0 $DOMAIN)" >&2
  exit 1
fi

# Locate the repo root (the directory that owns this script's grandparent).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX_CONF="$REPO_ROOT/nginx/nginx.conf"

if [[ ! -f "$NGINX_CONF" ]]; then
  echo "Cannot find $NGINX_CONF — run this script from the deployed repo on the manager droplet." >&2
  exit 1
fi

# 1. Make sure /var/www/certbot exists (the ACME challenge dir).
mkdir -p /var/www/certbot
chown -R root:root /var/www/certbot

# 2. Issue the cert via webroot mode. The running nginx container serves
#    /.well-known/acme-challenge/ from the same /var/www/certbot dir
#    (bind-mounted via docker-compose).
echo "==> Issuing Let's Encrypt cert for $DOMAIN..."
certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --non-interactive \
  --agree-tos \
  --email "admin@${DOMAIN}" \
  -d "${DOMAIN}"

# 3. Rewrite nginx.conf to the HTTPS-enabled version.
#    Single source of truth — this file is committed to git so subsequent
#    CI deploys preserve the HTTPS config instead of overwriting it.
echo "==> Rewriting $NGINX_CONF to HTTPS mode..."
cat > "$NGINX_CONF" <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    server_tokens off;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;

    resolver 127.0.0.11 valid=10s ipv6=off;

    # HTTP server: serves the ACME challenge for renewal, redirects everything
    # else to HTTPS.
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name ${DOMAIN};

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
            default_type "text/plain";
        }

        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    # HTTPS server: terminates TLS, proxies to the app on the swarm overlay.
    server {
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name ${DOMAIN};

        ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

        # Mozilla "intermediate" 2024 profile.
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;
        ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 1d;
        ssl_session_tickets off;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        location / {
            set \$upstream_app "tasks.minitwit:5000";
            proxy_pass http://\$upstream_app;

            proxy_http_version 1.1;
            proxy_set_header Host              \$host;
            proxy_set_header X-Real-IP         \$remote_addr;
            proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            proxy_connect_timeout 5s;
            proxy_read_timeout    30s;
            proxy_send_timeout    30s;
        }
    }
}
EOF

# 4. Install a renewal hook that reloads the swarm nginx after each renewal.
RENEWAL_HOOK=/etc/letsencrypt/renewal-hooks/deploy/reload-swarm-nginx.sh
mkdir -p "$(dirname "$RENEWAL_HOOK")"
cat > "$RENEWAL_HOOK" <<'EOF'
#!/bin/bash
# Triggered by certbot after every successful renewal.
docker service update --force minitwit_stack_nginx >/dev/null 2>&1 || true
EOF
chmod +x "$RENEWAL_HOOK"

# 5. Make sure the certbot renewal timer is on.
systemctl enable --now certbot.timer >/dev/null 2>&1 || true

cat <<EOF

==> TLS bootstrap done.

  Cert path:     /etc/letsencrypt/live/${DOMAIN}/
  nginx config:  ${NGINX_CONF}  (rewritten to HTTPS mode)

NEXT STEPS:
  1. Reload nginx so it serves over TLS:
       docker service update --force minitwit_stack_nginx

  2. Commit the updated nginx.conf so future CI deploys keep HTTPS:
       cd ${REPO_ROOT}
       git add nginx/nginx.conf
       git commit -m "Enable TLS for ${DOMAIN}"
       git push

  3. Verify:
       curl -I http://${DOMAIN}        # 301 to https
       curl -I https://${DOMAIN}       # 200
       https://www.ssllabs.com/ssltest/analyze.html?d=${DOMAIN}
EOF
