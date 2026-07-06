#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/substore-free-node}"
PORT="${PORT:-3001}"
USE_TUNNEL="${USE_TUNNEL:-0}"
NO_PUBLIC_IP="${NO_PUBLIC_IP:-0}"
DOMAIN="${DOMAIN:-}"
PUBLIC_SCHEME="${PUBLIC_SCHEME:-https}"
IMAGE="${IMAGE:-xream/sub-store:http-meta}"
CONTAINER_NAME="${CONTAINER_NAME:-sub-store}"
SKIP_PULL="${SKIP_PULL:-0}"
AUTO_BOOTSTRAP="${AUTO_BOOTSTRAP:-1}"
COLLECTION_NAME="${COLLECTION_NAME:-free-auto}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${BIND_IP+x}" ]; then
  if [ "$USE_TUNNEL" = "1" ] || [ "$NO_PUBLIC_IP" = "1" ]; then
    BIND_IP="127.0.0.1"
  else
    BIND_IP="0.0.0.0"
  fi
fi

log() { printf '[%s] %s\n' "$1" "$2"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif has_cmd docker-compose; then
    docker-compose "$@"
  else
    die "Docker Compose is not available."
  fi
}

install_packages() {
  if has_cmd apt-get; then
    apt-get update -y
    apt-get install -y "$@"
  elif has_cmd dnf; then
    dnf install -y "$@"
  elif has_cmd yum; then
    yum install -y "$@"
  elif has_cmd apk; then
    apk add --no-cache "$@"
  else
    die "No supported package manager found. Please install missing packages manually: $*"
  fi
}

ensure_curl() {
  if has_cmd curl; then
    return 0
  fi
  log "PRE" "curl missing, installing curl and ca-certificates..."
  install_packages curl ca-certificates
}

start_docker_service() {
  if docker info >/dev/null 2>&1; then
    log "1/7" "Docker daemon already running."
    return 0
  fi
  log "1/7" "Starting Docker daemon..."
  if has_cmd systemctl; then
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
  fi
  if has_cmd service; then
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
  if has_cmd docker; then
    log "1/7" "Docker already installed: $(docker --version 2>/dev/null || true)"
    start_docker_service
    return 0
  fi
  log "1/7" "Docker missing, installing Docker..."
  ensure_curl
  curl -fsSL https://get.docker.com | sh
  start_docker_service
}

install_compose_standalone() {
  local arch os url
  ensure_curl
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
    log "2/7" "Docker Compose v2 already installed: $(docker compose version 2>/dev/null || true)"
    return 0
  fi
  if has_cmd docker-compose; then
    log "2/7" "Legacy docker-compose already installed: $(docker-compose --version 2>/dev/null || true)"
    return 0
  fi
  log "2/7" "Docker exists but Compose is missing, installing Compose..."
  if has_cmd apt-get; then
    apt-get update -y
    apt-get install -y docker-compose-plugin || true
  elif has_cmd dnf; then
    dnf install -y docker-compose-plugin || true
  elif has_cmd yum; then
    yum install -y docker-compose-plugin || true
  fi
  if docker compose version >/dev/null 2>&1 || has_cmd docker-compose; then
    return 0
  fi
  log "2/7" "Package manager did not provide Compose, installing standalone docker-compose..."
  install_compose_standalone
}

generate_backend_path() {
  if has_cmd openssl; then
    openssl rand -hex 12
  elif has_cmd sha256sum; then
    date +%s%N | sha256sum | awk '{print substr($1,1,24)}'
  else
    date +%s%N | awk '{print substr($1,1,24)}'
  fi
}

validate_collection_name() {
  case "$COLLECTION_NAME" in
    *[!A-Za-z0-9._-]*|'') die "COLLECTION_NAME must only contain letters, numbers, dot, underscore, and dash. Current: ${COLLECTION_NAME}" ;;
  esac
}

load_existing_backend_path() {
  if [ -f "$APP_DIR/.env" ]; then
    grep '^BACKEND_PATH=' "$APP_DIR/.env" | tail -n 1 | cut -d= -f2- || true
  fi
}

