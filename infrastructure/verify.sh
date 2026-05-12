#!/usr/bin/env bash
# Post-apply sanity checks for the Terraform infra.
# Exits non-zero on the first failure so it can gate `bring-up.sh`.
#
# Covers three properties that a successful apply must hold:
#   1. Topology  — outputs match the expected manager/worker count
#   2. Health    — every swarm node reports Ready
#   3. Idempotency — a second `terraform plan` shows no diff

set -euo pipefail

cd "$(dirname "$0")"

EXPECTED_WORKERS="${EXPECTED_WORKERS:-2}"
pass() { echo "  [PASS] $*"; }
fail() { echo "  [FAIL] $*"; exit 1; }

echo "==> 1/3 Topology"
manager_ip=$(terraform output -raw manager_ip 2>/dev/null || true)
[[ -n "$manager_ip" ]] || fail "manager_ip output is empty — has 'terraform apply' run?"
pass "manager_ip = $manager_ip"

worker_count=$(terraform output -json worker_ips | python -c "import json,sys; print(len(json.load(sys.stdin)))")
[[ "$worker_count" == "$EXPECTED_WORKERS" ]] \
  || fail "expected $EXPECTED_WORKERS workers, got $worker_count"
pass "worker_count = $worker_count"

echo "==> 2/3 Swarm health"
ssh_key=$(terraform output -raw ssh_manager | sed -n 's/.*-i \([^ ]*\).*/\1/p')
expected_nodes=$((1 + EXPECTED_WORKERS))

# `docker node ls` only works on a manager, which is exactly where we're SSHing.
node_status=$(ssh -i "$ssh_key" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10 \
  "root@${manager_ip}" \
  'docker node ls --format "{{.Status}}"' 2>/dev/null || true)

ready_count=$(printf '%s\n' "$node_status" | grep -c '^Ready$' || true)
[[ "$ready_count" == "$expected_nodes" ]] \
  || fail "expected $expected_nodes Ready nodes, got $ready_count (raw: $node_status)"
pass "all $expected_nodes swarm nodes are Ready"

echo "==> 3/3 Idempotency"
# `terraform plan -detailed-exitcode` returns:
#   0 = no changes
#   1 = error
#   2 = changes pending → not idempotent
set +e
terraform plan -detailed-exitcode -input=false -out=/dev/null > /tmp/tf-idempotency.log 2>&1
plan_rc=$?
set -e
case "$plan_rc" in
  0) pass "second plan produced no diff" ;;
  2) fail "plan still has pending changes — provisioners aren't idempotent. See /tmp/tf-idempotency.log" ;;
  *) fail "terraform plan errored (exit $plan_rc). See /tmp/tf-idempotency.log" ;;
esac

echo
echo "==> All checks passed."
