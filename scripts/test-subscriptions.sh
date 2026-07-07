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
    echo "Result: 404. Check backend random path and collection name." >&2
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

echo "Local backend base: ${LOCAL_BACKEND}"
echo
echo "Important: this Docker image serves subscription downloads through the backend path: /BACKEND_PATH/download/collection/..."

check_url "Backend API" "${LOCAL_BACKEND}/api/subs"
check_url "v2rayN V2Ray base64" "${LOCAL_BACKEND}/download/collection/${COLLECTION_NAME}/V2Ray?includeUnsupportedProxy=true"
check_url "URI raw list" "${LOCAL_BACKEND}/download/collection/${COLLECTION_NAME}/URI?includeUnsupportedProxy=true"
check_url "Clash/Mihomo" "${LOCAL_BACKEND}/download/collection/${COLLECTION_NAME}/Clash.Meta?includeUnsupportedProxy=true&prettyYaml=true"

echo
echo "Local subscription endpoint tests passed. Use the URLs from ./show-info.sh in clients."