copy_project_files() {
  [ -f "$SCRIPT_DIR/sources.txt" ] || die "Missing sources.txt in project directory."
  [ -f "$SCRIPT_DIR/operators/01_fetch_today_clean.js" ] || die "Missing operators/01_fetch_today_clean.js."
  [ -f "$SCRIPT_DIR/operators/02_httpmeta_speed_filter.js" ] || die "Missing operators/02_httpmeta_speed_filter.js."
  [ -f "$SCRIPT_DIR/scripts/bootstrap-substore.sh" ] || die "Missing scripts/bootstrap-substore.sh."
  mkdir -p "$APP_DIR/data" "$APP_DIR/operators" "$APP_DIR/scripts"
  cp -f "$SCRIPT_DIR/sources.txt" "$APP_DIR/sources.txt"
  cp -f "$SCRIPT_DIR/operators/01_fetch_today_clean.js" "$APP_DIR/operators/01_fetch_today_clean.js"
  cp -f "$SCRIPT_DIR/operators/02_httpmeta_speed_filter.js" "$APP_DIR/operators/02_httpmeta_speed_filter.js"
  cp -f "$SCRIPT_DIR/scripts/bootstrap-substore.sh" "$APP_DIR/scripts/bootstrap-substore.sh"
  chmod +x "$APP_DIR/scripts/bootstrap-substore.sh"
  if [ -f "$SCRIPT_DIR/scripts/test-subscriptions.sh" ]; then
    cp -f "$SCRIPT_DIR/scripts/test-subscriptions.sh" "$APP_DIR/scripts/test-subscriptions.sh"
    chmod +x "$APP_DIR/scripts/test-subscriptions.sh"
  fi
}

