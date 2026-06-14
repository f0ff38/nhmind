#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: write-canary-module-env.sh --module <hello|coordinator> [--mode deploy|inspect|devtools]

Writes modules/<module>/.env from GitHub environment variables.

Environment:
  MNEMONIC_HELLO / MNEMONIC_COORDINATOR / MNEMONIC_FALLBACK
  RELAY_HOSTNAME
  RELAY_URL_OVERRIDE        deploy mode only; hello A/B public relay
  HELLO_MINIMAL_SMOKE       deploy mode only; true sets HELLO_MINIMAL=1
  GITHUB_OUTPUT             optional; receives smoke relay outputs in deploy mode
EOF
}

MODULE=""
MODE="deploy"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --module)
      MODULE="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${MODULE}" ]; then
  echo "Missing --module" >&2
  usage >&2
  exit 1
fi

case "${MODE}" in
  deploy|inspect|devtools) ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    exit 1
    ;;
esac

case "${MODULE}" in
  hello) MNEMONIC="${MNEMONIC_HELLO:-${MNEMONIC_FALLBACK:-}}" ;;
  coordinator) MNEMONIC="${MNEMONIC_COORDINATOR:-${MNEMONIC_FALLBACK:-}}" ;;
  *) echo "Unknown module: ${MODULE}" >&2; exit 1 ;;
esac

if [ -z "${MNEMONIC}" ]; then
  echo "Missing mnemonic secret for ${MODULE}." >&2
  echo "Set ACURAST_MNEMONIC_${MODULE^^} or ACURAST_MNEMONIC in environment canary." >&2
  exit 1
fi

relay_url=""
smoke_hostname=""
relay_ab_mode="operator_relay"

if [ "${MODE}" = "deploy" ]; then
  relay_override="$(printf '%s' "${RELAY_URL_OVERRIDE:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -n "${relay_override}" ]; then
    if [ "${MODULE}" != "hello" ]; then
      echo "::error::relay_url_override is only supported for module hello" >&2
      exit 1
    fi
    if ! printf '%s' "${relay_override}" | grep -Eq '^wss://[^/[:space:]]+/?$'; then
      echo "::error::relay_url_override must be wss://<host>/ (e.g. wss://relay.damus.io/)" >&2
      exit 1
    fi
    relay_url="${relay_override%/}/"
    smoke_hostname="$(printf '%s' "${relay_url}" | sed -E 's|^wss://([^/]+)/?$|\1|' | tr '[:upper:]' '[:lower:]')"
    relay_ab_mode="public"
    echo "::notice::Hello A/B: RELAY_URL=${relay_url} (RELAY_SKIP_WHITELIST=1); smoke on ${smoke_hostname}"
  fi
fi

if [ -z "${relay_url}" ] && [ -n "${RELAY_HOSTNAME:-}" ]; then
  relay_hostname="$(printf '%s' "${RELAY_HOSTNAME}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s|/$||')"
  if ! printf '%s' "${relay_hostname}" | grep -Eq '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$'; then
    echo "::error::Invalid RELAY_HOSTNAME format (expected lowercase FQDN)" >&2
    exit 1
  fi
  relay_url="wss://${relay_hostname}/"
  smoke_hostname="${relay_hostname}"
  echo "RELAY_URL derived from RELAY_HOSTNAME (wss://<host>/)" >&2
fi

if [ "${MODE}" = "deploy" ] && [ -z "${relay_url}" ]; then
  echo "::error::Missing RELAY_HOSTNAME in environment canary (FQDN without scheme)" >&2
  exit 1
fi

ENV_FILE="modules/${MODULE}/.env"
printf 'ACURAST_MNEMONIC=%s\n' "${MNEMONIC}" > "${ENV_FILE}"

if [ "${MODE}" != "devtools" ]; then
  printf 'ACURAST_RPC=wss://public-rpc.canary.acurast.com\n' >> "${ENV_FILE}"
  printf 'ACURAST_CANARY_RPC=wss://public-rpc.canary.acurast.com\n' >> "${ENV_FILE}"
  printf 'ACURAST_CANARY_INDEXER=https://dev.indexer.canary.acurast.com/api/v1/rpc\n' >> "${ENV_FILE}"
  printf 'ACURAST_CANARY_INDEXER_API_KEY=OXuwySHqNSlwwa_qqB-cBw\n' >> "${ENV_FILE}"
fi

if [ -n "${relay_url}" ]; then
  printf 'RELAY_URL=%s\n' "${relay_url}" >> "${ENV_FILE}"
fi

if [ "${relay_ab_mode}" = "public" ]; then
  if [ "${MODULE}" = "hello" ]; then
    printf 'RELAY_SKIP_WHITELIST=1\n' >> "${ENV_FILE}"
  fi
elif [ "${MODULE}" = "hello" ]; then
  printf 'RELAY_SKIP_WHITELIST=0\n' >> "${ENV_FILE}"
fi

if [ "${MODULE}" = "coordinator" ] && [ "${MODE}" = "deploy" ]; then
  printf 'COORDINATOR_WATCH_MODULES=hello\n' >> "${ENV_FILE}"
fi

minimal_smoke="$(printf '%s' "${HELLO_MINIMAL_SMOKE:-false}" | tr '[:upper:]' '[:lower:]')"
if [ "${MODE}" = "deploy" ] && [ "${minimal_smoke}" = "true" ]; then
  if [ "${MODULE}" != "hello" ]; then
    echo "::error::minimal_smoke is only supported for module hello" >&2
    exit 1
  fi
  printf 'HELLO_MINIMAL=1\n' >> "${ENV_FILE}"
  echo "::notice::Hello minimal smoke: HELLO_MINIMAL=1 (no Nostr/network); heartbeat smoke skipped"
elif [ "${MODE}" = "deploy" ] && [ "${MODULE}" = "hello" ]; then
  printf 'HELLO_MINIMAL=0\n' >> "${ENV_FILE}"
fi

if [ "${MODE}" = "deploy" ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "smoke_relay_hostname=${smoke_hostname}"
    echo "relay_ab_mode=${relay_ab_mode}"
    echo "hello_minimal_smoke=${minimal_smoke}"
  } >> "${GITHUB_OUTPUT}"
fi
