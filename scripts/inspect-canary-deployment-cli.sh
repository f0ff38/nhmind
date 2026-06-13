#!/usr/bin/env bash
# Run `acurast deployments <id>` when modules/<module>/.acurast/deploy/*-<id>.json exists.
# Requires local deployment file (from deploy or downloaded GHA artifact).
# Usage: inspect-canary-deployment-cli.sh <module> <deployment_id>
# Env: INSPECT_CLI_FAIL=1 — exit non-zero on failure.
set -euo pipefail

module="${1:?usage: inspect-canary-deployment-cli.sh <module> <deployment_id>}"
deployment_id="${2:?usage: inspect-canary-deployment-cli.sh <module> <deployment_id>}"
fail_on_error="${INSPECT_CLI_FAIL:-0}"
canary_rpc="${ACURAST_RPC:-wss://public-rpc.canary.acurast.com}"
deploy_dir="modules/${module}/.acurast/deploy"

shopt -s nullglob
files=("${deploy_dir}"/*-"${deployment_id}".json)
if [ "${#files[@]}" -eq 0 ]; then
  echo "::notice::No local deployment file in ${deploy_dir} for id ${deployment_id}; skip acurast deployments detail"
  exit 0
fi

echo "=== acurast deployments ${deployment_id} --network canary (local .acurast/deploy) ==="
set +e
cli_out="$(
  docker compose run --rm \
    -e "ACURAST_RPC=${canary_rpc}" \
    -e "ACURAST_CANARY_RPC=${canary_rpc}" \
    dev bash -lc "cd modules/${module} && acurast deployments ${deployment_id} --network canary" 2>&1
)"
cli_exit=$?
set -e
printf '%s\n' "${cli_out}"

if [ "${cli_exit}" -ne 0 ]; then
  echo "::warning::acurast deployments ${deployment_id} failed (exit ${cli_exit})"
  if [ "${fail_on_error}" = "1" ]; then
    exit "${cli_exit}"
  fi
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Acurast CLI (\`deployments ${deployment_id}\`)"
    echo ""
    echo '```'
    printf '%s\n' "${cli_out}"
    echo '```'
    echo ""
  } >> "${GITHUB_STEP_SUMMARY}"
fi
