const BLNK_ADMIN_WA='201062292012';
const BLNK_API_PHONE=p=>{let x=String(p||'').replace(/\D/g,'');if(x.startsWith('00'))x=x.slice(2);if(x.startsWith('0'))x='20'+x.slice(1);if(!x.startsWith('20'))x='20'+x;return x};
const BLNK_QR=code=>`https://api.qrserver.com/v1/create-qr-code/?size=320x320&data=${encodeURIComponent(code)}`;
const BLNK_PROFILE_FORM=document.getElementById('styleForm');
if(BLNK_PROFILE_FORM){BLNK_PROFILE_FORM.onsubmit=async e=>{e.preventDefault();const d=new FormData(BLNK_PROFILE_FORM),status=document.getElementById('formStatus'),result=document.getElementById('profileResult');status.textContent='جاري إنشاء ملفك...';try{const profile=Object.fromEntries(d.entries());const r=await fetch('/api/customer',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:profile.name,phone:profile.phone,profile})});const customer=await r.json();if(!r.ok)throw Error(customer.error||'تعذر إنشاء الملف');const qr=BLNK_QR(customer.customerId);const adminText=`BLNK CUSTOMER PROFILE\nCustomer ID: ${customer.customerId}\nالاسم: ${customer.name}\nواتساب: ${customer.phone}\n\nProfile:\n${Object.entries(profile).map(([k,v])=>`${k}: ${v}`).join('\n')}\n\nQR: ${qr}`;const customerText=`أهلاً بيك في BLNK 👋\nCustomer ID: ${customer.customerId}\nده الـQR الخاص بملفك:\n${qr}\nاحتفظ بيه عشان نستخدمه في ترشيحاتك وطلباتك.`;result.hidden=false;result.innerHTML=`<div class="customer-code">Customer ID: ${customer.customerId}</div><img src="${qr}" alt="BLNK Customer QR"><p class="hint">الـQR ده مميز للعميل ده.</p><div class="profile-actions"><a class="button button-dark" target="_blank" rel="noreferrer" href="https://wa.me/${BLNK_ADMIN_WA}?text=${encodeURIComponent(adminText)}">ابعت الملف لـ BLNK</a><a class="button button-light" target="_blank" rel="noreferrer" href="https://wa.me/${BLNK_API_PHONE(customer.phone)}?text=${encodeURIComponent(customerText)}">ابعت الـQR لنفسي</a></div>`;status.textContent='تم إنشاء ملفك بنجاح. احتفظ بالـCustomer ID والـQR.';result.scrollIntoView({behavior:'smooth',block:'center'});}catch(err){status.textContent=err.message||'حصل خطأ، حاول تاني.';}}}

