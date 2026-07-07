#!/usr/bin/env python3
"""Static free-node subscription generator.

This script is intentionally independent from Sub-Store. It fetches public sources,
parses supported proxy formats, optionally removes TCP-unreachable nodes, and writes
static files for subscription clients.
"""

from __future__ import annotations

import base64
import concurrent.futures
import datetime as dt
import hashlib
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover
    yaml = None

APP_DIR = Path(os.getenv("APP_DIR", "/opt/free-node-sub"))
SOURCES_FILE = Path(os.getenv("SOURCES_FILE", str(APP_DIR / "sources.txt")))
OUTPUT_DIR = Path(os.getenv("OUTPUT_DIR", str(APP_DIR / "output")))
FETCH_TIMEOUT = int(os.getenv("FETCH_TIMEOUT", "25"))
CHECK_TIMEOUT = float(os.getenv("CHECK_TIMEOUT", "3"))
MAX_WORKERS = int(os.getenv("MAX_WORKERS", "80"))
MAX_NODES = int(os.getenv("MAX_NODES", "500"))
CONNECT_CHECK = os.getenv("CONNECT_CHECK", "1") == "1"
USER_AGENT = os.getenv(
    "USER_AGENT",
    "Mozilla/5.0 (compatible; free-node-sub-generator/1.0)",
)

URI_RE = re.compile(
    r"(?:vmess|vless|trojan|ss|ssr|hysteria2|hy2)://[^\s\"'<>]+",
    re.IGNORECASE,
)

Proxy = Dict[str, Any]


def log(message: str) -> None:
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}", flush=True)


def b64decode_maybe(text: str) -> Optional[str]:
    compact = "".join(text.strip().split())
    if len(compact) < 16:
        return None
    padding = "=" * (-len(compact) % 4)
    try:
        raw = base64.urlsafe_b64decode((compact + padding).encode())
        decoded = raw.decode("utf-8", errors="replace")
        if URI_RE.search(decoded) or "proxies:" in decoded:
            return decoded
    except Exception:
        return None
    return None


