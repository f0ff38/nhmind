#!/usr/bin/env bash
# Print Acurast DevTools dashboard URL for a canary deployment (CI summary + stdout).
# 1) Parse deploy log  2) fallback: acurast devtools <deployment_id> in dev container
set -euo pipefail

module="${1:?usage: print-canary-devtools-url.sh <module> <deployment_id> [deploy_log]}"
deployment_id="${2:?usage: print-canary-devtools-url.sh <module> <deployment_id> [deploy_log]}"
deploy_log="${3:-/tmp/acurast-deploy.log}"

extract_url() {
  grep -oE 'https://devtools\.acurast\.com[^[:space:]]*' <<<"$1" | tail -1 || true
}

url=""
if [ -f "${deploy_log}" ]; then
  url="$(extract_url "$(cat "${deploy_log}")")"
fi

if [ -z "${url}" ]; then
  echo "DevTools URL not in deploy log; running acurast devtools ${deployment_id}..."
  cli_out="$(
    docker compose run --rm \
      -e ACURAST_CANARY_RPC=wss://public-rpc.canary.acurast.com \
      dev bash -lc "cd modules/${module} && acurast devtools ${deployment_id}" 2>&1 || true
  )"
  echo "${cli_out}"
  url="$(extract_url "${cli_out}")"
fi

if [ -z "${url}" ]; then
  echo "::warning::Could not obtain DevTools URL (deploy log + acurast devtools fallback)"
  exit 0
fi

echo "devtools_url=${url}"
echo "DevTools URL: ${url}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Acurast DevTools"
    echo ""
    echo "- **Module:** \`${module}\`"
    echo "- **Deployment ID:** \`${deployment_id}\`"
    echo ""
    echo "Open in browser when [api.devtools.acurast.com](https://api.devtools.acurast.com) is up (502 may be transient):"
    echo ""
    echo "[${url}](${url})"
  } >> "${GITHUB_STEP_SUMMARY}"
fi
