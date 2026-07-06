#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/substore-free-node}"
COLLECTION_NAME="${COLLECTION_NAME:-free-auto}"
BOOTSTRAP_REPLACE_PRESET="${BOOTSTRAP_REPLACE_PRESET:-0}"

log() {
  printf '[%s] %s\n' "$1" "$2"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_python3() {
  if has_cmd python3; then
    return 0
  fi
  log "BOOT" "python3 missing, installing python3..."
  if has_cmd apt-get; then
    apt-get update -y
    apt-get install -y python3
  elif has_cmd dnf; then
    dnf install -y python3
  elif has_cmd yum; then
    yum install -y python3
  elif has_cmd apk; then
    apk add --no-cache python3
  else
    die "python3 is required but no supported package manager found."
  fi
}

if [ -f "$APP_DIR/.env" ]; then
  # shellcheck disable=SC1091
  . "$APP_DIR/.env"
fi

PORT="${PORT:-3001}"
BACKEND_PATH="${BACKEND_PATH:-}"
[ -n "$BACKEND_PATH" ] || die "BACKEND_PATH is empty. Run install.sh first."

case "$COLLECTION_NAME" in
  *[!A-Za-z0-9._-]*|'')
    die "COLLECTION_NAME must only contain letters, numbers, dot, underscore, and dash. Current: ${COLLECTION_NAME}"
    ;;
esac

BASE_URL="${BASE_URL:-http://127.0.0.1:${PORT}/${BACKEND_PATH}}"
SOURCES_FILE="${SOURCES_FILE:-${APP_DIR}/sources.txt}"
SPEED_SCRIPT="${SPEED_SCRIPT:-${APP_DIR}/operators/02_httpmeta_speed_filter.js}"

[ -f "$SOURCES_FILE" ] || die "Sources file not found: ${SOURCES_FILE}"
[ -f "$SPEED_SCRIPT" ] || die "Speed script not found: ${SPEED_SCRIPT}"

install_python3

APP_DIR="$APP_DIR" \
BASE_URL="$BASE_URL" \
SOURCES_FILE="$SOURCES_FILE" \
SPEED_SCRIPT="$SPEED_SCRIPT" \
COLLECTION_NAME="$COLLECTION_NAME" \
BOOTSTRAP_REPLACE_PRESET="$BOOTSTRAP_REPLACE_PRESET" \
python3 <<'PY'
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

base_url = os.environ['BASE_URL'].rstrip('/')
sources_file = Path(os.environ['SOURCES_FILE'])
speed_script = Path(os.environ['SPEED_SCRIPT'])
collection_name = os.environ.get('COLLECTION_NAME', 'free-auto')
replace_preset = os.environ.get('BOOTSTRAP_REPLACE_PRESET', '0') == '1'


def request(method, path, data=None, allow_404=False):
    url = base_url + path
    body = None
    headers = {}
    if data is not None:
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        headers['Content-Type'] = 'application/json;charset=utf-8'
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode('utf-8', errors='replace')
            return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode('utf-8', errors='replace')
        if allow_404 and e.code == 404:
            return e.code, raw
        raise RuntimeError(f'{method} {url} failed: HTTP {e.code}: {raw[:500]}')
    except Exception as e:
        raise RuntimeError(f'{method} {url} failed: {e}')


def wait_backend():
    last = None
    for _ in range(60):
        try:
            request('GET', '/api/subs', allow_404=True)
            return
        except Exception as e:
            last = e
            time.sleep(1)
    raise RuntimeError(f'Sub-Store backend not ready: {last}')


def exists(path):
    status, _ = request('GET', path, allow_404=True)
    return status == 200


def post_or_patch(kind, name, payload):
    quoted = urllib.parse.quote(name, safe='')
    if kind == 'sub':
        exists_path = f'/api/sub/{quoted}'
        create_path = '/api/subs'
        update_path = exists_path
    elif kind == 'collection':
        exists_path = f'/api/collection/{quoted}'
        create_path = '/api/collections'
        update_path = exists_path
    else:
        raise ValueError(kind)

    if exists(exists_path):
        request('PATCH', update_path, payload)
        return 'updated'
    request('POST', create_path, payload)
    return 'created'


def read_sources():
    seen = set()
    out = []
    for raw in sources_file.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line in seen:
            continue
        seen.add(line)
        out.append(line)
    if not out:
        raise RuntimeError(f'No sources found in {sources_file}')
    return out


def source_display_name(index, url):
    try:
        parsed = urllib.parse.urlparse(url)
        host = parsed.netloc or 'local'
        path_tail = parsed.path.strip('/').split('/')[-1] or 'sub'
        return f'{index:03d} {host}/{path_tail}'
    except Exception:
        return f'{index:03d} source'


wait_backend()
sources = read_sources()
script_content = speed_script.read_text(encoding='utf-8')
sub_names = []
created = updated = 0

if replace_preset:
    # Replace only the preset names managed by this project, not unrelated user configs.
    # We do not delete anything here because some users may have already referenced these names manually.
    pass

for i, url in enumerate(sources, 1):
    name = f'source-{i:03d}'
    sub_names.append(name)
    sub = {
        'name': name,
        'displayName': source_display_name(i, url),
        'source': 'remote',
        'url': url,
        'ignoreFailedRemoteSub': 'fallbackQuiet',
        'process': [],
    }
    action = post_or_patch('sub', name, sub)
    if action == 'created':
        created += 1
    else:
        updated += 1

collection = {
    'name': collection_name,
    'displayName': 'Free Auto Nodes',
    'subscriptions': sub_names,
    'ignoreFailedRemoteSub': 'fallbackQuiet',
    'firstSubFlow': False,
    'process': [
        {
            'type': 'Script Operator',
            'customName': 'http-meta-speed-filter',
            'args': {
                'mode': 'script',
                'content': script_content,
            },
        }
    ],
}
col_action = post_or_patch('collection', collection_name, collection)

print(f'Subscriptions: created={created}, updated={updated}, total={len(sub_names)}')
print(f'Collection {collection_name}: {col_action}')
print('Bootstrap completed.')
PY
