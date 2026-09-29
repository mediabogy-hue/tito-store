(async () => {
  const q = selector => document.querySelector(selector);
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const money = value => 'EGP ' + Number(value || 0).toLocaleString('ar-EG');
  const labels = {preparing:'جاري التجهيز',ready_to_ship:'جاهز للشحن',shipped:'تم الشحن',out_for_delivery:'خرج للتسليم',delivered:'تم التسليم',cancelled:'ملغي'};
  let sb;
  try {
    const response = await fetch('/api/public-config');
    if (!response.ok) throw new Error('تعذر تحميل إعدادات الاتصال');
    const cfg = await response.json();
    sb = supabase.createClient(cfg.supabaseUrl, cfg.supabasePublishableKey);
  } catch (error) {
    q('#msg').textContent = error.message;
    return;
  }

  const shippingMode = () => location.hash === '#shipping';
  async function showShipments(orderId) {
    const box = document.getElementById('ship-' + orderId);
    if (!box) return;
    const {data, error} = await sb.rpc('admin_order_shipments', {p_order_id: orderId});
    if (error) { box.textContent = error.message; return; }
    const rows = data || [];
    box.innerHTML = '<button class="button button-dark" data-prepare="' + orderId + '">تجهيز سجلات الشحن</button>' +
      (rows.length ? rows.map(row => '<div class="supplier"><b>' + escapeHtml(row.supplier_name || 'BLNK') + '</b> · <span class="tag">' + escapeHtml(row.status) + '</span><br>رقم التتبع: ' + escapeHtml(row.tracking_number || 'لم يسجل') + ' · ' + money(row.shipping_fee) + '<div class="actions"><button class="button button-light" data-tracking="' + row.id + '" data-order-id="' + orderId + '">تسجيل رقم التتبع</button>' + (row.tracking_url ? '<a class="button button-light" target="_blank" rel="noopener noreferrer" href="' + escapeHtml(row.tracking_url) + '">تتبع</a>' : '') + '</div></div>').join('') : '<p class="muted">لا توجد شحنة بعد. تأكد من تأكيد المورد، ثم جهّز سجلات الشحن.</p>');
  }

  async function detail(id) {
    const box = document.getElementById('detail-' + id);
    if (!box) return;
    if (!box.hidden) { box.hidden = true; return; }
    box.hidden = false;
    box.textContent = 'جاري التحميل...';
    const {data, error} = await sb.rpc('admin_order_detail', {p_order_id:id});
    if (error) { box.textContent = error.message; return; }
    const customer = data.customer || {}, items = data.items || [], suppliers = data.suppliers || [], refunds = data.refunds || [];
    box.innerHTML = '<h3>العميل</h3><div>' + escapeHtml(customer.name) + ' · ' + escapeHtml(customer.phone) + (customer.whatsapp ? ' · WhatsApp ' + escapeHtml(customer.whatsapp) : '') + '<br>' + escapeHtml(customer.address) + ' ' + escapeHtml(customer.city) + '</div><h3>المنتجات</h3>' +
      items.map(item => '<div class="item"><b>' + escapeHtml(item.name) + '</b> × ' + Number(item.qty || 0) + ' · ' + money(item.unit_price) + '<br>مقاس ' + escapeHtml(item.size || '-') + ' · لون ' + escapeHtml(item.color || '-') + (item.source_url ? '<div class="supplier" style="margin-top:8px"><b>المصدر: ' + escapeHtml(item.source_brand || 'External Brand') + '</b>' + (item.source_sku ? ' · SKU ' + escapeHtml(item.source_sku) : '') + (item.source_price != null ? '<br>سعر المصدر وقت الطلب: ' + money(item.source_price) : '') + '<div class="actions" style="margin-top:8px"><a class="button button-dark" target="_blank" rel="noopener noreferrer" href="' + escapeHtml(item.source_url) + '">اطلب من البراند الأصلي ↗</a></div></div>' : '') + '</div>').join('') +
      '<h3>الشحن</h3><div id="ship-' + id + '">جاري تحميل الشحنات...</div><h3>الموردين</h3>' +
      (suppliers.length ? suppliers.map(item => '<div class="supplier"><b>' + escapeHtml(item.supplier) + '</b> · ' + escapeHtml(item.product) + ' × ' + Number(item.qty || 0) + ' <span class="tag">' + escapeHtml(item.status) + '</span><br>مستحق ' + money(item.supplier_amount) + ' · هامش BLNK ' + money(item.margin) + '</div>').join('') : '<div class="muted">منتجات BLNK مباشرة — لا يوجد مورد خارجي.</div>') +
      (refunds.length ? '<h3>Refunds</h3>' + refunds.map(item => '<div class="refund"><b>' + money(item.amount) + '</b> · ' + escapeHtml(item.description || 'Refund') + '</div>').join('') : '');
    await showShipments(id);
  }

  async function load() {
    const session = (await sb.auth.getSession()).data.session;
    if (!session) { q('#login').hidden = false; q('#panel').hidden = true; return; }
    const admin = await sb.rpc('is_admin');
    if (admin.error || !admin.data) { q('#msg').textContent = 'هذا الحساب لا يملك صلاحية الإدارة.'; return; }
    q('#login').hidden = true;
    q('#panel').hidden = false;
    const {data, error} = await sb.rpc('admin_orders');
    if (error) { q('#orders').textContent = error.message; return; }
    const all = data || [];
    const shipping = shippingMode();
    q('#shipping-title').textContent = shipping ? 'الشحن والتتبع' : 'الطلبات';
    q('#shipping-note').textContent = shipping ? 'جهّز سجلات الشحنات بعد تأكيد المورد، ثم سجّل رقم التتبع الذي يصدر من Bosta.' : 'افتح تفاصيل الطلب لمتابعة العميل والمنتجات والشحن.';
    const orders = shipping ? all.filter(order => order.status !== 'cancelled') : all;
    q('#stats').innerHTML = [['كل الطلبات',all.length],['جاري التنفيذ',all.filter(order => !['delivered','cancelled'].includes(order.status)).length],['تم التسليم',all.filter(order => order.status === 'delivered').length],['Refunds',money(all.reduce((sum,order) => sum + Number(order.refund_total || 0),0))]].map(item => '<div class="stat"><small>' + item[0] + '</small><h3>' + item[1] + '</h3></div>').join('');
    q('#orders').innerHTML = orders.map(order => '<article class="card"><div class="order-head"><div><b>#' + escapeHtml(order.order_number) + '</b> <span class="tag">' + escapeHtml(labels[order.status] || order.status) + '</span><div>' + escapeHtml(order.customer_name) + ' · ' + escapeHtml(order.phone) + '</div><small class="muted">' + escapeHtml(order.customer_code) + ' · ' + money(order.total) + ' · ' + new Date(order.created_at).toLocaleString('ar-EG') + '</small></div><div class="actions"><button class="button button-light" data-detail="' + order.id + '">فتح التفاصيل والشحن</button><select data-order="' + order.id + '">' + Object.entries(labels).map(([value,label]) => '<option value="' + value + '" ' + (value === order.status ? 'selected' : '') + '>' + label + '</option>').join('') + '</select></div></div><div><small>موردين ' + Number(order.supplier_count || 0) + ' · انتظار ' + Number(order.pending_suppliers || 0) + ' · مؤكد ' + Number(order.confirmed_suppliers || 0) + '</small></div><div class="details" id="detail-' + order.id + '" hidden></div></article>').join('') || '<div class="card">لا توجد طلبات للشحن حاليًا.</div>';
    if (shipping) for (const order of orders) await detail(order.id);
  }

  q('#orders').addEventListener('click', async event => {
    const button = event.target.closest('button');
    if (!button) return;
    if (button.dataset.detail) return detail(button.dataset.detail);
    if (button.dataset.prepare) {
      button.disabled = true;
      const {error} = await sb.rpc('admin_prepare_shipments', {p_order_id:button.dataset.prepare});
      button.disabled = false;
      if (error) { alert(error.message); return; }
      return showShipments(button.dataset.prepare);
    }
    if (button.dataset.tracking) {
      const tracking = prompt('رقم تتبع Bosta');
      if (!tracking?.trim()) return;
      const feeInput = prompt('تكلفة الشحن', '0');
      if (feeInput === null) return;
      const fee = Number(feeInput);
      if (!Number.isFinite(fee) || fee < 0) { alert('أدخل تكلفة شحن صحيحة.'); return; }
      const {error} = await sb.rpc('admin_set_shipment_tracking', {p_shipment_id:button.dataset.tracking,p_tracking_number:tracking.trim(),p_shipping_fee:fee});
      if (error) alert(error.message); else await showShipments(button.dataset.orderId);
    }
  });
  q('#orders').addEventListener('change', async event => {
    const select = event.target.closest('[data-order]');
    if (!select) return;
    if (select.value === 'cancelled' && !confirm('إلغاء الطلب سيعيد المبلغ المستحق للعميل ويرجع المخزون. تأكيد؟')) return load();
    const {error} = await sb.rpc('admin_set_order_status', {p_order_id:select.dataset.order,p_status:select.value});
    if (error) alert(error.message); else await load();
  });
  q('#go').onclick = async () => {
    const {error} = await sb.auth.signInWithPassword({email:q('#email').value,password:q('#pass').value});
    q('#msg').textContent = error ? 'بيانات الدخول غير صحيحة' : '';
    if (!error) await load();
  };
  window.addEventListener('hashchange', load);
  await load();
})();
