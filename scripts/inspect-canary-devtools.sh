#!/usr/bin/env bash
# Fetch Acurast DevTools logs from CI (GitHub Actions). See fetch-acurast-devtools-logs.mjs.
set -euo pipefail

module="${1:?usage: inspect-canary-devtools.sh <module> <job-id> [wait-ms]}"
job_id="${2:?usage: inspect-canary-devtools.sh <module> <job-id> [wait-ms]}"
wait_ms="${3:-0}"
poll_ms="${POLL_MS:-15000}"
timeout_ms="${DEVTOOLS_TIMEOUT_MS:-120000}"

echo "DevTools inspect: module=${module} job_id=${job_id} wait_ms=${wait_ms}"

docker compose run --rm \
  -e "INSPECT_WAIT_MS=${wait_ms}" \
  -e "DEVTOOLS_TIMEOUT_MS=${timeout_ms}" \
  -e "POLL_MS=${poll_ms}" \
  dev bash -lc "node scripts/fetch-acurast-devtools-logs.mjs --module ${module} --job-id ${job_id} --wait-ms ${wait_ms} --poll-ms ${poll_ms} --timeout-ms ${timeout_ms}"
