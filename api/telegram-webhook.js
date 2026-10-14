import crypto from 'node:crypto';

const BUCKET = 'blnk-supplier-products';
const MAX_PHOTO_BYTES = 10 * 1024 * 1024;

function env() {
  return {
    base: String(process.env.SUPABASE_URL || '').replace(/\/$/, ''),
    key: process.env.SUPABASE_SERVICE_ROLE_KEY || '',
    bot: process.env.TELEGRAM_BOT_TOKEN || '',
    secret: process.env.TELEGRAM_WEBHOOK_SECRET || ''
  };
}

function secureEqual(left, right) {
  const a = Buffer.from(String(left || ''));
  const b = Buffer.from(String(right || ''));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function digits(text) {
  return String(text || '').replace(/[٠-٩۰-۹]/g, c => String('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹'.indexOf(c) % 10));
}

function parsePost(text) {
  const clean = digits(text).replace(/\r/g, '');
  const priceMatch = clean.match(/(?:السعر|سعر|price|egp|جنيه|ج\.?م)\s*[:=\-]?\s*([0-9]+(?:\.[0-9]{1,2})?)/i)
    || clean.match(/([0-9]+(?:\.[0-9]{1,2})?)\s*(?:جنيه|ج\.?م|egp|ج)(?:\s|$)/i);
  const stockMatch = clean.match(/(?:الكمية|المتاح|متوفر|مخزون|stock)\D{0,12}([0-9]+)/i);
  const lines = clean.split('\n').map(x => x.trim()).filter(Boolean);
  const name = lines.find(x => !/(?:السعر|price|egp|جنيه|مقاس|لون|الكمية|المتاح|مخزون|stock)\s*[:=]/i.test(x) && x.length > 2) || '';
  const sizeMatch = clean.match(/(?:المقاسات|مقاسات|sizes?)\s*[:=\-]?\s*([^\n]+)/i);
  const colorMatch = clean.match(/(?:الألوان|اللون|colors?)\s*[:=\-]?\s*([^\n]+)/i);
  return {
    name: name.slice(0, 160),
    supplierPrice: priceMatch ? Number(priceMatch[1]) : null,
    stock: stockMatch ? Number(stockMatch[1]) : null,
    sizes: sizeMatch ? sizeMatch[1].trim().slice(0, 160) : null,
    colors: colorMatch ? colorMatch[1].trim().slice(0, 160) : null
  };
}

function restUrl(base, path) { return `${base}/rest/v1/${path}`; }

async function restRequest(base, key, path, method = 'GET', body, prefer) {
  const headers = { apikey: key, Authorization: `Bearer ${key}`, Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (prefer) headers.Prefer = prefer;
  const response = await fetch(restUrl(base, path), { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const payload = await response.text();
  if (!response.ok) throw new Error(`database_request_${response.status}:${payload.slice(0, 300)}`);
  try { return payload ? JSON.parse(payload) : null; } catch { return null; }
}

async function storeTelegramPhoto(cfg, message, chatId) {
  if (!Array.isArray(message.photo) || !message.photo.length) return null;
  const photo = message.photo[message.photo.length - 1];
  const fileInfoResponse = await fetch(`https://api.telegram.org/bot${cfg.bot}/getFile?file_id=${encodeURIComponent(photo.file_id)}`);
  if (!fileInfoResponse.ok) throw new Error('telegram_get_file_failed');
  const fileInfo = await fileInfoResponse.json();
  const filePath = fileInfo?.result?.file_path;
  if (!fileInfo.ok || !filePath) throw new Error('telegram_file_path_missing');
  const ext = (filePath.split('.').pop() || 'jpg').toLowerCase();
  const mime = ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
  const fileResponse = await fetch(`https://api.telegram.org/file/bot${cfg.bot}/${filePath}`);
  if (!fileResponse.ok) throw new Error('telegram_photo_download_failed');
  const buffer = Buffer.from(await fileResponse.arrayBuffer());
  if (!buffer.length || buffer.length > MAX_PHOTO_BYTES) throw new Error('telegram_photo_size_invalid');
  const objectPath = `telegram/${String(chatId).replace(/[^0-9-]/g, '')}/${message.message_id}.${ext}`;
  const upload = await fetch(`${cfg.base}/storage/v1/object/${BUCKET}/${objectPath}`, {
    method: 'POST',
    headers: { apikey: cfg.key, Authorization: `Bearer ${cfg.key}`, 'Content-Type': mime, 'x-upsert': 'true' },
    body: buffer
  });
  if (!upload.ok) throw new Error(`photo_storage_${upload.status}`);
  return `${cfg.base}/storage/v1/object/public/${BUCKET}/${objectPath.split('/').map(encodeURIComponent).join('/')}`;
}

async function claimUpdate(cfg, updateId) {
  const inserted = await restRequest(cfg.base, cfg.key, 'telegram_webhook_updates?on_conflict=update_id', 'POST',
    { update_id: updateId, status: 'processing' }, 'resolution=ignore-duplicates,return=representation');
  if (Array.isArray(inserted) && inserted.length) return 'claimed';
  const rows = await restRequest(cfg.base, cfg.key, `telegram_webhook_updates?update_id=eq.${updateId}&select=status,created_at`);
  const row = rows?.[0];
  if (!row || row.status === 'processed') return 'duplicate';
  if (row.status === 'processing' && Date.now() - Date.parse(row.created_at) < 120000) return 'duplicate';
  await restRequest(cfg.base, cfg.key, `telegram_webhook_updates?update_id=eq.${updateId}`, 'PATCH', { status: 'processing', error: null }, 'return=minimal');
  return 'claimed';
}

function sourceUrl(chat, messageId) {
  if (chat.username) return `https://t.me/${String(chat.username).replace(/^@/, '')}/${messageId}`;
  const channel = String(chat.id).replace(/^-100/, '');
  return String(chat.id).startsWith('-100') ? `https://t.me/c/${channel}/${messageId}` : null;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const cfg = env();
  if (!cfg.base || !cfg.key || !cfg.bot || !cfg.secret) return res.status(503).json({ error: 'Telegram intake is not configured' });
  if (!secureEqual(req.headers['x-telegram-bot-api-secret-token'], cfg.secret)) return res.status(401).json({ error: 'Unauthorized' });
  const update = req.body && typeof req.body === 'object' ? req.body : null;
  const message = update?.channel_post || update?.edited_channel_post;
  if (!message?.chat?.id || !message.message_id || !Number.isSafeInteger(update?.update_id)) return res.status(200).json({ ok: true, ignored: true });
  try {
    const claim = await claimUpdate(cfg, update.update_id);
    if (claim === 'duplicate') return res.status(200).json({ ok: true, duplicate: true });

    const chat = message.chat;
    const chatId = String(chat.id);
    const matches = await restRequest(cfg.base, cfg.key,
      `telegram_supplier_channels?telegram_chat_id=eq.${encodeURIComponent(chatId)}&active=eq.true&select=supplier_id,channel_title,username`);
    const mapping = matches?.[0] || null;
    const text = String(message.text || message.caption || '').slice(0, 10000);
    const parsed = parsePost(text);
    let imageUrl = null;
    try { imageUrl = await storeTelegramPhoto(cfg, message, chat.id); }
    catch (photoError) { /* Keep the post in review even if its image could not be copied. */ }

    let productId = null;
    let intakeStatus = mapping ? 'needs_review' : 'unmapped';
    if (mapping && parsed.name && parsed.supplierPrice !== null && parsed.supplierPrice >= 0 && parsed.stock !== null && parsed.stock > 0 && imageUrl) {
      const products = await restRequest(cfg.base, cfg.key, 'supplier_products?on_conflict=telegram_update_id', 'POST', {
        telegram_update_id: update.update_id,
        supplier_id: mapping.supplier_id,
        name: parsed.name,
        description: text || null,
        image_url: imageUrl,
        sizes: parsed.sizes,
        colors: parsed.colors,
        supplier_price: parsed.supplierPrice,
        stock: parsed.stock,
        status: 'pending',
        category: null,
        minimum_order_quantity: 1,
        source_channel: chat.title || mapping.channel_title || chat.username || chatId,
        source_message_url: sourceUrl(chat, message.message_id),
        source_message: text,
        updated_at: new Date().toISOString()
      }, 'resolution=ignore-duplicates,return=representation');
      productId = products?.[0]?.id || null;
      if (!productId) {
        const existing = await restRequest(cfg.base, cfg.key, `supplier_products?telegram_update_id=eq.${update.update_id}&select=id`);
        productId = existing?.[0]?.id || null;
      }
      if (productId) intakeStatus = 'imported';
    }

    await restRequest(cfg.base, cfg.key, 'telegram_supplier_intake?on_conflict=update_id', 'POST', {
      update_id: update.update_id,
      supplier_id: mapping?.supplier_id || null,
      telegram_chat_id: chatId,
      channel_title: chat.title || mapping?.channel_title || null,
      username: chat.username || mapping?.username || null,
      message_id: message.message_id,
      source_message_url: sourceUrl(chat, message.message_id),
      source_message: text,
      image_url: imageUrl,
      parsed_name: parsed.name || null,
      parsed_supplier_price: parsed.supplierPrice,
      parsed_stock: parsed.stock,
      product_id: productId,
      status: intakeStatus
    }, 'resolution=merge-duplicates,return=minimal');
    await restRequest(cfg.base, cfg.key, `telegram_webhook_updates?update_id=eq.${update.update_id}`, 'PATCH',
      { status: 'processed', processed_at: new Date().toISOString(), error: null }, 'return=minimal');
    return res.status(200).json({ ok: true, status: intakeStatus });
  } catch (error) {
    try {
      await restRequest(cfg.base, cfg.key, `telegram_webhook_updates?update_id=eq.${update.update_id}`, 'PATCH',
        { status: 'failed', error: String(error?.message || 'intake_error').slice(0, 300) }, 'return=minimal');
    } catch {}
    return res.status(500).json({ error: 'Telegram intake failed' });
  }
}
