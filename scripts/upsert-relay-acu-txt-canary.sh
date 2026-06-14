#!/usr/bin/env bash
# Upsert _acu.<relay-hostname> TXT for hello + coordinator deploy wallets (canary deploy).
set -euo pipefail

relay_hostname="${RELAY_HOSTNAME:-}"
relay_hostname="$(printf '%s' "${relay_hostname}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s|/$||')"

if [ -z "${relay_hostname}" ]; then
  echo "::error::RELAY_HOSTNAME is required"
  exit 1
fi

if [ -z "${SELECTEL_SERVICE_USER:-}" ] || [ -z "${SELECTEL_SERVICE_PASSWORD:-}" ]; then
  echo "::warning::SELECTEL DNS secrets missing in canary; skip _acu TXT upsert (configure manually)"
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

export PREPARE_OPENSTACK_EXPORT=1
# shellcheck disable=SC1091
source infra/selectel/scripts/prepare-openstack-env.sh

txt_values="$(bash scripts/compute-relay-acu-txt-values.sh 2>/dev/null || true)"
txt_values="$(printf '%s' "${txt_values}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [ -z "${txt_values}" ]; then
  echo "::warning::No deploy mnemonics available; skip _acu TXT upsert"
  exit 0
fi

export RELAY_HOSTNAME="${relay_hostname}"
export ACURAST_TXT_V="${txt_values}"
bash infra/selectel/scripts/upsert-relay-acu-txt.sh
