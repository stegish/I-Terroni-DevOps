#!/usr/bin/env bash
# Rebuild the whole infra + deploy the app. Designed for the pre-exam flow:
# after a full teardown.sh, a single command takes us back online.
#
# Sequence:
#   1. terraform apply  -> 3 droplets + swarm + firewall
#   2. extract the manager IP from Terraform outputs
#   3. scp .env + docker-compose + scripts to the manager
#   4. run deploy.sh on the manager (pull images, stack deploy)

set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${TF_VAR_do_token:-}" ]]; then
  echo "ERROR: TF_VAR_do_token is not set."
  exit 1
fi

ENV_FILE="../.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE (DATABASE_URL, SECRET_KEY, etc.)."
  exit 1
fi

echo "==> 1/4 terraform init (idempotent)"
terraform init -input=false

echo "==> 2/4 terraform apply"
terraform apply -auto-approve

MANAGER_IP=$(terraform output -raw manager_ip)
SSH_KEY=$(terraform output -raw ssh_manager | sed -n 's/.*-i \([^ ]*\).*/\1/p')

echo "==> 3/4 sync repo to the manager ($MANAGER_IP)"
# shellcheck disable=SC2086
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -r ../docker-compose.yml ../deploy.sh ../monitoring ../logging ../nginx ../scripts "$ENV_FILE" \
  "root@${MANAGER_IP}:/root/"

echo "==> 4/4 deploy stack on the manager"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "root@${MANAGER_IP}" "cd /root && bash deploy.sh"

echo
echo "==> Up. Manager: http://${MANAGER_IP}/"
echo "    For internal dashboards: ssh -L 3000:127.0.0.1:3000 root@${MANAGER_IP}"
