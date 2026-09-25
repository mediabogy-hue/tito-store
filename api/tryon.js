export const config = { api: { bodyParser: { sizeLimit: '8mb' } } };

function dataUrlToBlob(dataUrl) {
  const match = /^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/.exec(dataUrl || '');
  if (!match) throw new Error('Invalid customer image.');
  return new Blob([Buffer.from(match[2], 'base64')], { type: match[1] });
}

async function productToBlob(value) {
  if ((value || '').startsWith('data:')) return dataUrlToBlob(value);
  const r = await fetch(value);
  if (!r.ok) throw new Error('Could not load product image.');
  const type = r.headers.get('content-type') || 'image/jpeg';
  return new Blob([await r.arrayBuffer()], { type });
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const apiKey = process.env.OPENAI_API_KEY?.trim();
  if (!apiKey) return res.status(500).json({ error: 'OPENAI_API_KEY is not configured on Vercel.' });

  try {
    const { model_image, product_image, product_name } = req.body || {};
    if (!model_image || !product_image) return res.status(400).json({ error: 'model_image and product_image are required.' });

    const person = dataUrlToBlob(model_image);
    const garment = await productToBlob(product_image);
    const form = new FormData();
    form.append('model', 'gpt-image-2');
    form.append('image[]', person, 'customer.jpg');
    form.append('image[]', garment, 'garment.jpg');
    form.append('size', '1024x1536');
    form.append('quality', 'medium');
    form.append('output_format', 'jpeg');
    form.append('prompt', `Virtual clothing try-on for an ecommerce preview. Image 1 is the customer and Image 2 is the exact BLNK garment reference${product_name ? ` named "${product_name}"` : ''}. Edit Image 1 so the customer is naturally wearing the garment from Image 2. Preserve the customer's face, facial features, skin tone, body shape, pose, identity, hairstyle, expression, hands, background, camera angle and framing. Replace only the relevant clothing. Preserve the garment's design, color, texture, print, logos and proportions as faithfully as possible. Fit it naturally with realistic fabric draping, folds, occlusion, lighting and shadows. Do not add accessories, text, watermarks or change the scene.`);

    const response = await fetch('https://api.openai.com/v1/images/edits', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form
    });
    const data = await response.json();
    if (!response.ok) {
      const code = data?.error?.code || '';
      const raw = data?.error?.message || '';
      const billing = code === 'credit_balance_exhausted' || /credits|quota|billing|spend limit/i.test(raw);
      return res.status(response.status).json({
        error: billing
          ? 'الخدمة غير متاحة مؤقتًا، حاول مرة أخرى لاحقًا.'
          : 'تعذر تنفيذ تجربة المنتج الآن، حاول مرة أخرى.'
      });
    }
    const b64 = data?.data?.[0]?.b64_json;
    if (!b64) return res.status(502).json({ error: 'OpenAI did not return an image.' });
    return res.status(200).json({ output: `data:image/jpeg;base64,${b64}` });
  } catch (error) {
    return res.status(500).json({ error: error?.message || 'Try-on service failed.' });
  }
}