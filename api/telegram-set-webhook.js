export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const base = String(process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const publishable = process.env.SUPABASE_PUBLISHABLE_KEY || '';
  const botToken = process.env.TELEGRAM_BOT_TOKEN || '';
  const secret = process.env.TELEGRAM_WEBHOOK_SECRET || '';
  const siteUrl = String(process.env.BLNK_SITE_URL || '').replace(/\/$/, '');
  const authorization = String(req.headers.authorization || '');
  if (!base || !publishable || !botToken || !secret || !siteUrl) {
    return res.status(503).json({ error: 'Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET, and BLNK_SITE_URL first' });
  }
  if (!authorization.startsWith('Bearer ')) return res.status(401).json({ error: 'Admin sign-in required' });
  if (!siteUrl.startsWith('https://')) return res.status(503).json({ error: 'BLNK_SITE_URL must use HTTPS' });
  try {
    const check = await fetch(`${base}/rest/v1/rpc/is_admin`, {
      method: 'POST',
      headers: { apikey: publishable, Authorization: authorization, 'Content-Type': 'application/json' },
      body: '{}'
    });
    if (!check.ok || await check.json() !== true) return res.status(403).json({ error: 'BLNK admin access required' });
    const webhookResponse = await fetch(`https://api.telegram.org/bot${botToken}/setWebhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        url: `${siteUrl}/api/telegram-webhook`,
        allowed_updates: ['channel_post'],
        secret_token: secret,
        drop_pending_updates: false
      })
    });
    const result = await webhookResponse.json();
    if (!webhookResponse.ok || !result.ok) return res.status(502).json({ error: 'Telegram rejected the webhook setup' });
    return res.status(200).json({ ok: true, webhook: 'configured' });
  } catch {
    return res.status(502).json({ error: 'Could not configure Telegram webhook' });
  }
}
