export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Vercel env vars are case-sensitive. Support the official name plus the
  // lowercase/legacy names so an existing deployment does not fail silently.
  const apiKey = (
    process.env.FASHN_API_KEY ||
    process.env.fashn_api_key ||
    process.env.FASHN_API_TOKEN
  )?.trim();
  if (!apiKey) {
    return res.status(500).json({
      error: 'FASHN_API_KEY is missing from the Vercel runtime. Add it to the deployed environment and redeploy.'
    });
  }

  try {
    const { model_image, product_image, prompt } = req.body || {};
    if (!model_image || !product_image) {
      return res.status(400).json({ error: 'model_image and product_image are required.' });
    }

    const response = await fetch('https://api.fashn.ai/v1/run', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model_name: 'tryon-max',
        inputs: {
          model_image,
          product_image,
          ...(prompt ? { prompt } : {}),
          return_base64: true
        }
      })
    });

    const data = await response.json();
    if (!response.ok) {
      const raw = data?.error || data?.message || 'FASHN request failed.';
      const message = response.status === 401
        ? 'FASHN rejected the API key (UnauthorizedAccess). Check that the Vercel value is the active FASHN API key, with no quotes/spaces, then redeploy.'
        : raw;
      return res.status(response.status).json({ error: message });
    }

    return res.status(200).json({ id: data.id, error: data.error || null });
  } catch (error) {
    return res.status(500).json({ error: error?.message || 'Try-on service failed.' });
  }
}
