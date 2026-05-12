#!/usr/bin/env bash
# Ricostruisce l'intera infra + deploya l'app. Pensato per il flusso
# pre-esame: dopo aver spento tutto con teardown.sh, basta un singolo
# command per essere di nuovo online.
#
# Sequenza:
#   1. terraform apply  → 3 droplet + swarm + firewall + (DNS opzionale)
#   2. estrae l'IP del manager dagli output Terraform
#   3. copia .env + docker-compose + scripts sul manager via scp
#   4. lancia deploy.sh sul manager (pull immagini, stack deploy)

set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${TF_VAR_do_token:-}" ]]; then
  echo "ERROR: TF_VAR_do_token non impostata."
  exit 1
fi

ENV_FILE="../.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: manca $ENV_FILE (DATABASE_URL, SECRET_KEY, ecc.)."
  exit 1
fi

echo "==> 1/4 terraform init (idempotente)"
terraform init -input=false

echo "==> 2/4 terraform apply"
terraform apply -auto-approve

MANAGER_IP=$(terraform output -raw manager_ip)
SSH_KEY=$(terraform output -raw ssh_manager | sed -n 's/.*-i \([^ ]*\).*/\1/p')

echo "==> 3/4 sync repo sul manager ($MANAGER_IP)"
# shellcheck disable=SC2086
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -r ../docker-compose.yml ../deploy.sh ../monitoring ../logging ../nginx ../scripts "$ENV_FILE" \
  "root@${MANAGER_IP}:/root/"

echo "==> 4/5 deploy stack sul manager"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "root@${MANAGER_IP}" "cd /root && bash deploy.sh"

echo "==> 5/5 verify (topology + swarm health + idempotency)"
./verify.sh

echo
echo "==> Up. Manager: http://${MANAGER_IP}/"
echo "    Per le dashboard interne: ssh -L 3000:127.0.0.1:3000 root@${MANAGER_IP}"
