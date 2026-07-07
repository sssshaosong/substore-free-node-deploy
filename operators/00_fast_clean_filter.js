async function operator(proxies) {
  const STRINGS_TO_REMOVE = [
    'ProxyGo免费节点分享',
    '免费节点',
    'TG频道',
    '联系客服',
    ' | free-nodes',
  ];

  function escapeRegex(string) {
    return String(string).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function cleanName(name) {
    if (!name) return name;
    let cleaned = String(name).replace(/æªç¥/g, '未知');
    for (const str of STRINGS_TO_REMOVE) {
      const regex = new RegExp(`\\s*[\\(（]?\\s*${escapeRegex(str)}\\s*[\\)）]?\\s*`, 'g');
      cleaned = cleaned.replace(regex, ' ').trim();
    }
    cleaned = cleaned.replace(/\s{2,}/g, ' ').trim();
    return cleaned || name;
  }

  const seen = new Set();
  const out = [];
  for (const proxy of proxies) {
    if (!proxy || !proxy.server || !proxy.port || !proxy.type) continue;
    const key = [proxy.type, proxy.server, proxy.port, proxy.uuid || proxy.password || proxy.name].join('|');
    if (seen.has(key)) continue;
    seen.add(key);
    proxy.name = `Starss-${out.length + 1} ${cleanName(proxy.name)}`;
    out.push(proxy);
  }
  return out;
}
