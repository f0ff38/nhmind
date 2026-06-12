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
  label_count="$(printf '%s' "${relay_hostname}" | tr -cd '.' | wc -c | tr -d ' ')"
  if [ "${label_count}" -le 1 ]; then
    certbot_email="ops@${relay_hostname}"
  else
    certbot_email="ops@${relay_hostname#*.}"
  fi
fi

export RELAY_HOSTNAME="${relay_hostname}"

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  echo "Installing Docker Compose v2 plugin (docker.io has no compose plugin package)..."
  local version="v2.32.4"
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) arch="x86_64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    *)
      echo "::error::Unsupported architecture for Docker Compose: ${arch}"
      exit 1
      ;;
  esac

  local plugin_dir="/usr/local/lib/docker/cli-plugins"
  sudo mkdir -p "${plugin_dir}"
  sudo curl -fsSL \
    "https://github.com/docker/compose/releases/download/${version}/docker-compose-linux-${arch}" \
    -o "${plugin_dir}/docker-compose"
  sudo chmod +x "${plugin_dir}/docker-compose"
  docker compose version
}

ensure_acme_http_ingress() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  if sudo ufw status | grep -Eq '^80/tcp'; then
    return 0
  fi
  echo "Opening UFW port 80 for ACME HTTP-01..."
  sudo ufw allow 80/tcp comment 'certbot HTTP-01'
}

ensure_docker_compose
ensure_acme_http_ingress

init_relay_data_dir() {
  docker compose run --rm --user root --entrypoint sh relay \
    -c 'mkdir -p /usr/src/app/db && chown -R 100:100 /usr/src/app/db'
}

init_relay_data_dir

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
if ! docker compose ps relay 2>/dev/null | grep -qE 'Up [0-9]'; then
  echo "::warning::nostr-rs-relay is not healthy — container logs:"
  docker compose logs relay --tail 40 2>/dev/null || true
  exit 1
fi
echo "Relay stack is up for ${relay_hostname}"
