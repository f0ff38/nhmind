#!/usr/bin/env bash
# Sync infra/nostr-relay to VM, pull TLS from Selectel Knox, start compose.
set -euo pipefail

host="${1:?usage: deploy-remote.sh <ssh-host>}"
relay_hostname="${2:?usage: deploy-remote.sh <ssh-host> <relay-hostname>}"
ssh_user="${RELAY_SSH_USER:-deploy}"
install_dir="/opt/nhmind-relay"

if [ -z "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}" ]; then
  echo "::error::RELAY_DEPLOY_SSH_PRIVATE_KEY is required"
  exit 1
fi

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} — source prepare-openstack-env.sh before deploy-remote.sh"
    exit 1
  fi
done

key_file="$(mktemp)"
trap 'rm -rf "${key_file}" "${tls_dir:-}"' EXIT
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
selectel_scripts="$(cd "${relay_root}/../selectel/scripts" && pwd)"

knox_cert_id="$(bash "${selectel_scripts}/issue-relay-le-cert.sh")"
tls_dir="$(mktemp -d)"
bash "${selectel_scripts}/fetch-relay-tls-pem.sh" "${tls_dir}" "${knox_cert_id}"

ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "sudo mkdir -p ${install_dir}/certs && sudo chown ${ssh_user}:${ssh_user} ${install_dir} ${install_dir}/certs"

tar -C "${relay_root}" \
  --exclude='./scripts/deploy-remote.sh' \
  --exclude='./certs' \
  -czf - . | ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "tar xzf - -C ${install_dir}"

scp "${ssh_opts[@]}" "${tls_dir}/fullchain.pem" "${tls_dir}/privkey.pem" \
  "${ssh_user}@${host}:${install_dir}/certs/"

printf 'RELAY_HOSTNAME=%s\n' "${relay_hostname}" | \
  ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "cat > ${install_dir}/.env"

ssh "${ssh_opts[@]}" "${ssh_user}@${host}" \
  "chmod +x ${install_dir}/scripts/bootstrap-relay.sh && bash ${install_dir}/scripts/bootstrap-relay.sh ${install_dir}"

echo "Deploy finished: https://${relay_hostname}/ (WSS wss://${relay_hostname}/)"
