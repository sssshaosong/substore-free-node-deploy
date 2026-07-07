#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/free-node-sub}"
STATIC_PORT="${STATIC_PORT:-8088}"
DOMAIN="${DOMAIN:-}"
PUBLIC_SCHEME="${PUBLIC_SCHEME:-https}"
USE_TUNNEL="${USE_TUNNEL:-0}"
NO_PUBLIC_IP="${NO_PUBLIC_IP:-0}"
CONNECT_CHECK="${CONNECT_CHECK:-1}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-3}"
FETCH_TIMEOUT="${FETCH_TIMEOUT:-25}"
MAX_WORKERS="${MAX_WORKERS:-80}"
MAX_NODES="${MAX_NODES:-500}"
MIN_OUTPUT_NODES="${MIN_OUTPUT_NODES:-1}"
SYNC_SOURCES_FROM_GITHUB="${SYNC_SOURCES_FROM_GITHUB:-1}"
REMOTE_SOURCES_URL="${REMOTE_SOURCES_URL:-https://raw.githubusercontent.com/sssshaosong/substore-free-node-deploy/main/sources.txt}"
REMOVE_OLD_SUBSTORE="${REMOVE_OLD_SUBSTORE:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${LISTEN_ADDR+x}" ]; then
  if [ "$USE_TUNNEL" = "1" ] || [ "$NO_PUBLIC_IP" = "1" ]; then
    LISTEN_ADDR="127.0.0.1"
  else
    LISTEN_ADDR="0.0.0.0"
  fi
fi

log() { printf '[%s] %s\n' "$1" "$2"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

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
    die "No supported package manager found. Install manually: $*"
  fi
}

ensure_runtime() {
  if has_cmd apt-get; then
    apt-get update -y
    apt-get install -y curl python3 python3-yaml util-linux
  else
    install_packages curl python3 util-linux
  fi
}

write_env() {
  mkdir -p "$APP_DIR" "$APP_DIR/output"
  cat > "$APP_DIR/config.env" <<EOF
APP_DIR=$APP_DIR
SOURCES_FILE=$APP_DIR/sources.txt
OUTPUT_DIR=$APP_DIR/output
STATIC_PORT=$STATIC_PORT
LISTEN_ADDR=$LISTEN_ADDR
DOMAIN=$DOMAIN
PUBLIC_SCHEME=$PUBLIC_SCHEME
CONNECT_CHECK=$CONNECT_CHECK
CHECK_TIMEOUT=$CHECK_TIMEOUT
FETCH_TIMEOUT=$FETCH_TIMEOUT
MAX_WORKERS=$MAX_WORKERS
MAX_NODES=$MAX_NODES
MIN_OUTPUT_NODES=$MIN_OUTPUT_NODES
SYNC_SOURCES_FROM_GITHUB=$SYNC_SOURCES_FROM_GITHUB
REMOTE_SOURCES_URL=$REMOTE_SOURCES_URL
EOF
}

copy_files() {
  [ -f "$SCRIPT_DIR/generator.py" ] || die "Missing generator.py"
  [ -f "$SCRIPT_DIR/sources.txt" ] || die "Missing sources.txt"
  cp -f "$SCRIPT_DIR/generator.py" "$APP_DIR/generator.py"
  cp -f "$SCRIPT_DIR/sources.txt" "$APP_DIR/sources.txt"
  chmod +x "$APP_DIR/generator.py"

  cat > "$APP_DIR/generate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
. ./config.env
set +a

if [ "${SYNC_SOURCES_FROM_GITHUB:-1}" = "1" ] && [ -n "${REMOTE_SOURCES_URL:-}" ]; then
  tmp="${SOURCES_FILE}.new"
  if curl -fsSL --max-time 25 -H 'Cache-Control: no-cache' "${REMOTE_SOURCES_URL}" -o "$tmp"; then
    if [ -s "$tmp" ] && grep -Eq '^https?://' "$tmp"; then
      mv -f "$tmp" "$SOURCES_FILE"
      echo "[sources] updated from ${REMOTE_SOURCES_URL}"
    else
      rm -f "$tmp"
      echo "[sources] remote sources invalid/empty, keeping local sources.txt" >&2
    fi
  else
    rm -f "$tmp"
    echo "[sources] failed to fetch remote sources, keeping local sources.txt" >&2
  fi
fi

exec python3 ./generator.py
EOF
  chmod +x "$APP_DIR/generate.sh"

  cat > "$APP_DIR/serve.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a
. ./config.env
set +a
mkdir -p "$OUTPUT_DIR"
exec python3 -m http.server "$STATIC_PORT" --bind "$LISTEN_ADDR" --directory "$OUTPUT_DIR"
EOF
  chmod +x "$APP_DIR/serve.sh"

  cat > "$APP_DIR/show-info.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
. ./config.env
if [ -n "${DOMAIN:-}" ]; then
  BASE_URL="${PUBLIC_SCHEME}://${DOMAIN}"
elif [ "$LISTEN_ADDR" = "127.0.0.1" ]; then
  BASE_URL="http://127.0.0.1:${STATIC_PORT}"
else
  IP=""
  if command -v curl >/dev/null 2>&1; then
    IP="$(curl -4 -fsS https://api.ipify.org 2>/dev/null || true)"
  fi
  [ -n "$IP" ] || IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -n "$IP" ] || IP="YOUR_SERVER_IP"
  BASE_URL="http://${IP}:${STATIC_PORT}"
