#!/usr/bin/env bash
# Spegne completamente l'infra (slide 33: "Can you also stop your systems
# so you don't pay…"). Conserva lo state file: il prossimo `bring-up.sh`
# ricostruisce esattamente la stessa topologia.
#
# Quello che NON viene distrutto:
#   - il database MySQL gestito (è esterno, gestito a mano in DO UI)
#   - i record DNS (verranno ricreati al prossimo apply se var.domain_name
#     è impostata)
#   - il volume Spaces eventuale per lo state remoto

set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${TF_VAR_do_token:-}" ]]; then
  echo "ERROR: TF_VAR_do_token non impostata. Esporta il token DigitalOcean:"
  echo "  export TF_VAR_do_token=dop_v1_..."
  exit 1
fi

echo "==> Plan di destroy:"
terraform plan -destroy -out=teardown.tfplan

read -r -p "Procedere con il teardown? (yes/NO) " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Abortito."
  rm -f teardown.tfplan
  exit 0
fi

terraform apply teardown.tfplan
rm -f teardown.tfplan

echo
echo "==> Infra distrutta. Lo state file è ancora qui (terraform.tfstate)."
echo "    Esegui infrastructure/bring-up.sh per ricreare tutto."
