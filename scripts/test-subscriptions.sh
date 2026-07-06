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

LOCAL_FRONTEND="http://127.0.0.1:${PORT}"
LOCAL_BACKEND="http://127.0.0.1:${PORT}/${BACKEND_PATH}"

check_url() {
  local name="$1"
  local url="$2"
  echo
  echo "[TEST] ${name}"
  echo "URL: ${url}"
  local code
  code="$(curl -L -sS -o /tmp/substore-test-output.txt -w '%{http_code}' --max-time 180 "$url" || true)"
  echo "HTTP: ${code}"
  echo "Body preview:"
  head -c 400 /tmp/substore-test-output.txt || true
  echo
  if [ "$code" = "404" ]; then
    echo "Result: 404. For /api use backend path. For /share use root frontend path." >&2
    return 1
  fi
  if [ "$code" = "000" ]; then
    echo "Result: request failed. Check whether Sub-Store is running and listening on 127.0.0.1:${PORT}." >&2
    return 1
  fi
  if grep -qi '<!DOCTYPE html\|<html' /tmp/substore-test-output.txt; then
    echo "Result: HTML frontend page returned. This endpoint is wrong for subscription content." >&2
    return 1
  fi
}

echo "Local frontend base: ${LOCAL_FRONTEND}"
echo "Local backend base : ${LOCAL_BACKEND}"
echo
echo "Important: /api uses backend path; /share uses root frontend path."

check_url "Backend API" "${LOCAL_BACKEND}/api/subs"
check_url "v2rayN V2Ray base64" "${LOCAL_FRONTEND}/share/col/${COLLECTION_NAME}/V2Ray?includeUnsupportedProxy=true"
check_url "URI raw list" "${LOCAL_FRONTEND}/share/col/${COLLECTION_NAME}/URI?includeUnsupportedProxy=true"
check_url "Clash/Mihomo" "${LOCAL_FRONTEND}/share/col/${COLLECTION_NAME}/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true"

echo
echo "Local subscription endpoint tests passed."
echo "If local tests pass but client gets 404, use the URL from ./show-info.sh and make sure Cloudflare Tunnel points to http://localhost:${PORT}."
