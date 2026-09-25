(() => {
  const AR = () => (localStorage.getItem('blnk_lang') || 'ar') === 'ar';

  function styles() {
    if (document.getElementById('blnk-ai-tryon-style')) return;
    const s = document.createElement('style');
    s.id = 'blnk-ai-tryon-style';
    s.textContent = `
      .blnk-ai-tryon{position:fixed;inset:0;z-index:10050;display:none;align-items:center;justify-content:center;padding:18px;background:rgba(0,0,0,.72)}
      .blnk-ai-tryon.open{display:flex}.blnk-ai-card{width:min(560px,100%);max-height:92vh;overflow:auto;background:#fff;color:#111;border-radius:24px;padding:20px;box-shadow:0 24px 80px rgba(0,0,0,.35);direction:rtl}
      .blnk-ai-head{display:flex;align-items:center;justify-content:space-between;gap:12px}.blnk-ai-head h3{margin:0;font-size:22px}.blnk-ai-close{border:0;background:#111;color:#fff;width:38px;height:38px;border-radius:50%;font-size:24px;cursor:pointer}
      .blnk-ai-preview{margin:16px 0;border:1px dashed #bbb;border-radius:18px;min-height:180px;display:flex;align-items:center;justify-content:center;overflow:hidden;background:#f5f5f5}.blnk-ai-preview img{max-width:100%;max-height:55vh;display:block}
      .blnk-ai-upload{display:block;border:1px solid #111;border-radius:14px;padding:14px;text-align:center;cursor:pointer;margin:12px 0}.blnk-ai-upload input{display:none}
      .blnk-ai-actions{display:flex;gap:10px;flex-wrap:wrap}.blnk-ai-actions button,.blnk-ai-actions a{flex:1;min-width:150px;text-align:center}
      .blnk-ai-status{text-align:center;font-size:14px;margin:12px 0;min-height:20px}.blnk-ai-note{font-size:12px;opacity:.65;line-height:1.6}
      .blnk-ai-result{display:none}.blnk-ai-result.show{display:block}.blnk-ai-loading{display:none;text-align:center;padding:22px}.blnk-ai-loading.show{display:block}
    `;
    document.head.appendChild(s);
  }

  function ensureModal() {
    styles();
    let el = document.getElementById('blnkAiTryOn');
    if (el) return el;
    el = document.createElement('div');
    el.id = 'blnkAiTryOn';
    el.className = 'blnk-ai-tryon';
    el.innerHTML = `<div class="blnk-ai-card">
      <div class="blnk-ai-head"><h3>👕 ${AR() ? 'جرب المنتج' : 'TRY IT ON'}</h3><button class="blnk-ai-close" type="button">×</button></div>
      <p>${AR() ? 'ارفع صورتك، والـAI هيحط المنتج عليك.' : 'Upload your photo and AI will place the product on you.'}</p>
      <label class="blnk-ai-upload">📷 ${AR() ? 'اختار صورتك' : 'Choose your photo'}<input id="blnkAiPhoto" type="file" accept="image/*"></label>
      <div class="blnk-ai-preview" id="blnkAiPreview"><span>${AR() ? 'الصورة هتظهر هنا' : 'Your photo will appear here'}</span></div>
      <div class="blnk-ai-actions"><button class="button button-dark" id="blnkAiRun" type="button" disabled>${AR() ? 'جرب المنتج' : 'TRY IT ON'}</button></div>
      <div class="blnk-ai-status" id="blnkAiStatus"></div>
      <div class="blnk-ai-loading" id="blnkAiLoading">⏳ ${AR() ? 'الـAI بيجهز الصورة…' : 'AI is generating your look…'}</div>
      <div class="blnk-ai-result" id="blnkAiResult"><div class="blnk-ai-preview"><img id="blnkAiResultImg" alt="BLNK AI try-on result"></div><div class="blnk-ai-actions"><a class="button button-dark" id="blnkAiSave" download="blnk-ai-tryon.jpg">${AR() ? 'احفظ الصورة عندك' : 'SAVE TO YOUR DEVICE'}</a><button class="button button-light" id="blnkAiAgain" type="button">${AR() ? 'جرّب صورة تانية' : 'TRY ANOTHER PHOTO'}</button></div><p class="blnk-ai-note">${AR() ? 'الصورة الشخصية والنتيجة مش بيتحفظوا في بروفايل BLNK أو قاعدة بيانات العملاء. النتيجة بتفضل عندك لو حفظتها.' : 'Your photo and result are not saved to your BLNK customer profile or customer database.'}</p></div>
    </div>`;
    document.body.appendChild(el);
    el.querySelector('.blnk-ai-close').onclick = () => close();
    el.addEventListener('click', e => { if (e.target === el) close(); });
    return el;
  }

  let currentProduct = null;
  let photoData = null;
  let objectUrl = null;

  function close() {
    const el = document.getElementById('blnkAiTryOn');
    if (el) el.classList.remove('open');
    if (objectUrl) { URL.revokeObjectURL(objectUrl); objectUrl = null; }
    photoData = null;
  }

  function fileToDataUrl(file) {
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(r.result);
      r.onerror = reject;
      r.readAsDataURL(file);
    });
  }

  async function poll(id) {
    for (let i = 0; i < 90; i++) {
      await new Promise(r => setTimeout(r, 2000));
      const r = await fetch(`/api/tryon-status?id=${encodeURIComponent(id)}`, { cache: 'no-store' });
      const d = await r.json();
      if (!r.ok) throw new Error(d.error || 'Status request failed');
      if (d.status === 'completed' || d.output) return d.output;
      if (d.status === 'failed' || d.status === 'canceled') throw new Error(d.error || 'AI generation failed');
    }
    throw new Error(AR() ? 'الطلب أخد وقت أطول من المتوقع. جرّب تاني.' : 'The request took too long. Please try again.');
  }

  function firstOutput(output) {
    if (Array.isArray(output)) return output[0];
    return output;
  }

  async function run() {
    const el = ensureModal();
    const status = el.querySelector('#blnkAiStatus');
    const loading = el.querySelector('#blnkAiLoading');
    const result = el.querySelector('#blnkAiResult');
    const resultImg = el.querySelector('#blnkAiResultImg');
    const save = el.querySelector('#blnkAiSave');
    if (!photoData || !currentProduct?.image) return;
    loading.classList.add('show'); result.classList.remove('show'); status.textContent = '';
    let walletTxn = null;
    el.querySelector('#blnkAiRun').disabled = true;
    try {
      if(!window.BLNKAccount?.getSession?.()) throw new Error(AR() ? 'سجّل دخولك في حساب BLNK الأول علشان تستخدم جرب المنتج.' : 'Sign in to your BLNK account first.');
      try {
        walletTxn = await window.BLNKAccount.reserveTryOn(currentProduct.id);
      } catch(e) {
        const m=String(e?.message||'');
        if(m.includes('INSUFFICIENT_BALANCE')) throw new Error(AR() ? 'رصيد BLNK غير كافٍ لتجربة المنتج.' : 'Your BLNK balance is not enough for Try It On.');
        if(m.includes('AUTH_REQUIRED')) throw new Error(AR() ? 'سجّل دخولك الأول.' : 'Please sign in first.');
        throw e;
      }
      status.textContent = AR() ? `تم حجز ${walletTxn?.charge||0} جنيه من رصيدك للتجربة.` : `EGP ${walletTxn?.charge||0} reserved for this try-on.`;
      const r = await fetch('/api/tryon', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({ model_image: photoData, product_image: currentProduct.image, product_name: currentProduct.name || 'BLNK garment' }) });
      const d = await r.json();
      if (!r.ok) throw new Error(d.error || 'Could not generate AI try-on');
      const output = firstOutput(d.output);
      if (!output) throw new Error('No image returned');
      if(walletTxn?.transaction_id) await window.BLNKAccount.completeTryOn(walletTxn.transaction_id);
      resultImg.src = output;
      save.href = output;
      result.classList.add('show');
      status.textContent = AR() ? 'تم! دي النتيجة بتاعتك.' : 'Done! Here is your result.';
    } catch (e) {
      if(walletTxn?.transaction_id){try{await window.BLNKAccount.refundTryOn(walletTxn.transaction_id)}catch(_e){}}
      status.textContent = e.message || (AR() ? 'حصل خطأ، جرّب تاني.' : 'Something went wrong.');
    } finally {
      loading.classList.remove('show');
      el.querySelector('#blnkAiRun').disabled = !photoData;
    }
  }

  function open(product) {
    currentProduct = product;
    const el = ensureModal();
    const input = el.querySelector('#blnkAiPhoto');
    const preview = el.querySelector('#blnkAiPreview');
    const runBtn = el.querySelector('#blnkAiRun');
    const result = el.querySelector('#blnkAiResult');
    result.classList.remove('show');
    input.value = '';
    preview.innerHTML = `<span>${AR() ? 'الصورة هتظهر هنا' : 'Your photo will appear here'}</span>`;
    runBtn.disabled = true;
    el.classList.add('open');
    input.onchange = async () => {
      const file = input.files?.[0]; if (!file) return;
      if (!file.type.startsWith('image/')) return;
      if (file.size > 12 * 1024 * 1024) { alert(AR() ? 'الصورة لازم تكون أقل من 12MB.' : 'Please use an image under 12MB.'); return; }
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      objectUrl = URL.createObjectURL(file);
      preview.innerHTML = `<img src="${objectUrl}" alt="Your photo">`;
      photoData = await fileToDataUrl(file);
      runBtn.disabled = false;
    };
    runBtn.onclick = run;
    el.querySelector('#blnkAiAgain').onclick = () => input.click();
  }

  window.openTryOn = open;
  window.closeTryOn = close;
})();
