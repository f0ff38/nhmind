#!/usr/bin/env bash
# Ensure Selectel PTR points relay floating IP to RELAY_HOSTNAME, then verify propagation.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${PUBLIC_IP:-}" ]; then
  PUBLIC_IP="$(bash "${script_dir}/read-relay-public-ip.sh")"
  export PUBLIC_IP
fi

token="$(printf '%s' "${SELECTEL_STATIC_TOKEN:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [ -n "${token}" ]; then
  bash "${script_dir}/upsert-relay-ptr.sh"
else
  echo "::warning::SELECTEL_STATIC_TOKEN missing — skip PTR upsert; verifying existing PTR only"
fi

bash "${script_dir}/verify-relay-ptr.sh"
