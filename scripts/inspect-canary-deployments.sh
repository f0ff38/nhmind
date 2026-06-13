#!/usr/bin/env bash
# CLI/SDK canary deployment diagnostics (no DevTools web).
# 1) SDK: indexer + on-chain RPC (works without local .acurast file)
# 2) CLI: acurast deployments <id> when modules/<module>/.acurast/deploy/*-<id>.json exists
# Usage: inspect-canary-deployments.sh <module> [deployment_id]
# Env: INSPECT_DEPLOYMENTS_FAIL=1 — exit non-zero on SDK failure (standalone GHA workflow).
set -euo pipefail

module="${1:?usage: inspect-canary-deployments.sh <module> [deployment_id]}"
deployment_id="${2:-}"
fail_on_error="${INSPECT_DEPLOYMENTS_FAIL:-0}"
canary_rpc="${ACURAST_RPC:-wss://public-rpc.canary.acurast.com}"
canary_indexer="${ACURAST_CANARY_INDEXER:-https://dev.indexer.canary.acurast.com/api/v1/rpc}"
canary_indexer_key="${ACURAST_CANARY_INDEXER_API_KEY:-OXuwySHqNSlwwa_qqB-cBw}"

sdk_args=(--module "${module}" --network canary)
if [ -n "${deployment_id}" ]; then
  sdk_args+=(--deployment-id "${deployment_id}")
fi

echo "=== fetch-acurast-deployment-status.mjs (module=${module}${deployment_id:+, id=${deployment_id}}) ==="
set +e
sdk_out="$(
  docker compose run --rm \
    -e "ACURAST_RPC=${canary_rpc}" \
    -e "ACURAST_CANARY_RPC=${canary_rpc}" \
    -e "ACURAST_CANARY_INDEXER=${canary_indexer}" \
    -e "ACURAST_CANARY_INDEXER_API_KEY=${canary_indexer_key}" \
    dev node scripts/fetch-acurast-deployment-status.mjs "${sdk_args[@]}" 2>&1
)"
sdk_exit=$?
set -e
printf '%s\n' "${sdk_out}"

if [ "${sdk_exit}" -ne 0 ]; then
  echo "::warning::fetch-acurast-deployment-status failed (exit ${sdk_exit})"
  if [ "${fail_on_error}" = "1" ]; then
    exit "${sdk_exit}"
  fi
fi

if [ -n "${deployment_id}" ]; then
  bash scripts/inspect-canary-deployment-cli.sh "${module}" "${deployment_id}" \
    || echo "::warning::CLI deployment detail failed"
fi
