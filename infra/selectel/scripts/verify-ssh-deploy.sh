#!/usr/bin/env bash
# SSH connectivity to relay VM (deploy stage, after provision).
set -euo pipefail

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

host="$(trim "${RELAY_SSH_HOST:-}")"
user="$(trim "${RELAY_SSH_USER:-deploy}")"
private_key="$(trim "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}")"

if [ -z "${host}" ] || [ -z "${private_key}" ]; then
  echo "::error::RELAY_SSH_HOST and RELAY_DEPLOY_SSH_PRIVATE_KEY are required"
  exit 1
fi

key_file="$(mktemp)"
trap 'rm -f "${key_file}"' EXIT
umask 077
printf '%s\n' "${private_key}" > "${key_file}"

if ssh -i "${key_file}" \
  -o BatchMode=yes \
  -o ConnectTimeout=15 \
  -o StrictHostKeyChecking=accept-new \
  "${user}@${host}" "echo relay-ssh-ok" 2>/dev/null | grep -q relay-ssh-ok; then
  echo "Relay SSH OK (${user}@${host}:22, key auth)"
  exit 0
fi

echo "::error::SSH to ${user}@${host} failed (timeout, key rejected, or port 22 blocked)"
echo "Checklist:"
echo "  - RELAY_SSH_HOST is floating IP from terraform output"
echo "  - Security group allows 0.0.0.0/0:22 and deploy user has RELAY_DEPLOY_SSH_PUBLIC_KEY"
echo "  - VM finished cloud-init (wait a few minutes after apply)"
exit 1
