#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/substore-free-node}"
PORT="${PORT:-3001}"
BIND_IP="${BIND_IP:-0.0.0.0}"
IMAGE="${IMAGE:-xream/sub-store:http-meta}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash install.sh"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[1/5] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker >/dev/null 2>&1 || true
  systemctl start docker >/dev/null 2>&1 || true
else
  echo "[1/5] Docker already installed."
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required. Please install docker compose plugin and rerun."
  exit 1
fi

mkdir -p "$APP_DIR/data" "$APP_DIR/operators"
cp -f "$SCRIPT_DIR/sources.txt" "$APP_DIR/sources.txt"
cp -f "$SCRIPT_DIR/operators/01_fetch_today_clean.js" "$APP_DIR/operators/01_fetch_today_clean.js"
cp -f "$SCRIPT_DIR/operators/02_httpmeta_speed_filter.js" "$APP_DIR/operators/02_httpmeta_speed_filter.js"

if [ -f "$APP_DIR/.env" ]; then
  . "$APP_DIR/.env"
  BACKEND_PATH="${BACKEND_PATH:-}"
fi
if [ -z "${BACKEND_PATH:-}" ]; then
  BACKEND_PATH="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)"
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
      - PORT=9876
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
docker compose pull
docker compose up -d
UPDATEEOF
chmod +x "$APP_DIR/update.sh"

cat > "$APP_DIR/uninstall.sh" <<'UNINSTALLEOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker compose down
printf "Keep data at %s/data. Remove it manually if you are sure.\n" "$(pwd)"
UNINSTALLEOF
chmod +x "$APP_DIR/uninstall.sh"

echo "[2/5] Pulling image..."
cd "$APP_DIR"
docker compose pull

echo "[3/5] Starting Sub-Store..."
docker compose up -d

echo "[4/5] Waiting for service..."
sleep 3

echo "[5/5] Done."
"$APP_DIR/show-info.sh"
