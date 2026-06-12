#!/usr/bin/env bash
# Compute space-separated v= TXT values for hello + coordinator deploy wallets.
set -euo pipefail

relay_hostname="${RELAY_HOSTNAME:-}"
relay_hostname="$(printf '%s' "${relay_hostname}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s|/$||')"

if [ -z "${relay_hostname}" ]; then
  echo "::error::RELAY_HOSTNAME is required"
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

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
  echo "::error::No deploy mnemonics in canary environment"
  exit 1
fi

printf '%s' "${txt_values[*]}"
