#!/usr/bin/env bash
# Submit Acurast deploy without blocking CI on processor match/ack (can take 30+ min).
# Succeeds once deployment ID is registered on-chain; smoke verifies execution via relay.
set -euo pipefail

MODULE="${1:?usage: deploy-canary-acurast.sh <module> [dry_run]}"
DRY_RUN="${2:-false}"
DEPLOY_LOG="${DEPLOY_LOG:-/tmp/acurast-deploy.log}"
TIMEOUT_SEC="${ACURAST_DEPLOY_TIMEOUT_SEC:-300}"
NETWORK="${ACURAST_NETWORK:-canary}"
if [ "${NETWORK}" = "mainnet" ]; then
  RPC="${ACURAST_RPC:-wss://public-rpc.mainnet.acurast.com}"
else
  RPC="${ACURAST_RPC:-wss://public-rpc.canary.acurast.com}"
fi

DEPLOY_FLAGS="-n"
if [ "${DRY_RUN}" = "true" ]; then
  DEPLOY_FLAGS="${DEPLOY_FLAGS} --dry-run"
fi

: >"${DEPLOY_LOG}"
set +e
timeout --foreground "${TIMEOUT_SEC}" \
  docker compose run --rm \
    -e "ACURAST_RPC=${RPC}" \
    -e "ACURAST_CANARY_RPC=${RPC}" \
    -e "ACURAST_MAINNET_RPC=${RPC}" \
    dev bash -lc "cd modules/${MODULE} && acurast deploy ${DEPLOY_FLAGS}" \
  2>&1 | tee -a "${DEPLOY_LOG}"
deploy_exit=$?
set -e

parse_deployment_id() {
  local id=""
  id="$(grep -oE 'Deployment registered \(ID: [0-9]+' "${DEPLOY_LOG}" | tail -1 | grep -oE '[0-9]+' || true)"
  if [ -z "${id}" ]; then
    id="$(grep -oE 'Deployment registered \(DeploymentID: [0-9,]+' "${DEPLOY_LOG}" | tail -1 | grep -oE '[0-9,]+' | tr -d ',' || true)"
  fi
  printf '%s' "${id}"
}

deployment_id="$(parse_deployment_id)"

if [ -n "${deployment_id}" ]; then
  echo "deployment_id=${deployment_id}"
  if [ "${deploy_exit}" -eq 124 ]; then
    if grep -q "Waiting for deployment to be matched with processors" "${DEPLOY_LOG}"; then
      echo "::notice::Deploy registered (ID ${deployment_id}); stopped after ${TIMEOUT_SEC}s waiting for processor match (continues on-chain)"
    else
      echo "::notice::Deploy registered (ID ${deployment_id}); CLI stopped after ${TIMEOUT_SEC}s (processor pipeline continues on-chain)"
    fi
  elif [ "${deploy_exit}" -ne 0 ]; then
    echo "::warning::acurast deploy exited ${deploy_exit} but deployment_id=${deployment_id} was parsed"
  fi
  exit 0
fi

if [ "${DRY_RUN}" = "true" ] && [ "${deploy_exit}" -eq 0 ]; then
  echo "::notice::acurast deploy dry-run completed without on-chain registration"
  exit 0
fi

if [ "${deploy_exit}" -eq 124 ]; then
  echo "::error::acurast deploy timed out after ${TIMEOUT_SEC}s without on-chain registration"
  exit 1
fi

echo "::error::acurast deploy failed (exit ${deploy_exit}); no deployment ID in log"
if [ "${deploy_exit}" -ne 0 ]; then
  exit "${deploy_exit}"
fi
exit 1
