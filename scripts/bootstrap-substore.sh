#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/substore-free-node}"
COLLECTION_NAME="${COLLECTION_NAME:-free-auto}"
BOOTSTRAP_REPLACE_PRESET="${BOOTSTRAP_REPLACE_PRESET:-0}"
USE_SPEED_FILTER="${USE_SPEED_FILTER:-0}"

log() { printf '[%s] %s\n' "$1" "$2"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

install_python3() {
  has_cmd python3 && return 0
  log BOOT "python3 missing, installing python3..."
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
  *[!A-Za-z0-9._-]*|'') die "COLLECTION_NAME must only contain letters, numbers, dot, underscore, and dash. Current: ${COLLECTION_NAME}" ;;
esac

BASE_URL="${BASE_URL:-http://127.0.0.1:${PORT}/${BACKEND_PATH}}"
SOURCES_FILE="${SOURCES_FILE:-${APP_DIR}/sources.txt}"
FAST_SCRIPT="${FAST_SCRIPT:-${APP_DIR}/operators/00_fast_clean_filter.js}"
SPEED_SCRIPT="${SPEED_SCRIPT:-${APP_DIR}/operators/02_httpmeta_speed_filter.js}"

[ -f "$SOURCES_FILE" ] || die "Sources file not found: ${SOURCES_FILE}"
[ -f "$FAST_SCRIPT" ] || die "Fast script not found: ${FAST_SCRIPT}"
if [ "$USE_SPEED_FILTER" = "1" ]; then
  [ -f "$SPEED_SCRIPT" ] || die "Speed script not found: ${SPEED_SCRIPT}"
fi

install_python3

BASE_URL="$BASE_URL" \
SOURCES_FILE="$SOURCES_FILE" \
FAST_SCRIPT="$FAST_SCRIPT" \
SPEED_SCRIPT="$SPEED_SCRIPT" \
COLLECTION_NAME="$COLLECTION_NAME" \
BOOTSTRAP_REPLACE_PRESET="$BOOTSTRAP_REPLACE_PRESET" \
USE_SPEED_FILTER="$USE_SPEED_FILTER" \
python3 <<'PY'
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

base_url = os.environ['BASE_URL'].rstrip('/')
sources_file = Path(os.environ['SOURCES_FILE'])
fast_script = Path(os.environ['FAST_SCRIPT'])
speed_script = Path(os.environ['SPEED_SCRIPT'])
collection_name = os.environ.get('COLLECTION_NAME', 'free-auto')
use_speed_filter = os.environ.get('USE_SPEED_FILTER', '0') == '1'


def request(method, path, data=None, timeout=90):
    url = base_url + path
    body = None
    headers = {}
    if data is not None:
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        headers['Content-Type'] = 'application/json;charset=utf-8'
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode('utf-8', errors='replace')
            return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode('utf-8', errors='replace')
        raise RuntimeError(f'{method} {url} failed: HTTP {e.code}: {raw[:800]}')
    except Exception as e:
        raise RuntimeError(f'{method} {url} failed: {e}')


def request_json(method, path, data=None):
    status, raw = request(method, path, data=data)
    try:
        return json.loads(raw)
    except Exception:
        raise RuntimeError(f'{method} {base_url + path} did not return JSON: {raw[:800]}')


def wait_backend():
    last = None
    for _ in range(90):
        try:
            obj = request_json('GET', '/api/subs')
            if isinstance(obj, dict) and obj.get('status') == 'success':
                return
        except Exception as e:
            last = e
        time.sleep(1)
    raise RuntimeError(f'Sub-Store backend not ready: {last}')


def extract_names(api_obj):
    data = api_obj.get('data') if isinstance(api_obj, dict) else api_obj
    names = set()
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get('name'):
                names.add(str(item['name']))
    elif isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, dict) and value.get('name'):
                names.add(str(value['name']))
            elif isinstance(key, str):
                names.add(key)
    return names


def create_or_update(kind, existing_names, name, payload):
    quoted = urllib.parse.quote(name, safe='')
    if kind == 'sub':
        create_path = '/api/subs'
        update_path = f'/api/sub/{quoted}'
    else:
        create_path = '/api/collections'
        update_path = f'/api/collection/{quoted}'

    if name in existing_names:
        request('PATCH', update_path, payload)
        return 'updated'
    try:
        request('POST', create_path, payload)
        existing_names.add(name)
        return 'created'
    except RuntimeError as e:
        msg = str(e)
        if 'DUPLICATE_KEY' in msg or 'already exists' in msg:
            request('PATCH', update_path, payload)
            existing_names.add(name)
            return 'updated'
        raise


def read_sources():
    seen = set()
    out = []
    for raw in sources_file.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or line in seen:
            continue
        seen.add(line)
        out.append(line)
    if not out:
        raise RuntimeError(f'No sources found in {sources_file}')
    return out


def source_display_name(index, url):
    parsed = urllib.parse.urlparse(url)
    host = parsed.netloc or 'local'
    path_tail = parsed.path.strip('/').split('/')[-1] or 'sub'
    return f'{index:03d} {host}/{path_tail}'


wait_backend()
existing_subs = extract_names(request_json('GET', '/api/subs'))
existing_cols = extract_names(request_json('GET', '/api/collections'))
sources = read_sources()
operator_content = (speed_script if use_speed_filter else fast_script).read_text(encoding='utf-8')
operator_name = 'http-meta-speed-filter' if use_speed_filter else 'fast-clean-filter'
sub_names = []
created = updated = 0

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
    action = create_or_update('sub', existing_subs, name, sub)
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
            'customName': operator_name,
            'args': {
                'mode': 'script',
                'content': operator_content,
            },
        }
    ],
}
col_action = create_or_update('collection', existing_cols, collection_name, collection)

print(f'Subscriptions: created={created}, updated={updated}, total={len(sub_names)}')
print(f'Collection {collection_name}: {col_action}')
print(f'Operator: {operator_name}')
print('Bootstrap completed.')
PY
