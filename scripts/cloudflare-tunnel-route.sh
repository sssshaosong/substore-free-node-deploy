#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-${1:-}}"
TUNNEL_NAME="${TUNNEL_NAME:-${2:-}}"
PORT="${PORT:-3001}"
SERVICE="${SERVICE:-http://localhost:${PORT}}"
CONFIG_FILE="${CONFIG_FILE:-/etc/cloudflared/config.yml}"

log() {
  printf '[%s] %s\n' "$1" "$2"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

if ! command -v cloudflared >/dev/null 2>&1; then
  die "cloudflared is not installed. Install or configure Cloudflare Tunnel first."
fi

if [ -z "$DOMAIN" ]; then
  cat <<'EOF'
Usage:
  DOMAIN=sub.example.com TUNNEL_NAME=my-tunnel bash scripts/cloudflare-tunnel-route.sh

Or:
  bash scripts/cloudflare-tunnel-route.sh sub.example.com my-tunnel
EOF
  exit 1
fi

if [ -z "$TUNNEL_NAME" ]; then
  log "INFO" "Existing tunnels on this machine/account:"
  cloudflared tunnel list || true
  die "TUNNEL_NAME is required. Example: TUNNEL_NAME=my-tunnel DOMAIN=${DOMAIN} bash scripts/cloudflare-tunnel-route.sh"
fi

log "1/3" "Creating DNS route: ${DOMAIN} -> ${TUNNEL_NAME}"
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

log "2/3" "DNS route created. Now make sure your tunnel ingress points ${DOMAIN} to ${SERVICE}."

cat <<EOF

Add this rule to your cloudflared ingress config, before the final http_status:404 rule:

  - hostname: ${DOMAIN}
    service: ${SERVICE}

Typical config path:
  ${CONFIG_FILE}

Example full ingress block:

  ingress:
    - hostname: ${DOMAIN}
      service: ${SERVICE}
    - service: http_status:404

After editing, restart cloudflared:

  sudo systemctl restart cloudflared

Then run Sub-Store in local-only mode:

  sudo USE_TUNNEL=1 DOMAIN=${DOMAIN} bash install.sh

EOF

log "3/3" "Done."
