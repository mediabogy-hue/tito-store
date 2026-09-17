export default async function handler(req, res) {
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });

  const apiKey = (
    process.env.FASHN_API_KEY ||
    process.env.fashn_api_key ||
    process.env.FASHN_API_TOKEN
  )?.trim();
  const id = req.query?.id;

  if (!apiKey) {
    return res.status(500).json({
      error: 'FASHN_API_KEY is missing from the Vercel runtime. Add it to the deployed environment and redeploy.'
    });
  }
  if (!id) return res.status(400).json({ error: 'Missing prediction id.' });

  try {
    const r = await fetch(`https://api.fashn.ai/v1/status/${encodeURIComponent(id)}`, {
      headers: { Authorization: `Bearer ${apiKey}` }
    });
    const d = await r.json();
    if (!r.ok) {
      const raw = d?.error || d?.message || 'FASHN status request failed.';
      const message = r.status === 401
        ? 'FASHN rejected the API key (UnauthorizedAccess). Check the active FASHN API key in Vercel, with no quotes/spaces, then redeploy.'
        : raw;
      return res.status(r.status).json({ error: message });
    }
    return res.status(200).json({ status: d.status, output: d.output || null, error: d.error || null });
  } catch (error) {
    return res.status(500).json({ error: error?.message || 'Try-on status failed.' });
  }
}
