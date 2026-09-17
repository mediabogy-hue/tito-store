const GITHUB_API = 'https://api.github.com';
const REPO = 'mediabogy-hue/tito-store';
const FILE_PATH = 'products.json';

function authHeaders() {
  return {
    Authorization: `Bearer ${process.env.GITHUB_TOKEN}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type': 'application/json'
  };
}

export default async function handler(req, res) {
  try {
    if (req.method === 'GET') {
      const r = await fetch(`${GITHUB_API}/repos/${REPO}/contents/${FILE_PATH}`);
      if (!r.ok) return res.status(502).json({ error: 'Could not load products' });
      const file = await r.json();
      const products = JSON.parse(Buffer.from(file.content, 'base64').toString('utf8'));
      return res.status(200).json(products);
    }

    // Admin login check. GET stays public so the storefront can read products.
    if (req.method === 'POST') {
      const key = String(req.body?.key || '');
      if (!process.env.ADMIN_KEY || key !== process.env.ADMIN_KEY) {
        return res.status(401).json({ error: 'Invalid admin password' });
      }
      return res.status(200).json({ ok: true });
    }

    if (req.method !== 'PUT') {
      return res.status(405).json({ error: 'Method not allowed' });
    }

    const adminKey = req.headers['x-admin-key'];
    if (!process.env.ADMIN_KEY || adminKey !== process.env.ADMIN_KEY) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    if (!process.env.GITHUB_TOKEN) {
      return res.status(500).json({ error: 'GITHUB_TOKEN is not configured' });
    }

    const products = Array.isArray(req.body) ? req.body : req.body?.products;
    if (!Array.isArray(products)) {
      return res.status(400).json({ error: 'Products must be an array' });
    }

    const clean = products.map((p, i) => ({
      id: String(p.id || `product-${Date.now()}-${i}`),
      name: String(p.name || '').trim(),
      category: String(p.category || 'tshirt'),
      price: Number(p.price || 0),
      oldPrice: p.oldPrice === null || p.oldPrice === '' ? null : Number(p.oldPrice),
      sizes: Array.isArray(p.sizes) ? p.sizes.map(String).filter(Boolean) : [],
      colors: Array.isArray(p.colors) ? p.colors.map(String).filter(Boolean) : [],
      stock: Number.isFinite(Number(p.stock)) ? Number(p.stock) : 0,
      image: String(p.image || '').trim(),
      note: String(p.note || '').trim(),
      lastPieces: Boolean(p.lastPieces),
      active: p.active !== false
    }));

    if (clean.some(p => !p.name || p.price < 0)) {
      return res.status(400).json({ error: 'Each product needs a name and a valid price' });
    }

    const current = await fetch(`${GITHUB_API}/repos/${REPO}/contents/${FILE_PATH}`, { headers: authHeaders() });
    if (!current.ok) return res.status(502).json({ error: 'Could not read current catalog' });
    const currentFile = await current.json();

    const content = JSON.stringify(clean, null, 2) + '\n';
    const update = await fetch(`${GITHUB_API}/repos/${REPO}/contents/${FILE_PATH}`, {
      method: 'PUT',
      headers: authHeaders(),
      body: JSON.stringify({
        message: 'Update BLNK product catalog',
        content: Buffer.from(content).toString('base64'),
        sha: currentFile.sha,
        branch: 'main'
      })
    });

    if (!update.ok) {
      const details = await update.text();
      return res.status(502).json({ error: 'GitHub update failed', details });
    }

    return res.status(200).json({ ok: true, products: clean });
  } catch (error) {
    return res.status(500).json({ error: 'Server error', details: error.message });
  }
}
