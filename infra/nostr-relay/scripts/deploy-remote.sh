#!/usr/bin/env bash
# Sync infra/nostr-relay to VM and start compose (called from deploy-relay GHA).
set -euo pipefail

host="${1:?usage: deploy-remote.sh <ssh-host>}"
relay_hostname="${2:?usage: deploy-remote.sh <ssh-host> <relay-hostname>}"
certbot_email="${3:-}"
ssh_user="${RELAY_SSH_USER:-deploy}"
install_dir="/opt/nhmind-relay"

if [ -z "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}" ]; then
  echo "::error::RELAY_DEPLOY_SSH_PRIVATE_KEY is required"
  exit 1
fi

key_file="$(mktemp)"
trap 'rm -f "${key_file}"' EXIT
umask 077
printf '%s\n' "${RELAY_DEPLOY_SSH_PRIVATE_KEY}" > "${key_file}"

ssh_opts=(
  -i "${key_file}"
  -o BatchMode=yes
  -o ConnectTimeout=30
  -o StrictHostKeyChecking=accept-new
)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
relay_root="$(cd "${script_dir}/.." && pwd)"

ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "sudo mkdir -p ${install_dir} && sudo chown ${ssh_user}:${ssh_user} ${install_dir}"

tar -C "${relay_root}" \
  --exclude='./scripts/deploy-remote.sh' \
  -czf - . | ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "tar xzf - -C ${install_dir}"

env_body="RELAY_HOSTNAME=${relay_hostname}"
if [ -n "${certbot_email}" ]; then
  env_body="${env_body}
CERTBOT_EMAIL=${certbot_email}"
fi
printf '%s\n' "${env_body}" | ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "cat > ${install_dir}/.env"

ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "chmod +x ${install_dir}/scripts/bootstrap-tls.sh && bash ${install_dir}/scripts/bootstrap-tls.sh ${install_dir}"

echo "Deploy finished: https://${relay_hostname}/ (WSS wss://${relay_hostname}/)"
