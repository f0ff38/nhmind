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

declare -a txt_values=()

compute_txt() {
  local mnemonic="$1"
  docker compose run --rm \
    -e "ACURAST_MNEMONIC=${mnemonic}" \
    dev bash -lc "
      set -euo pipefail
      npm install --prefix scripts --silent --no-fund --no-audit
      node scripts/compute-acu-txt-v.mjs --from-mnemonic '${relay_hostname}'
    "
}

for var in ACURAST_MNEMONIC_HELLO ACURAST_MNEMONIC_COORDINATOR ACURAST_MNEMONIC; do
  mnemonic="$(printenv "${var}" 2>/dev/null || true)"
  mnemonic="$(printf '%s' "${mnemonic}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "${mnemonic}" ]; then
    continue
  fi
  txt="$(compute_txt "${mnemonic}")"
  case " ${txt_values[*]:-} " in
    *" ${txt} "*) ;;
    *) txt_values+=("${txt}") ;;
  esac
done

if [ "${#txt_values[@]}" -eq 0 ]; then
  echo "::warning::No deploy mnemonics available; skip _acu TXT upsert"
  exit 0
fi

export RELAY_HOSTNAME="${relay_hostname}"
export ACURAST_TXT_V="${txt_values[*]}"
bash infra/selectel/scripts/upsert-relay-acu-txt.sh
