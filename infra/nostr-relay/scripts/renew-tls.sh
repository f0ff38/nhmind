#!/usr/bin/env bash
# Pull current Selectel Knox TLS PEM and reload nginx on the relay VM.
set -euo pipefail

host="${1:?usage: renew-tls.sh <ssh-host> <relay-hostname>}"
relay_hostname="${2:?usage: renew-tls.sh <ssh-host> <relay-hostname>}"
ssh_user="${RELAY_SSH_USER:-deploy}"
install_dir="/opt/nhmind-relay"

if [ -z "${RELAY_DEPLOY_SSH_PRIVATE_KEY:-}" ]; then
  echo "::error::RELAY_DEPLOY_SSH_PRIVATE_KEY is required"
  exit 1
fi

for var in OS_DOMAIN_NAME OS_USERNAME OS_PASSWORD OS_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::Missing ${var} — source prepare-openstack-env.sh before renew-tls.sh"
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

ssh "${ssh_opts[@]}" "${ssh_user}@${host}" "sudo mkdir -p ${install_dir}/certs && sudo chown ${ssh_user}:${ssh_user} ${install_dir}/certs"
scp "${ssh_opts[@]}" "${tls_dir}/fullchain.pem" "${tls_dir}/privkey.pem" \
  "${ssh_user}@${host}:${install_dir}/certs/"

ssh "${ssh_opts[@]}" "${ssh_user}@${host}" \
  "cd ${install_dir} && chmod 600 certs/fullchain.pem certs/privkey.pem && docker compose exec -T nginx nginx -s reload"

echo "TLS renewed and nginx reloaded for https://${relay_hostname}/"