fi
cat <<INFO
Static file server : ${BASE_URL}
Listen             : ${LISTEN_ADDR}:${STATIC_PORT}
Output dir         : ${OUTPUT_DIR}
Timer              : systemd timer, every 6 hours, Persistent=true
Source list sync   : ${SYNC_SOURCES_FROM_GITHUB} (${REMOTE_SOURCES_URL})
Connect check      : ${CONNECT_CHECK} (1=TCP remove unreachable, 0=skip)

Subscription URLs:
v2rayN / V2Ray     : ${BASE_URL}/v2ray.txt
Raw URI            : ${BASE_URL}/uri.txt
Clash / Mihomo     : ${BASE_URL}/clash.yaml
Status             : ${BASE_URL}/status.json
Last error         : ${BASE_URL}/last_error.json

Local files:
${OUTPUT_DIR}/v2ray.txt
${OUTPUT_DIR}/uri.txt
${OUTPUT_DIR}/clash.yaml
${OUTPUT_DIR}/status.json
INFO
EOF
  chmod +x "$APP_DIR/show-info.sh"

  cat > "$APP_DIR/health-check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
. ./config.env
fail=0

need_file() {
  if [ ! -s "$1" ]; then
    echo "FAIL: missing or empty $1"
    fail=1
  else
    echo "OK  : $1"
  fi
}

need_file "$OUTPUT_DIR/v2ray.txt"
need_file "$OUTPUT_DIR/uri.txt"
need_file "$OUTPUT_DIR/clash.yaml"
need_file "$OUTPUT_DIR/status.json"

if systemctl is-enabled free-node-sub-generate.timer >/dev/null 2>&1 && systemctl is-active free-node-sub-generate.timer >/dev/null 2>&1; then
  echo "OK  : timer enabled and active"
else
  echo "FAIL: timer is not enabled/active"
  fail=1
fi

if systemctl is-active free-node-sub-server.service >/dev/null 2>&1; then
  echo "OK  : static server active"
else
  echo "FAIL: static server inactive"
  fail=1
fi

python3 - <<'PY' || fail=1
import json, sys
from datetime import datetime, timezone
from pathlib import Path
status = json.loads(Path('output/status.json').read_text())
print('OK  : status output_count =', status.get('output_count'))
print('OK  : status source_ok_count =', status.get('source_ok_count'))
raw = status.get('generated_at')
if not raw:
    print('FAIL: generated_at missing')
    sys.exit(1)
gen = datetime.fromisoformat(raw.replace('Z', '+00:00'))
age_hours = (datetime.now(timezone.utc) - gen).total_seconds() / 3600
print(f'OK  : generated_at age = {age_hours:.2f} hours')
if age_hours > 7:
    print('FAIL: generated output is older than 7 hours')
    sys.exit(1)
if int(status.get('output_count') or 0) < 1:
    print('FAIL: output_count < 1')
    sys.exit(1)
PY

curl -fsSI --max-time 10 "http://127.0.0.1:${STATIC_PORT}/v2ray.txt" >/dev/null && echo "OK  : local HTTP v2ray.txt reachable" || { echo "FAIL: local HTTP v2ray.txt unreachable"; fail=1; }

exit "$fail"
EOF
  chmod +x "$APP_DIR/health-check.sh"
}

write_systemd() {
  cat > /etc/systemd/system/free-node-sub-generate.service <<EOF
[Unit]
Description=Generate static free-node subscriptions
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/flock -n /run/free-node-sub-generate.lock $APP_DIR/generate.sh
TimeoutStartSec=45min
Nice=10
EOF

  cat > /etc/systemd/system/free-node-sub-generate.timer <<'EOF'
[Unit]
Description=Run free-node subscription generator every 6 hours

[Timer]
OnBootSec=2min
OnUnitActiveSec=6h
Persistent=true
AccuracySec=1min
RandomizedDelaySec=0
Unit=free-node-sub-generate.service

[Install]
WantedBy=timers.target
EOF

  cat > /etc/systemd/system/free-node-sub-server.service <<EOF
[Unit]
Description=Serve static free-node subscriptions
After=network-online.target free-node-sub-generate.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/serve.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable free-node-sub-generate.timer >/dev/null
  systemctl enable free-node-sub-server.service >/dev/null
}

maybe_remove_old() {
  if [ "$REMOVE_OLD_SUBSTORE" != "1" ]; then
    return 0
  fi
  log CLEAN "Stopping old Sub-Store project if present"
  docker rm -f sub-store >/dev/null 2>&1 || true
  systemctl disable --now sub-store >/dev/null 2>&1 || true
}

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash install.sh"

log 1/6 "Installing runtime packages"
ensure_runtime
log 2/6 "Writing config and copying files to $APP_DIR"
write_env
copy_files
maybe_remove_old
log 3/6 "Installing systemd services"
write_systemd
log 4/6 "Generating subscription files now"
if ! systemctl start free-node-sub-generate.service; then
  journalctl -u free-node-sub-generate.service --no-pager -n 120 || true
  die "Initial generation failed"
fi
log 5/6 "Starting static file server and timer"
systemctl restart free-node-sub-server.service
systemctl start free-node-sub-generate.timer
log 6/6 "Done"
"$APP_DIR/show-info.sh"
