#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/substore-free-node}"

if [ -f "$APP_DIR/.env" ]; then
  # shellcheck disable=SC1091
  . "$APP_DIR/.env"
fi

PORT="${PORT:-3001}"
BACKEND_PATH="${BACKEND_PATH:-}"
COLLECTION_NAME="${COLLECTION_NAME:-free-auto}"
[ -n "$BACKEND_PATH" ] || { echo "BACKEND_PATH is empty. Run install.sh first." >&2; exit 1; }

LOCAL_BASE="http://127.0.0.1:${PORT}/${BACKEND_PATH}"

check_url() {
  local name="$1"
  local url="$2"
  echo
  echo "[TEST] ${name}"
  echo "URL: ${url}"
  local code
  code="$(curl -L -sS -o /tmp/substore-test-output.txt -w '%{http_code}' --max-time 120 "$url" || true)"
  echo "HTTP: ${code}"
  echo "Body preview:"
  head -c 300 /tmp/substore-test-output.txt || true
  echo
  if [ "$code" = "404" ]; then
    echo "Result: 404. Usually the backend random path is missing or the tunnel hostname path is wrong." >&2
    return 1
  fi
  if [ "$code" = "000" ]; then
    echo "Result: request failed. Check whether Sub-Store is running and listening on 127.0.0.1:${PORT}." >&2
    return 1
  fi
}

echo "Local backend base: ${LOCAL_BASE}"
check_url "Backend API" "${LOCAL_BASE}/api/subs"
check_url "v2rayN V2Ray base64" "${LOCAL_BASE}/share/col/${COLLECTION_NAME}/V2Ray?includeUnsupportedProxy=true"
check_url "URI raw list" "${LOCAL_BASE}/share/col/${COLLECTION_NAME}/URI?includeUnsupportedProxy=true"
check_url "Clash/Mihomo" "${LOCAL_BASE}/share/col/${COLLECTION_NAME}/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true"

echo
echo "If local tests pass but client gets 404, the client URL is wrong or Cloudflare Tunnel routing is not pointing to http://localhost:${PORT}."
