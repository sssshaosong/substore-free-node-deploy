async function operator(proxies, targetPlatform, context) {
  const now = new Date();
  const Y = now.getFullYear();
  const M = String(now.getMonth() + 1).padStart(2, '0');
  const D = String(now.getDate()).padStart(2, '0');
  const TODAY = `${Y}${M}${D}`;
  const VARIANT = 1;
  const FETCH_URL = `https://raw.githubusercontent.com/free-nodes/v2rayfree/main/v${TODAY}${VARIANT}`;

  const STRINGS_TO_REMOVE = [' | free-nodes'];
  const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const isDomainLike = (s) => {
    const t = String(s || '').trim();
    return /^[a-zA-Z0-9.-]+\.[a-z]{2,}$/i.test(t) && !/^(\d{1,3}\.){3}\d{1,3}$/.test(t);
  };

  function cleanName(name) {
    if (!name) return name;
    let cleaned = name.replace(/æªç¥/g, '未知');
    for (const str of STRINGS_TO_REMOVE) {
      const regex = new RegExp(`\\s*[\\(（]?\\s*${escapeRegex(str)}\\s*[\\)）]?\\s*`, 'g');
      cleaned = cleaned.replace(regex, ' ').trim();
    }
    cleaned = cleaned.replace(/\s{2,}/g, ' ').trim();
    for (const delim of ['|', '｜', '+', '-']) {
      const idx = cleaned.indexOf(delim);
      if (idx > -1) {
        const part1 = cleaned.substring(0, idx).trim();
        const part2 = cleaned.substring(idx + delim.length).trim();
        if (isDomainLike(part2) && part1.length > 0) return part1;
      }
    }
    return cleaned.replace(/\s+[a-zA-Z0-9.-]*[a-zA-Z][a-zA-Z0-9.-]*\.[a-z]{2,}(?:\/.*)?\s*$/i, '').trim() || cleaned;
  }

  function parseNodeLine(line) {
    try {
      line = line.trim();
      if (line.startsWith('vmess://')) {
        const json = JSON.parse(atob(line.substring(8)));
        return {
          name: json.ps || 'vmess节点',
          server: json.add,
          port: parseInt(json.port, 10) || 443,
          type: 'vmess',
          uuid: json.id,
          alterId: Number(json.aid || 0),
          cipher: json.scy || 'auto',
          tls: json.tls === 'tls',
          network: json.net || 'tcp',
          wsPath: json.path || undefined,
          wsHeaders: json.host ? { Host: json.host } : undefined,
          sni: json.sni || undefined,
        };
      }
      if (line.startsWith('vless://')) {
        const u = new URL(line);
        return {
          name: u.hash ? decodeURIComponent(u.hash.slice(1)) : 'vless节点',
          server: u.hostname,
          port: parseInt(u.port, 10) || 443,
          type: 'vless',
          uuid: u.username,
          flow: u.searchParams.get('flow') || undefined,
          tls: u.searchParams.get('security') === 'tls' || u.searchParams.get('security') === 'reality',
          network: u.searchParams.get('type') || 'tcp',
          servername: u.searchParams.get('sni') || undefined,
          realityOpts: u.searchParams.get('security') === 'reality' ? {
            publicKey: u.searchParams.get('pbk') || undefined,
            shortId: u.searchParams.get('sid') || undefined,
          } : undefined,
        };
      }
      if (line.startsWith('trojan://')) {
        const u = new URL(line);
        return {
          name: u.hash ? decodeURIComponent(u.hash.slice(1)) : 'trojan节点',
          server: u.hostname,
          port: parseInt(u.port, 10) || 443,
          type: 'trojan',
          password: u.username,
          tls: true,
          sni: u.searchParams.get('sni') || undefined,
        };
      }
      if (line.startsWith('ss://')) {
        const u = new URL(line);
        let name = u.hash ? decodeURIComponent(u.hash.slice(1)) : 'SS节点';
        let method = '';
        let password = '';
        try {
          const decoded = atob(u.username);
          const parts = decoded.split(':');
          method = parts.shift();
          password = parts.join(':');
        } catch {
          const parts = u.username.split(':');
          method = parts.shift();
          password = parts.join(':');
        }
        return {
          name,
          server: u.hostname,
          port: parseInt(u.port, 10) || 8388,
          type: 'ss',
          cipher: method,
          password,
        };
      }
      return null;
    } catch {
      return null;
    }
  }

  async function httpGet(url) {
    if (typeof fetch === 'function') {
      const resp = await fetch(url);
      return await resp.text();
    }
    if (typeof $httpClient !== 'undefined') {
      return new Promise((resolve, reject) => {
        $httpClient.get(url, (err, resp, data) => err ? reject(err) : resolve(data));
      });
    }
    if (typeof $task !== 'undefined') {
      const resp = await $task.fetch(url);
      return resp.body;
    }
    throw new Error('No available HTTP client');
  }

  try {
    const rawText = await httpGet(FETCH_URL);
    let lines = [];
    try {
      lines = atob(rawText).split('\n').filter(l => l.trim() !== '');
    } catch {
      lines = rawText.split('\n').filter(l => l.trim() !== '');
    }
    const fetchedProxies = lines.map(parseNodeLine).filter(Boolean);
    let candidates = fetchedProxies.length > 0 ? fetchedProxies : proxies;
    candidates = candidates.filter(p => p.server && p.port);
    if (candidates.length === 0) return proxies.map(p => { p.name = '[无有效节点] ' + p.name; return p; });
    return candidates.map(p => { p.name = cleanName(p.name); return p; });
  } catch (e) {
    console.error('operator error: ' + e);
    return proxies;
  }
}