write_runtime_files() {
  BACKEND_PATH="${BACKEND_PATH:-$(load_existing_backend_path)}"
  if [ -z "${BACKEND_PATH:-}" ]; then
    BACKEND_PATH="$(generate_backend_path)"
  fi

  cat > "$APP_DIR/.env" <<ENVEOF
APP_DIR=$APP_DIR
PORT=$PORT
BIND_IP=$BIND_IP
USE_TUNNEL=$USE_TUNNEL
NO_PUBLIC_IP=$NO_PUBLIC_IP
DOMAIN=$DOMAIN
PUBLIC_SCHEME=$PUBLIC_SCHEME
IMAGE=$IMAGE
CONTAINER_NAME=$CONTAINER_NAME
AUTO_BOOTSTRAP=$AUTO_BOOTSTRAP
COLLECTION_NAME=$COLLECTION_NAME
BACKEND_PATH=$BACKEND_PATH
ENVEOF

  cat > "$APP_DIR/docker-compose.yml" <<YAMLEOF
services:
  sub-store:
    image: ${IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${BIND_IP}:${PORT}:3001"
    volumes:
      - ./data:/opt/app/data
    environment:
      SUB_STORE_FRONTEND_BACKEND_PATH: "/${BACKEND_PATH}"
      SUB_STORE_BACKEND_SYNC_CRON: "0 */6 * * *"
      SUB_STORE_PRODUCE_CRON: "0 */6 * * *,collection,${COLLECTION_NAME}"
YAMLEOF

  cat > "$APP_DIR/show-info.sh" <<'INFOEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
. ./.env
COLLECTION_NAME="${COLLECTION_NAME:-free-auto}"

if [ -n "${DOMAIN:-}" ]; then
  FRONTEND_URL="${PUBLIC_SCHEME}://${DOMAIN}"
  BACKEND_URL="${PUBLIC_SCHEME}://${DOMAIN}/${BACKEND_PATH}"
  UI_URL="${PUBLIC_SCHEME}://${DOMAIN}?api=${PUBLIC_SCHEME}://${DOMAIN}/${BACKEND_PATH}"
elif [ "${NO_PUBLIC_IP:-0}" = "1" ] || [ "${USE_TUNNEL:-0}" = "1" ] || [ "${BIND_IP:-}" = "127.0.0.1" ]; then
  FRONTEND_URL="http://127.0.0.1:${PORT}"
  BACKEND_URL="http://127.0.0.1:${PORT}/${BACKEND_PATH}"
  UI_URL="http://127.0.0.1:${PORT}?api=http://127.0.0.1:${PORT}/${BACKEND_PATH}"
else
  if command -v curl >/dev/null 2>&1; then
    IP="$(curl -4 -fsS https://api.ipify.org 2>/dev/null || true)"
  fi
  if [ -z "${IP:-}" ]; then
    IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [ -z "${IP:-}" ]; then
    IP="YOUR_SERVER_IP"
  fi
  FRONTEND_URL="http://${IP}:${PORT}"
  BACKEND_URL="http://${IP}:${PORT}/${BACKEND_PATH}"
  UI_URL="http://${IP}:${PORT}?api=http://${IP}:${PORT}/${BACKEND_PATH}"
fi

# Sub-Store uses the random backend path for /api, but subscription share routes are served from the root frontend path.
V2RAYN_URL="${FRONTEND_URL}/share/col/${COLLECTION_NAME}/V2Ray?includeUnsupportedProxy=true"
URI_URL="${FRONTEND_URL}/share/col/${COLLECTION_NAME}/URI?includeUnsupportedProxy=true"
CLASH_URL="${FRONTEND_URL}/share/col/${COLLECTION_NAME}/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true"
SINGBOX_URL="${FRONTEND_URL}/share/col/${COLLECTION_NAME}/sing-box?includeUnsupportedProxy=true"

echo "Sub-Store frontend: ${FRONTEND_URL}"
echo "Sub-Store backend : ${BACKEND_URL}"
echo "One-line UI URL   : ${UI_URL}"
echo
echo "Ready subscription URLs:"
echo "v2rayN      : ${V2RAYN_URL}"
echo "URI raw     : ${URI_URL}"
echo "Clash/Mihomo: ${CLASH_URL}"
echo "sing-box    : ${SINGBOX_URL}"
echo
echo "Bind address      : ${BIND_IP}:${PORT} -> container 3001"
echo "Preset collection : ${COLLECTION_NAME}"
echo "Sources file      : ${APP_DIR}/sources.txt"
echo "Speed script      : ${APP_DIR}/operators/02_httpmeta_speed_filter.js"
echo
if [ -z "${DOMAIN:-}" ] && { [ "${NO_PUBLIC_IP:-0}" = "1" ] || [ "${USE_TUNNEL:-0}" = "1" ] || [ "${BIND_IP:-}" = "127.0.0.1" ]; }; then
  echo "Public IP output is disabled/local-only. Use a tunnel, reverse proxy, or SSH port forwarding to access it remotely."
fi
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
if [ -x ./scripts/bootstrap-substore.sh ]; then
  ./scripts/bootstrap-substore.sh
fi
./show-info.sh
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

check_container_conflict() {
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    local working_dir
    working_dir="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$CONTAINER_NAME" 2>/dev/null || true)"
    if [ -n "$working_dir" ] && [ "$working_dir" != "<no value>" ] && [ "$working_dir" != "$APP_DIR" ]; then
      die "Container name ${CONTAINER_NAME} is already used by another compose project: ${working_dir}. Use CONTAINER_NAME=sub-store2 or remove the old container."
    fi
    log "PRE" "Existing container ${CONTAINER_NAME} found. It will be reused/updated, not deleted."
  fi
}

print_plan() {
  log "PLAN" "APP_DIR=${APP_DIR}"
  log "PLAN" "PORT=${PORT}, BIND_IP=${BIND_IP}, CONTAINER_NAME=${CONTAINER_NAME}"
  log "PLAN" "USE_TUNNEL=${USE_TUNNEL}, NO_PUBLIC_IP=${NO_PUBLIC_IP}, DOMAIN=${DOMAIN:-none}"
  log "PLAN" "AUTO_BOOTSTRAP=${AUTO_BOOTSTRAP}, COLLECTION_NAME=${COLLECTION_NAME}"
  log "PLAN" "IMAGE=${IMAGE}"
  if [ "$SKIP_PULL" = "1" ]; then
    log "PLAN" "SKIP_PULL=1, image pull will be skipped."
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  die "Please run as root: sudo bash install.sh"
fi

validate_collection_name
print_plan
ensure_docker
ensure_compose
check_container_conflict

log "3/7" "Copying project files to ${APP_DIR}..."
copy_project_files
write_runtime_files

cd "$APP_DIR"
if [ "$SKIP_PULL" = "1" ]; then
  log "4/7" "Skipping image pull because SKIP_PULL=1."
else
  log "4/7" "Pulling image: ${IMAGE}"
  run_compose pull
fi

log "5/7" "Starting or updating Sub-Store..."
run_compose up -d

if [ "$AUTO_BOOTSTRAP" = "1" ]; then
  log "6/7" "Bootstrapping built-in sources, collection, and speed operator..."
  "$APP_DIR/scripts/bootstrap-substore.sh"
else
  log "6/7" "Skipping bootstrap because AUTO_BOOTSTRAP=0."
fi

log "7/7" "Done."
sleep 1
"$APP_DIR/show-info.sh"
