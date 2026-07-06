#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/substore-free-node}"
PORT="${PORT:-3001}"
BIND_IP="${BIND_IP:-0.0.0.0}"
IMAGE="${IMAGE:-xream/sub-store:http-meta}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[%s] %s\n' "$1" "$2"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    die "Docker Compose is not available."
  fi
}

install_basic_tools() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y curl ca-certificates openssl tar gzip
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates openssl tar gzip
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates openssl tar gzip
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl ca-certificates openssl tar gzip
  fi
}

start_docker_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
  fi
  if command -v service >/dev/null 2>&1; then
    service docker start >/dev/null 2>&1 || true
  fi

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  die "Docker is installed but the daemon is not running. Run: systemctl status docker"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "1/6" "Docker already installed, checking daemon..."
    start_docker_service
    return 0
  fi

  log "1/6" "Installing Docker..."
  install_basic_tools
  curl -fsSL https://get.docker.com | sh
  start_docker_service
}

install_compose_standalone() {
  local arch os url
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    armv7l) arch="armv7" ;;
    *) die "Unsupported CPU architecture for Docker Compose: $(uname -m)" ;;
  esac

  url="https://github.com/docker/compose/releases/latest/download/docker-compose-${os}-${arch}"
  curl -fL "$url" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
}

ensure_compose() {
  if docker compose version >/dev/null 2>&1; then
    log "2/6" "Docker Compose v2 plugin already installed."
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    log "2/6" "Legacy docker-compose already installed."
    return 0
  fi

  log "2/6" "Docker exists but Compose is missing, installing Compose..."
  install_basic_tools

  if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y docker-compose-plugin || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y docker-compose-plugin || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y docker-compose-plugin || true
  fi

  if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
    return 0
  fi

  log "2/6" "Package manager did not provide Compose, installing standalone binary..."
  install_compose_standalone

  if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
    return 0
  fi

  die "Failed to install Docker Compose."
}

generate_backend_path() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 12
  else
    date +%s%N | sha256sum | awk '{print substr($1,1,24)}'
  fi
}

copy_project_files() {
  [ -f "$SCRIPT_DIR/sources.txt" ] || die "Missing sources.txt in project directory."
  [ -f "$SCRIPT_DIR/operators/01_fetch_today_clean.js" ] || die "Missing operators/01_fetch_today_clean.js."
  [ -f "$SCRIPT_DIR/operators/02_httpmeta_speed_filter.js" ] || die "Missing operators/02_httpmeta_speed_filter.js."

  mkdir -p "$APP_DIR/data" "$APP_DIR/operators"
  cp -f "$SCRIPT_DIR/sources.txt" "$APP_DIR/sources.txt"
  cp -f "$SCRIPT_DIR/operators/01_fetch_today_clean.js" "$APP_DIR/operators/01_fetch_today_clean.js"
  cp -f "$SCRIPT_DIR/operators/02_httpmeta_speed_filter.js" "$APP_DIR/operators/02_httpmeta_speed_filter.js"
}

write_runtime_files() {
  if [ -f "$APP_DIR/.env" ]; then
    # shellcheck disable=SC1091
    . "$APP_DIR/.env" || true
    BACKEND_PATH="${BACKEND_PATH:-}"
  fi
  if [ -z "${BACKEND_PATH:-}" ]; then
    BACKEND_PATH="$(generate_backend_path)"
  fi

  cat > "$APP_DIR/.env" <<ENVEOF
APP_DIR=$APP_DIR
PORT=$PORT
BIND_IP=$BIND_IP
IMAGE=$IMAGE
BACKEND_PATH=$BACKEND_PATH
ENVEOF

  cat > "$APP_DIR/docker-compose.yml" <<YAMLEOF
services:
  sub-store:
    image: ${IMAGE}
    container_name: sub-store
    restart: unless-stopped
    ports:
      - "${BIND_IP}:${PORT}:3001"
    volumes:
      - ./data:/opt/app/data
    environment:
      - SUB_STORE_FRONTEND_BACKEND_PATH=/${BACKEND_PATH}
      - SUB_STORE_BACKEND_SYNC_CRON=0 */6 * * *
      - SUB_STORE_PRODUCE_CRON=0 */6 * * *
YAMLEOF

  cat > "$APP_DIR/show-info.sh" <<'INFOEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
. ./.env
IP="$(curl -4 -fsS https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
echo "Sub-Store frontend: http://${IP}:${PORT}"
echo "Sub-Store backend : http://${IP}:${PORT}/${BACKEND_PATH}"
echo "One-line UI URL   : http://${IP}:${PORT}?api=http://${IP}:${PORT}/${BACKEND_PATH}"
echo
echo "Sources file      : ${APP_DIR}/sources.txt"
echo "Speed script      : ${APP_DIR}/operators/02_httpmeta_speed_filter.js"
echo
echo "Use this to view sources: cat ${APP_DIR}/sources.txt"
echo "Use this to view script : cat ${APP_DIR}/operators/02_httpmeta_speed_filter.js"
INFOEOF
  chmod +x "$APP_DIR/show-info.sh"

  cat > "$APP_DIR/update.sh" <<'UPDATEEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}
run_compose pull
run_compose up -d
UPDATEEOF
  chmod +x "$APP_DIR/update.sh"

  cat > "$APP_DIR/uninstall.sh" <<'UNINSTALLEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}
run_compose down
printf "Keep data at %s/data. Remove it manually if you are sure.\n" "$(pwd)"
UNINSTALLEOF
  chmod +x "$APP_DIR/uninstall.sh"
}

if [ "$(id -u)" -ne 0 ]; then
  die "Please run as root: sudo bash install.sh"
fi

ensure_docker
ensure_compose

log "3/6" "Copying project files to ${APP_DIR}..."
copy_project_files
write_runtime_files

cd "$APP_DIR"
log "4/6" "Pulling image: ${IMAGE}"
run_compose pull

log "5/6" "Starting Sub-Store..."
run_compose up -d

log "6/6" "Done."
sleep 3
"$APP_DIR/show-info.sh"
