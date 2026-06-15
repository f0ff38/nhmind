#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="acurast-example-smoke"
MODULE_DIR="modules/${MODULE}"
ACTION=""
NETWORK="mainnet"
SKIP_INSTALL="false"
SKIP_BUNDLE="false"
WEBHOOK_URL_VALUE="${WEBHOOK_URL:-}"

usage() {
  cat <<'EOF'
Usage: scripts/acurast-live-example-smoke.sh <setup|run> [options]

Run the official Acurast example smoke in Live Code mode from the Docker dev
container. This is a manual diagnostic path; it requires a live-code processor
and a transient deploy mnemonic in ACURAST_MNEMONIC.

Options:
  --network <canary|mainnet>  Acurast network (default: mainnet)
  --webhook-url <url>         Optional breadcrumb endpoint
  --skip-install             Do not run npm ci before live
  --skip-bundle              Do not rebuild dist/bundle.js before live
  -h, --help                 Show this help

Examples:
  ACURAST_MNEMONIC="..." scripts/acurast-live-example-smoke.sh setup --network mainnet
  ACURAST_MNEMONIC="..." scripts/acurast-live-example-smoke.sh run --network mainnet --skip-install
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    setup|run)
      ACTION="$1"
      shift
      ;;
    --network)
      NETWORK="${2:-}"
      shift 2
      ;;
    --webhook-url)
      WEBHOOK_URL_VALUE="${2:-}"
      shift 2
      ;;
    --skip-install)
      SKIP_INSTALL="true"
      shift
      ;;
    --skip-bundle)
      SKIP_BUNDLE="true"
      shift
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

if [ -z "${ACTION}" ]; then
  echo "Missing action: setup or run" >&2
  usage >&2
  exit 1
fi

case "${NETWORK}" in
  canary)
    RPC="wss://public-rpc.canary.acurast.com"
    ;;
  mainnet)
    RPC="wss://public-rpc.mainnet.acurast.com"
    ;;
  *)
    echo "Unknown network: ${NETWORK}" >&2
    exit 1
    ;;
esac

if [ -z "${ACURAST_MNEMONIC:-}" ]; then
  echo "Missing ACURAST_MNEMONIC in the host environment." >&2
  echo "Use a temporary shell variable; never commit mnemonics or module .env files." >&2
  exit 1
fi

cd "${ROOT_DIR}"

ENV_FILE="${MODULE_DIR}/.env"
CONFIG_FILE="${MODULE_DIR}/acurast.json"
ENV_BACKUP=""
CONFIG_BACKUP="$(mktemp)"

if [ -f "${ENV_FILE}" ]; then
  ENV_BACKUP="$(mktemp)"
  cp "${ENV_FILE}" "${ENV_BACKUP}"
fi
cp "${CONFIG_FILE}" "${CONFIG_BACKUP}"

cleanup() {
  cp "${CONFIG_BACKUP}" "${CONFIG_FILE}"
  rm -f "${CONFIG_BACKUP}"
  if [ -n "${ENV_BACKUP}" ]; then
    cp "${ENV_BACKUP}" "${ENV_FILE}"
    rm -f "${ENV_BACKUP}"
  else
    rm -f "${ENV_FILE}"
  fi
}
trap cleanup EXIT

docker compose build dev

docker compose run --rm --entrypoint node \
  -e "CONFIG_FILE=${CONFIG_FILE}" \
  -e "MODULE=${MODULE}" \
  -e "NETWORK=${NETWORK}" \
  dev \
  -e 'const { readFileSync, writeFileSync } = require("node:fs");
const configPath = process.env.CONFIG_FILE;
const config = JSON.parse(readFileSync(configPath, "utf8"));
const project = config.projects[process.env.MODULE];
project.network = process.env.NETWORK;
project.enableDevtools = true;
writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);'

webhook_url="$(printf '%s' "${WEBHOOK_URL_VALUE}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
{
  printf 'ACURAST_MNEMONIC=%s\n' "${ACURAST_MNEMONIC}"
  printf 'ACURAST_RPC=%s\n' "${RPC}"
  if [ "${NETWORK}" = "mainnet" ]; then
    printf 'ACURAST_MAINNET_RPC=%s\n' "${RPC}"
  else
    printf 'ACURAST_CANARY_RPC=%s\n' "${RPC}"
  fi
  printf 'WEBHOOK_URL=%s\n' "${webhook_url:-__NHMIND_NO_WEBHOOK__}"
} > "${ENV_FILE}"

if [ "${SKIP_INSTALL}" != "true" ]; then
  docker compose run --rm --entrypoint bash dev -lc "npm ci --prefix ${MODULE_DIR}"
fi

if [ "${SKIP_BUNDLE}" != "true" ]; then
  docker compose run --rm --entrypoint bash dev -lc "npm run bundle --prefix ${MODULE_DIR}"
fi

if [ "${ACTION}" = "setup" ]; then
  live_command="acurast live --setup"
else
  live_command="acurast live"
fi

echo "Running ${live_command} for ${MODULE} on ${NETWORK}."
echo "If setup asks for a live-code processor, follow the Acurast CLI prompt."

docker compose run --rm --entrypoint bash \
  -e "ACURAST_RPC=${RPC}" \
  -e "ACURAST_CANARY_RPC=${RPC}" \
  -e "ACURAST_MAINNET_RPC=${RPC}" \
  dev -lc "cd ${MODULE_DIR} && ${live_command}"
