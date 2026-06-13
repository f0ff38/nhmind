#!/usr/bin/env bash
# Query Acurast deployment status via CLI (alternative to Hub UI).
# Usage: inspect-canary-deployments.sh <module> [deployment_id]
#   deployment_id — Hub numeric ID (e.g. 378420); optional (list only if omitted).
# Env: INSPECT_DEPLOYMENTS_FAIL=1 — exit non-zero when CLI fails (standalone GHA workflow).
set -euo pipefail

module="${1:?usage: inspect-canary-deployments.sh <module> [deployment_id]}"
deployment_id="${2:-}"
fail_on_error="${INSPECT_DEPLOYMENTS_FAIL:-0}"

run_cli() {
  docker compose run --rm \
    -e ACURAST_CANARY_RPC=wss://public-rpc.canary.acurast.com \
    dev bash -lc "cd modules/${module} && $*"
}

append_summary_section() {
  local title="$1"
  local body="$2"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## ${title}"
      echo ""
      echo '```text'
      printf '%s\n' "${body}"
      echo '```'
      echo ""
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
}

cli_failed() {
  local label="$1"
  local exit_code="$2"
  echo "::warning::${label} failed (exit ${exit_code})"
  if [ "${fail_on_error}" = "1" ]; then
    exit "${exit_code}"
  fi
}

wallet_addr=""
wallet_addr="$(docker compose run --rm dev bash -lc "node scripts/show-acurast-address.mjs modules/${module}" 2>/dev/null || true)"
if [ -n "${wallet_addr}" ]; then
  echo "Deploy wallet: ${wallet_addr}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "- **Wallet:** \`${wallet_addr}\`" >> "${GITHUB_STEP_SUMMARY}"
    echo "" >> "${GITHUB_STEP_SUMMARY}"
  fi
fi

echo "=== acurast deployments ls --network canary (module=${module}) ==="
set +e
ls_out="$(run_cli "acurast deployments ls --network canary" 2>&1)"
ls_exit=$?
set -e
printf '%s\n' "${ls_out}"
append_summary_section "Acurast deployments ls (canary)" "${ls_out}"
if [ "${ls_exit}" -ne 0 ]; then
  cli_failed "acurast deployments ls" "${ls_exit}"
fi

if [ -z "${deployment_id}" ]; then
  exit 0
fi

full_id=""
full_id="$(printf '%s\n' "${ls_out}" | grep -oE "Acurast:[^[:space:]]+:${deployment_id}" | head -1 || true)"
if [ -z "${full_id}" ] && [ -n "${wallet_addr}" ]; then
  full_id="Acurast:${wallet_addr}:${deployment_id}"
fi
if [ -z "${full_id}" ]; then
  full_id="${deployment_id}"
fi

echo "=== acurast deployments ${full_id} ==="
set +e
detail_out="$(run_cli "acurast deployments ${full_id}" 2>&1)"
detail_exit=$?
set -e
printf '%s\n' "${detail_out}"
append_summary_section "Deployment ${deployment_id}" "${detail_out}"
if [ "${detail_exit}" -ne 0 ]; then
  cli_failed "acurast deployments ${full_id}" "${detail_exit}"
fi
