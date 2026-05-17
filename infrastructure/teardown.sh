#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${TF_VAR_do_token:-}" ]]; then
  echo "ERROR: TF_VAR_do_token is not set. Export your DigitalOcean token:"
  echo "  export TF_VAR_do_token=dop_v1_..."
  exit 1
fi

echo "==> Destroy plan:"
terraform plan -destroy -out=teardown.tfplan

read -r -p "Proceed with teardown? (yes/NO) " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  rm -f teardown.tfplan
  exit 0
fi

terraform apply teardown.tfplan
rm -f teardown.tfplan

echo
echo "==> Infra destroyed. The state file is still here (terraform.tfstate)."
echo "    Run infrastructure/bring-up.sh to bring everything back up."
