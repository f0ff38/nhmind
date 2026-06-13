#!/usr/bin/env bash
# Verify _acu.<RELAY_HOSTNAME> TXT records match expected v= values (Acurast forward whitelist).
set -euo pipefail

normalize_hostname() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/\.$//'
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

relay_host="$(normalize_hostname "$(trim "${RELAY_HOSTNAME:-}")")"
expected_raw="$(trim "${ACURAST_TXT_V:-}")"
retries="${VERIFY_ACU_TXT_RETRIES:-12}"
sleep_sec="${VERIFY_ACU_TXT_SLEEP_SEC:-10}"

if [ -z "${relay_host}" ]; then
  echo "::error::RELAY_HOSTNAME is required"
  exit 1
fi

if [ -z "${expected_raw}" ]; then
  echo "::error::ACURAST_TXT_V is required (space-separated v=... values)"
  exit 1
fi

if ! command -v dig >/dev/null 2>&1; then
  echo "::error::dig is required"
  exit 1
fi

declare -a expected_values=()
while IFS= read -r line; do
  value="$(trim "${line}")"
  if [ -n "${value}" ]; then
    expected_values+=("${value}")
  fi
done <<EOF
$(printf '%s' "${expected_raw}" | tr ' ' '\n')
EOF

if [ "${#expected_values[@]}" -eq 0 ]; then
  echo "::error::No expected v= values"
  exit 1
fi

lookup_txt() {
  dig +short TXT "_acu.${relay_host}" 2>/dev/null | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

attempt=1
while [ "${attempt}" -le "${retries}" ]; do
  declare -a found_values=()
  while IFS= read -r line; do
    value="$(trim "${line}")"
    if [ -n "${value}" ]; then
      found_values+=("${value}")
    fi
  done <<EOF
$(lookup_txt)
EOF

  missing=0
  for want in "${expected_values[@]}"; do
    case " ${found_values[*]:-} " in
      *" ${want} "*) ;;
      *)
        missing=1
        break
        ;;
    esac
  done

  if [ "${missing}" -eq 0 ]; then
    echo "TXT OK: _acu.${relay_host} contains ${#expected_values[@]} expected v= record(s)"
    exit 0
  fi

  echo "TXT _acu.${relay_host} missing expected v= (attempt ${attempt}/${retries}); found: ${found_values[*]:-none}"
  sleep "${sleep_sec}"
  attempt=$((attempt + 1))
done

echo "::error::_acu.${relay_host} TXT does not contain expected v= values after ${retries} attempts"
exit 1
