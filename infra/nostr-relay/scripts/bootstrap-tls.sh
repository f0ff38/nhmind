#!/usr/bin/env bash
# Run on relay VM after files are synced to /opt/nhmind-relay.
set -euo pipefail

install_dir="${1:-/opt/nhmind-relay}"
cd "${install_dir}"

if [ ! -f .env ]; then
  echo "::error::Missing ${install_dir}/.env (RELAY_HOSTNAME, CERTBOT_EMAIL)"
  exit 1
fi

# shellcheck disable=SC1091
source .env

relay_hostname="$(printf '%s' "${RELAY_HOSTNAME:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
certbot_email="${CERTBOT_EMAIL:-}"

if [ -z "${relay_hostname}" ]; then
  echo "::error::RELAY_HOSTNAME is required in .env"
  exit 1
fi

if [ -z "${certbot_email}" ]; then
  domain="${relay_hostname#*.}"
  certbot_email="ops@${domain}"
fi

export RELAY_HOSTNAME="${relay_hostname}"

if ! docker compose version >/dev/null 2>&1; then
  echo "Installing docker compose plugin..."
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
fi

cert_exists() {
  docker compose --profile certbot run --rm --entrypoint sh certbot \
    -c "test -f /etc/letsencrypt/live/${relay_hostname}/fullchain.pem"
}

ensure_http_nginx() {
  cp nginx/nginx.http-only.conf nginx/active.conf
  docker compose up -d relay nginx
}

issue_certificate() {
  echo "Requesting Let's Encrypt certificate for ${relay_hostname}..."
  docker compose --profile certbot run --rm certbot certonly \
    --webroot \
    -w /var/www/certbot \
    -d "${relay_hostname}" \
    --email "${certbot_email}" \
    --agree-tos \
    --no-eff-email \
    --non-interactive
}

activate_https_nginx() {
  sed "s/\${RELAY_HOSTNAME}/${relay_hostname}/g" nginx/nginx.conf.template > nginx/active.conf
  docker compose up -d relay nginx
  docker compose exec -T nginx nginx -s reload 2>/dev/null || true
}

if cert_exists; then
  echo "TLS certificate already present for ${relay_hostname}"
else
  ensure_http_nginx
  issue_certificate
fi

activate_https_nginx
docker compose ps
echo "Relay stack is up for ${relay_hostname}"
