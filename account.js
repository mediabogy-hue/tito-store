/* BLNK customer account — Supabase-backed customer hub */
(function(){
 const $=s=>document.querySelector(s), money=v=>`EGP ${Number(v||0).toLocaleString('en-US')}`;
 let sb=null, session=null;
 async function config(){const r=await fetch('/api/public-config',{cache:'no-store'});if(!r.ok)throw new Error('Customer accounts are not configured yet.');return r.json()}
 async function boot(){
  try{const c=await config();if(!c.supabaseUrl||!c.supabasePublishableKey)throw new Error('Customer accounts are not configured yet.');
   sb=window.supabase.createClient(c.supabaseUrl,c.supabasePublishableKey,{auth:{persistSession:true,autoRefreshToken:true}});
   const x=await sb.auth.getSession();session=x.data.session;render();sb.auth.onAuthStateChange((_e,s)=>{session=s;render()});
  }catch(e){$('#accountState').innerHTML='<div class="account-empty">جاري تجهيز حسابات BLNK للعملاء.</div>'}
 }
 function authView(){return `<div class="account-auth"><div><p class="eyebrow">BLNK ACCOUNT</p><h2>حسابك في BLNK</h2><p>سجّل دخولك علشان تشوف رصيدك، فواتيرك، مشترياتك وBLNK Club.</p></div><form id="loginForm"><input name="email" type="email" placeholder="البريد الإلكتروني" required><input name="password" type="password" placeholder="كلمة المرور" minlength="6" required><button class="button button-dark" type="submit">تسجيل الدخول</button><button class="button button-light" id="signupBtn" type="button">إنشاء حساب جديد</button><p id="authMsg"></p></form></div>`}
 async function dashboard(){
  const uid=session.user.id;
  const [p,i,w]=await Promise.all([
   sb.from('profiles').select('*').eq('id',uid).maybeSingle(),
   sb.from('invoices').select('*,invoice_items(*)').eq('customer_id',uid).order('created_at',{ascending:false}),
   sb.from('wallet_transactions').select('*').eq('customer_id',uid).order('created_at',{ascending:false}).limit(20)
  ]);
  const profile=p.data||{}, invoices=i.data||[], wallet=w.data||[];
  const items=invoices.flatMap(x=>x.invoice_items||[]);
  $('#accountState').innerHTML=`<div class="account-top"><div><p class="eyebrow">BLNK CLUB</p><h2>${profile.full_name||session.user.email}</h2><p class="customer-code">${profile.customer_code||'BLNK MEMBER'}</p></div><button id="logoutBtn" class="button button-light">تسجيل خروج</button></div>
  <div class="account-cards"><article><span>الرصيد</span><strong>${money(profile.balance)}</strong></article><article><span>النقاط</span><strong>${Number(profile.points||0).toLocaleString()}</strong></article><article><span>الفواتير</span><strong>${invoices.length}</strong></article><article><span>القطع المشتراة</span><strong>${items.reduce((s,x)=>s+Number(x.quantity||1),0)}</strong></article></div>
  <div class="account-grid"><section><h3>آخر الفواتير</h3>${invoices.length?invoices.slice(0,8).map(x=>`<div class="account-row"><div><b>#${x.invoice_number}</b><small>${new Date(x.created_at).toLocaleDateString('ar-EG')}</small></div><strong>${money(x.total)}</strong></div>`).join(''):'<p class="muted">لسه مفيش فواتير.</p>'}</section>
  <section><h3>مشترياتي</h3>${items.length?items.slice(0,12).map(x=>`<div class="account-row"><div><b>${x.product_name}</b><small>${[x.size,x.color].filter(Boolean).join(' / ')}</small></div><strong>×${x.quantity||1}</strong></div>`).join(''):'<p class="muted">مشترياتك هتظهر هنا بعد ربط الـPOS.</p>'}</section>
  <section><h3>حركة الرصيد</h3>${wallet.length?wallet.map(x=>`<div class="account-row"><div><b>${x.description||x.type}</b><small>${new Date(x.created_at).toLocaleDateString('ar-EG')}</small></div><strong>${Number(x.amount)>0?'+':''}${money(x.amount)}</strong></div>`).join(''):'<p class="muted">لسه مفيش حركات على الرصيد.</p>'}</section>
  <section><h3>بياناتي</h3><div class="account-profile"><p><b>الموبايل:</b> ${profile.phone||'—'}</p><p><b>المستوى:</b> ${profile.club_tier||'Member'}</p><p><b>QR / Customer ID:</b> ${profile.customer_code||'—'}</p></div></section></div>`;
  $('#logoutBtn').onclick=()=>sb.auth.signOut();
 }
 async function render(){if(!session){$('#accountState').innerHTML=authView();const form=$('#loginForm'),msg=$('#authMsg');form.onsubmit=async e=>{e.preventDefault();const d=new FormData(form);const {error}=await sb.auth.signInWithPassword({email:d.get('email'),password:d.get('password')});msg.textContent=error?'بيانات الدخول غير صحيحة.':''};$('#signupBtn').onclick=async()=>{const d=new FormData(form);if(!d.get('email')||!d.get('password')){msg.textContent='اكتب البريد وكلمة المرور الأول.';return}const {error}=await sb.auth.signUp({email:d.get('email'),password:d.get('password')});msg.textContent=error?error.message:'تم إنشاء الحساب. لو مطلوب تأكيد بريد افتح رسالة التأكيد.'};return}await dashboard()}
 document.addEventListener('DOMContentLoaded',boot);
})();