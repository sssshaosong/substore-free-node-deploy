async function operator(proxies) {
  const TEST_URL = 'http://www.gstatic.com/generate_204';
  const TIMEOUT = 5000;
  const MAX_DELAY = 800;
  const CONCURRENCY = 6;
  const KEEP_REGEX = /香港|HK|🇭🇰|US|🇺🇸|美国|日本|JP|西班牙|德国|台湾|法国|韩国|巴西|新加坡|英国|加拿大|捷克|荷兰|土耳其|南非|俄罗斯|罗马尼亚|阿根廷|未知|RU|GB|KR|DE|🇮🇳|🇵🇭|🇦🇺|🇹🇭|🇻🇳|🇰🇭|🇯🇵|🇸🇬|🇹🇼|🇲🇾|🇲🇴|🇦🇷|SG/i;
  const STRINGS_TO_REMOVE = ['ProxyGo免费节点分享', '免费节点', 'TG频道', '联系客服'];

  function escapeRegex(string) {
    return String(string).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  function cleanName(name) {
    if (!name) return name;
    let cleaned = String(name);
    for (const str of STRINGS_TO_REMOVE) {
      const regex = new RegExp(`\\s*[\\(（]?\\s*${escapeRegex(str)}\\s*[\\)）]?\\s*`, 'g');
      cleaned = cleaned.replace(regex, ' ').trim();
    }
    cleaned = cleaned.replace(/\s{2,}/g, ' ').trim();

    const isDomainLike = (s) => {
      const t = String(s || '').trim();
      return /^[a-zA-Z0-9.-]+\.[a-z]{2,}$/i.test(t) && !/^(\d{1,3}\.){3}\d{1,3}$/.test(t);
    };
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

  function chunk(arr, size) {
    const out = [];
    for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
    return out;
  }

  const candidates = proxies.filter(p => KEEP_REGEX.test(p.name || '') && p.server && p.port);
  if (candidates.length === 0) return proxies.map(p => { p.name = '[无候选] ' + p.name; return p; });

  const $ = $substore;
  let internalProxies = [];
  try {
    internalProxies = ProxyUtils.produce(candidates, 'ClashMeta', 'internal');
  } catch {
    try {
      internalProxies = ProxyUtils.produce(candidates, 'Clash', 'internal');
    } catch (e) {
      console.log(`[SCOPE] ERROR: 节点转换失败: ${e.message}`);
      return proxies;
    }
  }

  let startBody;
  try {
    const startRes = await $.http.post({
      url: 'http://127.0.0.1:9876/start',
      headers: { 'content-type': 'application/json' },
      timeout: 10000,
      body: JSON.stringify({ proxies: internalProxies, timeout: TIMEOUT }),
    });
    startBody = JSON.parse(startRes.body);
    if (!startBody?.pid || !Array.isArray(startBody?.ports) || startBody.ports.length !== candidates.length) {
      throw new Error('启动响应无效');
    }
  } catch (e) {
    console.log(`[SCOPE] ERROR: 启动 http-meta 测速服务失败: ${e.message}`);
    return proxies;
  }

  await $.wait(1500);

  const testResults = new Array(candidates.length).fill(null);
  const groups = chunk(candidates.map((_, index) => index), CONCURRENCY);
  for (const group of groups) {
    await Promise.all(group.map(async (index) => {
      const proxyUrl = `http://127.0.0.1:${startBody.ports[index]}`;
      try {
        const startTime = Date.now();
        await $.http.get({ url: TEST_URL, timeout: TIMEOUT, proxy: proxyUrl });
        testResults[index] = { alive: true, delay: Date.now() - startTime };
      } catch {
        testResults[index] = { alive: false, delay: Infinity };
      }
    }));
  }

  try {
    await $.http.post({
      url: 'http://127.0.0.1:9876/stop',
      headers: { 'content-type': 'application/json' },
      timeout: 5000,
      body: JSON.stringify({ pid: [startBody.pid] }),
    });
  } catch {}

  candidates.forEach((proxy, index) => {
    proxy._health = testResults[index]?.alive ? testResults[index].delay : Infinity;
  });

  return candidates
    .filter(p => p._health <= MAX_DELAY && p._health < 999999)
    .sort((a, b) => a._health - b._health)
    .map(p => {
      p.name = `Starss-Node [${p._health}ms] ${cleanName(p.name)}`;
      return p;
    });
}
