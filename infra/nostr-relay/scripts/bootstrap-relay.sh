#!/usr/bin/env bash
# Run on relay VM after files and TLS PEM are synced to /opt/nhmind-relay.
set -euo pipefail

install_dir="${1:-/opt/nhmind-relay}"
cd "${install_dir}"

if [ ! -f .env ]; then
  echo "::error::Missing ${install_dir}/.env (RELAY_HOSTNAME)"
  exit 1
fi

# shellcheck disable=SC1091
source .env

relay_hostname="$(printf '%s' "${RELAY_HOSTNAME:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [ -z "${relay_hostname}" ]; then
  echo "::error::RELAY_HOSTNAME is required in .env"
  exit 1
fi

if [ ! -f certs/fullchain.pem ] || [ ! -f certs/privkey.pem ]; then
  echo "::error::Missing certs/fullchain.pem or certs/privkey.pem (sync from Selectel Knox)"
  exit 1
fi

chmod 600 certs/fullchain.pem certs/privkey.pem

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

init_relay_data_dir() {
  docker compose run --rm --user root --entrypoint sh relay \
    -c 'mkdir -p /usr/src/app/db && chown -R 100:100 /usr/src/app/db'
}

close_legacy_http_ingress() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  if sudo ufw status | grep -Eq '^80/tcp'; then
    echo "Removing legacy UFW rule for port 80 (TLS is Selectel LE, not certbot)..."
    sudo ufw delete allow 80/tcp || true
  fi
}

ensure_docker_compose
close_legacy_http_ingress
init_relay_data_dir

sed "s/\${RELAY_HOSTNAME}/${relay_hostname}/g" nginx/nginx.conf.template > nginx/active.conf
docker compose up -d --force-recreate relay http-bridge nginx
docker compose exec -T nginx nginx -s reload 2>/dev/null || true

wait_for_service() {
  local service="$1"
  local attempts=24
  local attempt=1
  while [ "${attempt}" -le "${attempts}" ]; do
    container_id="$(docker compose ps -q "${service}" 2>/dev/null || true)"
    status=""
    if [ -n "${container_id}" ]; then
      status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container_id}" 2>/dev/null || true)"
    fi
    if [ "${status}" = "healthy" ] || [ "${status}" = "running" ]; then
      return 0
    fi
    echo "Waiting for ${service} health (${status:-unknown}) ${attempt}/${attempts}..."
    sleep 5
    attempt=$((attempt + 1))
  done
  echo "::warning::${service} is not healthy — container logs:"
  docker compose logs "${service}" --tail 40 2>/dev/null || true
  return 1
}

docker compose ps
wait_for_service relay
wait_for_service http-bridge
wait_for_service nginx
echo "Relay stack is up for ${relay_hostname} (TLS from Selectel Knox)"