def b64encode_text(text: str) -> str:
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def safe_name(name: Any, fallback: str) -> str:
    s = str(name or fallback).strip()
    for bad in ["ProxyGo免费节点分享", "免费节点", "TG频道", "联系客服", " | free-nodes"]:
        s = s.replace(bad, " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s[:96] or fallback


def read_sources(path: Path) -> List[str]:
    sources: List[str] = []
    seen = set()
    for raw in path.read_text("utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line in seen:
            continue
        seen.add(line)
        sources.append(line)
    return sources


def fetch_url(url: str) -> Tuple[str, Optional[str], Optional[str]]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as resp:
            data = resp.read()
        text = data.decode("utf-8", errors="replace")
        decoded = b64decode_maybe(text)
        if decoded:
            text = decoded
        return url, text, None
    except Exception as e:
        return url, None, str(e)


def parse_vmess(uri: str) -> Optional[Proxy]:
    try:
        data = uri[8:]
        padding = "=" * (-len(data) % 4)
        obj = json.loads(base64.urlsafe_b64decode((data + padding).encode()).decode("utf-8", errors="replace"))
        return {
            "type": "vmess",
            "name": safe_name(obj.get("ps"), "vmess"),
            "server": obj.get("add"),
            "port": int(obj.get("port") or 443),
            "uuid": obj.get("id"),
            "alterId": int(obj.get("aid") or 0),
            "cipher": obj.get("scy") or "auto",
            "network": obj.get("net") or "tcp",
            "tls": obj.get("tls") == "tls",
            "servername": obj.get("sni") or obj.get("host") or "",
            "ws-opts": {
                "path": obj.get("path") or "/",
                "headers": {"Host": obj.get("host")},
            }
            if (obj.get("net") == "ws" and obj.get("host"))
            else None,
            "uri": uri,
        }
    except Exception:
        return None


def parse_url_uri(uri: str) -> Optional[Proxy]:
    try:
        parsed = urllib.parse.urlparse(uri)
        scheme = parsed.scheme.lower()
        name = safe_name(urllib.parse.unquote(parsed.fragment), scheme)
        query = urllib.parse.parse_qs(parsed.query)
        q = {k: v[-1] for k, v in query.items() if v}
        server = parsed.hostname
        port = int(parsed.port or (443 if scheme in {"vless", "trojan"} else 8388))
        if not server:
            return None
        if scheme == "vless":
            return {
                "type": "vless",
                "name": name,
                "server": server,
                "port": port,
                "uuid": urllib.parse.unquote(parsed.username or ""),
                "network": q.get("type", "tcp"),
                "tls": q.get("security") in {"tls", "reality"},
                "servername": q.get("sni") or q.get("peer") or "",
                "flow": q.get("flow") or "",
                "uri": uri,
            }
        if scheme == "trojan":
            return {
                "type": "trojan",
                "name": name,
                "server": server,
                "port": port,
                "password": urllib.parse.unquote(parsed.username or ""),
                "sni": q.get("sni") or q.get("peer") or "",
                "uri": uri,
            }
        if scheme == "ss":
            method = password = ""
            if "@" in uri:
                userinfo = parsed.username or ""
                try:
                    decoded = base64.urlsafe_b64decode(userinfo + "=" * (-len(userinfo) % 4)).decode()
                    if ":" in decoded:
                        method, password = decoded.split(":", 1)
                    else:
                        method = urllib.parse.unquote(parsed.username or "")
                        password = urllib.parse.unquote(parsed.password or "")
                except Exception:
                    method = urllib.parse.unquote(parsed.username or "")
                    password = urllib.parse.unquote(parsed.password or "")
            return {
                "type": "ss",
                "name": name,
                "server": server,
                "port": port,
                "cipher": method,
                "password": password,
                "uri": uri,
            }
        if scheme in {"hysteria2", "hy2", "ssr"}:
            return {"type": scheme, "name": name, "server": server, "port": port, "uri": uri}
    except Exception:
        return None
    return None


def parse_uri(uri: str) -> Optional[Proxy]:
    uri = uri.strip().strip('"\'')
    if uri.lower().startswith("vmess://"):
        return parse_vmess(uri)
    return parse_url_uri(uri)


def yaml_proxy_to_uri(p: Proxy) -> Optional[str]:
    typ = str(p.get("type", "")).lower()
    name = safe_name(p.get("name"), typ)
    server = p.get("server")
    port = p.get("port")
    if not server or not port:
        return None
    if typ == "ss":
        method = p.get("cipher") or p.get("method") or ""
        password = p.get("password") or ""
        user = b64encode_text(f"{method}:{password}").rstrip("=")
        return f"ss://{user}@{server}:{port}#{urllib.parse.quote(name)}"
    if typ == "trojan":
        password = urllib.parse.quote(str(p.get("password") or ""), safe="")
        params = {"security": "tls"}
        if p.get("sni"):
            params["sni"] = str(p.get("sni"))
        qs = urllib.parse.urlencode(params)
        return f"trojan://{password}@{server}:{port}?{qs}#{urllib.parse.quote(name)}"
    if typ == "vless":
        uuid = p.get("uuid") or p.get("id")
        params = {"encryption": "none", "type": str(p.get("network") or "tcp")}
        if p.get("tls") or p.get("security"):
            params["security"] = str(p.get("security") or "tls")
        if p.get("servername") or p.get("sni"):
            params["sni"] = str(p.get("servername") or p.get("sni"))
        if p.get("flow"):
            params["flow"] = str(p.get("flow"))
        return f"vless://{uuid}@{server}:{port}?{urllib.parse.urlencode(params)}#{urllib.parse.quote(name)}"
    if typ == "vmess":
        obj = {
            "v": "2",
            "ps": name,
            "add": server,
            "port": str(port),
            "id": p.get("uuid") or p.get("id"),
            "aid": str(p.get("alterId", p.get("alter-id", 0)) or 0),
            "scy": p.get("cipher") or "auto",
            "net": p.get("network") or "tcp",
            "type": "none",
            "host": p.get("servername") or p.get("server-name") or "",
            "path": "",
            "tls": "tls" if p.get("tls") else "",
            "sni": p.get("servername") or p.get("server-name") or "",
        }
        return "vmess://" + b64encode_text(json.dumps(obj, ensure_ascii=False)).rstrip("=")
    return None


def normalize_yaml_proxy(p: Dict[str, Any], fallback: str) -> Optional[Proxy]:
    typ = str(p.get("type", "")).lower()
    if typ not in {"ss", "trojan", "vmess", "vless"}:
        return None
    server = p.get("server")
    port = p.get("port")
    if not server or not port:
        return None
    out = dict(p)
    out["type"] = typ
    out["name"] = safe_name(p.get("name"), fallback)
    out["server"] = str(server)
    out["port"] = int(port)
    uri = yaml_proxy_to_uri(out)
    if uri:
        out["uri"] = uri
    return out


def parse_yaml_proxies(text: str) -> List[Proxy]:
    if yaml is None:
        return []
    try:
        obj = yaml.safe_load(text)
    except Exception:
        return []
    proxies = []
    if isinstance(obj, dict) and isinstance(obj.get("proxies"), list):
        for idx, item in enumerate(obj["proxies"], 1):
            if isinstance(item, dict):
                p = normalize_yaml_proxy(item, f"yaml-{idx}")
                if p:
                    proxies.append(p)
    elif isinstance(obj, list):
        for idx, item in enumerate(obj, 1):
            if isinstance(item, dict):
                p = normalize_yaml_proxy(item, f"yaml-{idx}")
                if p:
                    proxies.append(p)
    return proxies


def parse_text(text: str) -> List[Proxy]:
    proxies: List[Proxy] = []
    for match in URI_RE.finditer(text):
        uri = match.group(0).rstrip(",;]")
        p = parse_uri(uri)
        if p:
            proxies.append(p)
    proxies.extend(parse_yaml_proxies(text))
    return proxies


def key_for_proxy(p: Proxy) -> str:
    parts = [str(p.get("type", "")), str(p.get("server", "")), str(p.get("port", "")), str(p.get("uuid") or p.get("password") or p.get("uri") or "")]
    return hashlib.sha1("|".join(parts).encode()).hexdigest()


def tcp_alive(p: Proxy) -> bool:
    host = str(p.get("server") or "")
    port = int(p.get("port") or 0)
    if not host or port <= 0:
        return False
    try:
        with socket.create_connection((host, port), timeout=CHECK_TIMEOUT):
            return True
    except Exception:
        return False


def filter_alive(proxies: List[Proxy]) -> Tuple[List[Proxy], int]:
    if not CONNECT_CHECK:
        return proxies, 0
    dead = 0
    alive: List[Proxy] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        fut_map = {ex.submit(tcp_alive, p): p for p in proxies}
        for fut in concurrent.futures.as_completed(fut_map):
            p = fut_map[fut]
            ok = False
            try:
                ok = fut.result()
            except Exception:
                ok = False
            if ok:
                alive.append(p)
            else:
                dead += 1
    return alive, dead


def clash_proxy(p: Proxy) -> Optional[Dict[str, Any]]:
    typ = str(p.get("type", "")).lower()
    if typ not in {"ss", "trojan", "vmess", "vless"}:
        return None
    out: Dict[str, Any] = {
        "name": p["name"],
        "type": typ,
        "server": p["server"],
        "port": int(p["port"]),
    }
    if typ == "ss":
        out["cipher"] = p.get("cipher") or ""
        out["password"] = p.get("password") or ""
    elif typ == "trojan":
        out["password"] = p.get("password") or ""
        out["sni"] = p.get("sni") or p.get("servername") or ""
        out["skip-cert-verify"] = True
    elif typ == "vmess":
        out["uuid"] = p.get("uuid")
        out["alterId"] = int(p.get("alterId", 0) or 0)
        out["cipher"] = p.get("cipher") or "auto"
        out["network"] = p.get("network") or "tcp"
        if p.get("tls"):
            out["tls"] = True
            out["servername"] = p.get("servername") or ""
        if p.get("ws-opts"):
            out["ws-opts"] = p.get("ws-opts")
    elif typ == "vless":
        out["uuid"] = p.get("uuid")
        out["network"] = p.get("network") or "tcp"
        if p.get("tls"):
            out["tls"] = True
            out["servername"] = p.get("servername") or ""
        if p.get("flow"):
            out["flow"] = p.get("flow")
    return out


def write_outputs(proxies: List[Proxy], status: Dict[str, Any]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    uri_lines = [p.get("uri", "") for p in proxies if p.get("uri")]
    uri_text = "\n".join(uri_lines) + ("\n" if uri_lines else "")
    (OUTPUT_DIR / "uri.txt").write_text(uri_text, "utf-8")
    (OUTPUT_DIR / "v2ray.txt").write_text(b64encode_text(uri_text), "utf-8")

    clash_list = [cp for p in proxies if (cp := clash_proxy(p))]
    names = [p["name"] for p in clash_list]
    clash_config = {
        "mixed-port": 7890,
        "allow-lan": False,
        "mode": "rule",
        "log-level": "info",
        "proxies": clash_list,
        "proxy-groups": [{"name": "PROXY", "type": "select", "proxies": names or ["DIRECT"]}],
        "rules": ["MATCH,PROXY"],
    }
    if yaml is not None:
        clash_text = yaml.safe_dump(clash_config, allow_unicode=True, sort_keys=False)
    else:
        clash_text = json.dumps(clash_config, ensure_ascii=False, indent=2)
    (OUTPUT_DIR / "clash.yaml").write_text(clash_text, "utf-8")
    (OUTPUT_DIR / "status.json").write_text(json.dumps(status, ensure_ascii=False, indent=2), "utf-8")


def main() -> int:
    start = time.time()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    sources = read_sources(SOURCES_FILE)
    log(f"Loaded {len(sources)} sources")
    fetched: List[Tuple[str, Optional[str], Optional[str]]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(24, max(4, len(sources)))) as ex:
        for item in ex.map(fetch_url, sources):
            fetched.append(item)

    all_proxies: List[Proxy] = []
    source_status = []
    for url, text, err in fetched:
        if err or text is None:
            source_status.append({"url": url, "ok": False, "error": err})
            continue
        proxies = parse_text(text)
        source_status.append({"url": url, "ok": True, "parsed": len(proxies)})
        all_proxies.extend(proxies)

    seen = set()
    unique: List[Proxy] = []
    for p in all_proxies:
        if not p.get("server") or not p.get("port"):
            continue
        key = key_for_proxy(p)
        if key in seen:
            continue
        seen.add(key)
        p["name"] = safe_name(p.get("name"), f"node-{len(unique) + 1}")
        unique.append(p)

    log(f"Parsed {len(all_proxies)} nodes, unique {len(unique)} nodes")
    alive, dead_count = filter_alive(unique)
    if CONNECT_CHECK:
        log(f"TCP alive {len(alive)} nodes, removed {dead_count} dead nodes")
    else:
        log("CONNECT_CHECK=0, skipped TCP check")
    alive = alive[:MAX_NODES]
    for idx, p in enumerate(alive, 1):
        p["name"] = f"Starss-{idx} {safe_name(p.get('name'), f'node-{idx}') }"
        if p.get("uri"):
            old = str(p["uri"])
            if "#" in old:
                old = old.split("#", 1)[0]
            p["uri"] = old + "#" + urllib.parse.quote(p["name"])

    status = {
        "generated_at": dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        "elapsed_seconds": round(time.time() - start, 2),
        "connect_check": CONNECT_CHECK,
        "source_count": len(sources),
        "raw_parsed_count": len(all_proxies),
        "unique_count": len(unique),
        "output_count": len(alive),
        "dead_removed_count": dead_count,
        "sources": source_status,
    }
    write_outputs(alive, status)
    log(f"Wrote {OUTPUT_DIR}/v2ray.txt, uri.txt, clash.yaml, status.json")
    return 0 if alive else 2


if __name__ == "__main__":
    sys.exit(main())
