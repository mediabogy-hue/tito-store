const ALLOWED_HOSTS = new Set(['shop.iravin.com']);

export default async function handler(req, res) {
  try {
    const raw = String(req.query.url || '');
    if (!raw) return res.status(400).send('Missing url');
    const u = new URL(raw);
    if (u.protocol !== 'https:' || !ALLOWED_HOSTS.has(u.hostname)) return res.status(400).send('Unsupported source');
    const page = await fetch(u.toString(), { headers: { 'User-Agent': 'Mozilla/5.0 BLNK-Catalog/1.0' } });
    if (!page.ok) return res.status(502).send('Source unavailable');
    const html = await page.text();
    const m = html.match(/<meta[^>]+(?:property|name)=["']og:image(?::secure_url)?["'][^>]+content=["']([^"']+)["']/i)
      || html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']og:image(?::secure_url)?["']/i);
    if (!m) return res.status(404).send('Image unavailable');
    const img = m[1].replace(/&amp;/g, '&');
    const ir = await fetch(img);
    if (!ir.ok) return res.status(502).send('Image unavailable');
    res.setHeader('Content-Type', ir.headers.get('content-type') || 'image/jpeg');
    res.setHeader('Cache-Control', 'public, s-maxage=21600, stale-while-revalidate=86400');
    const buf = Buffer.from(await ir.arrayBuffer());
    return res.status(200).send(buf);
  } catch (e) {
    return res.status(500).send('Image proxy error');
  }
}