/* BLNK — شوف المنتج عليك: client-side virtual preview */
(function(){
 const css=`.blnk-tryon-btn{margin-top:10px}.blnk-tryon-overlay{position:fixed;inset:0;z-index:9999;background:rgba(0,0,0,.72);display:flex;align-items:center;justify-content:center;padding:16px}.blnk-tryon-card{background:#fff;color:#111;width:min(760px,100%);max-height:92vh;overflow:auto;border-radius:22px;padding:20px;position:relative}.blnk-tryon-close{position:absolute;right:14px;top:10px;border:0;background:#111;color:#fff;border-radius:50%;width:36px;height:36px;font-size:24px}.blnk-tryon-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}.blnk-tryon-preview{background:#f3f3f3;border-radius:18px;min-height:340px;display:flex;align-items:center;justify-content:center;overflow:hidden}.blnk-tryon-preview canvas{max-width:100%;height:auto}.blnk-tryon-controls{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.blnk-tryon-controls label{display:flex;flex-direction:column;gap:5px;font-size:13px}.blnk-tryon-controls input[type=range]{width:150px}@media(max-width:700px){.blnk-tryon-grid{grid-template-columns:1fr}.blnk-tryon-preview{min-height:280px}}
 .blnk-tryon-note{font-size:12px;opacity:.65;margin-top:8px}`;
 const st=document.createElement('style');st.textContent=css;document.head.appendChild(st);
 let currentProduct=null;
 function injectButton(){
   const copy=document.querySelector('#productModalContent .detail-copy');
   if(!copy||copy.querySelector('.blnk-tryon-btn'))return;
   const btn=document.createElement('button');btn.type='button';btn.className='button button-light full-button blnk-tryon-btn';btn.textContent='👕 شوف المنتج عليك';
   btn.onclick=()=>openTryOn();
   const buy=copy.querySelector('#buyNow');
   if(buy)buy.insertAdjacentElement('afterend',btn);else copy.appendChild(btn);
 }
 function getProduct(){
   const id=document.querySelector('#productModalContent #addToCart')?.closest('.detail-copy')?.querySelector('h2')?.textContent;
   return (window.products||[]).find(p=>p.name===id)||null;
 }
 function openTryOn(){
   currentProduct=getProduct();
   const image=currentProduct?.image||document.querySelector('#productModalContent .detail-image img')?.src;
   if(!image){alert('صورة المنتج مش متاحة للتجربة دلوقتي.');return}
   const old=document.getElementById('blnkTryOn');if(old)old.remove();
   const el=document.createElement('div');el.id='blnkTryOn';el.className='blnk-tryon-overlay';el.innerHTML=`<div class="blnk-tryon-card"><button class="blnk-tryon-close" type="button">×</button><p class="eyebrow">BLNK / TRY ON</p><h2>شوف المنتج عليك</h2><p>ارفع صورتك وشوف معاينة للمنتج. الصورة تفضل على جهازك أثناء المعاينة.</p><div class="blnk-tryon-grid"><div><input id="blnkTryOnFile" type="file" accept="image/*"><div class="blnk-tryon-controls"><label>حجم المنتج<input id="blnkTryScale" type="range" min="15" max="90" value="45"></label><label>مكان المنتج<input id="blnkTryY" type="range" min="10" max="90" value="42"></label></div><p class="blnk-tryon-note">المعاينة الحالية تركيب بصري للصورة، وليست قياسًا دقيقًا للمقاس أو محاكاة جسم بالذكاء الاصطناعي.</p></div><div class="blnk-tryon-preview"><canvas id="blnkTryCanvas"></canvas></div></div><div class="blnk-tryon-controls"><button id="blnkTryDownload" class="button button-dark" type="button">حفظ النتيجة</button><button id="blnkTryCart" class="button button-light" type="button">أضف للحقيبة</button></div></div>`;
   document.body.appendChild(el);el.querySelector('.blnk-tryon-close').onclick=()=>el.remove();
   const file=el.querySelector('#blnkTryOnFile'),scale=el.querySelector('#blnkTryScale'),pos=el.querySelector('#blnkTryY'),canvas=el.querySelector('#blnkTryCanvas'),ctx=canvas.getContext('2d');
   const user=new Image(),prod=new Image();prod.crossOrigin='anonymous';prod.src=image;
   let readyUser=false,readyProd=false;
   function draw(){if(!readyUser||!readyProd)return;const max=900,ratio=Math.min(max/user.naturalWidth,max/user.naturalHeight);canvas.width=Math.round(user.naturalWidth*ratio);canvas.height=Math.round(user.naturalHeight*ratio);ctx.clearRect(0,0,canvas.width,canvas.height);ctx.drawImage(user,0,0,canvas.width,canvas.height);const w=canvas.width*(Number(scale.value)/100);const h=w*(prod.naturalHeight/prod.naturalWidth);const y=canvas.height*(Number(pos.value)/100)-h*.5;ctx.globalAlpha=.93;ctx.drawImage(prod,(canvas.width-w)/2,y,w,h);ctx.globalAlpha=1}
   file.onchange=()=>{const f=file.files?.[0];if(!f)return;user.onload=()=>{readyUser=true;draw()};user.src=URL.createObjectURL(f)};prod.onload=()=>{readyProd=true;draw()};scale.oninput=draw;pos.oninput=draw;
   el.querySelector('#blnkTryDownload').onclick=()=>{if(!readyUser){alert('ارفع صورتك الأول.');return}const a=document.createElement('a');a.download='BLNK-try-on.png';a.href=canvas.toDataURL('image/png');a.click()};
   el.querySelector('#blnkTryCart').onclick=()=>{const add=document.querySelector('#productModalContent #addToCart');if(add){add.click();el.remove()}else alert('اختار المنتج من صفحة المنتج الأول.')};
 }
 const observer=new MutationObserver(injectButton);observer.observe(document.body,{subtree:true,childList:true});setInterval(injectButton,500);
})();
