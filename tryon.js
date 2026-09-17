// BLNK "See it on you" client-side visual try-on helper.
(function(){
  const state={userUrl:'', productUrl:'', scale:1, x:0, y:0};
  function esc(s){return String(s||'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
  function openTryOn(product){
    state.productUrl=product.image||product.imageUrl||product.img||'';
    state.scale=1; state.x=0; state.y=0;
    let el=document.getElementById('blnkTryOn');
    if(!el){el=document.createElement('div');el.id='blnkTryOn';el.innerHTML=`<div class="blnk-to-back"></div><div class="blnk-to-modal"><button class="blnk-to-close">×</button><h2>شوف المنتج عليك</h2><p class="blnk-to-hint">ارفع صورتك، وبعدها حرّك المنتج وكبّره أو صغّره عشان تشوفه عليك.</p><label class="blnk-to-upload">ارفع صورتك<input id="blnkToFile" type="file" accept="image/*"></label><div class="blnk-to-stage" id="blnkToStage"><div class="blnk-to-empty">ارفع صورتك للبدء</div></div><div class="blnk-to-controls"><button id="blnkToMinus">−</button><button id="blnkToPlus">+</button><button id="blnkToReset">إعادة ضبط</button></div><div class="blnk-to-actions"><button id="blnkToSave">حفظ الصورة</button><button id="blnkToCart">أضف للحقيبة</button></div></div>`;document.body.appendChild(el);}
    el.style.display='flex';
    const stage=el.querySelector('#blnkToStage'); stage.innerHTML='<div class="blnk-to-empty">ارفع صورتك للبدء</div>';
    el.querySelector('.blnk-to-close').onclick=()=>el.style.display='none';
    el.querySelector('.blnk-to-back').onclick=()=>el.style.display='none';
    el.querySelector('#blnkToFile').onchange=e=>{const f=e.target.files&&e.target.files[0];if(!f)return;const r=new FileReader();r.onload=()=>{state.userUrl=r.result;render(stage);};r.readAsDataURL(f);};
    el.querySelector('#blnkToPlus').onclick=()=>{state.scale=Math.min(2,state.scale+.1);render(stage)};
    el.querySelector('#blnkToMinus').onclick=()=>{state.scale=Math.max(.5,state.scale-.1);render(stage)};
    el.querySelector('#blnkToReset').onclick=()=>{state.scale=1;state.x=0;state.y=0;render(stage)};
    el.querySelector('#blnkToSave').onclick=()=>save(stage,product.name||'BLNK product');
    el.querySelector('#blnkToCart').onclick=()=>{if(window.addToCart) window.addToCart(product); else if(window.openProduct) window.openProduct(product);};
    function render(s){if(!state.userUrl){s.innerHTML='<div class="blnk-to-empty">ارفع صورتك للبدء</div>';return;}s.innerHTML=`<img class="blnk-to-user" src="${state.userUrl}"><img class="blnk-to-product" src="${state.productUrl}" style="transform:translate(${state.x}px,${state.y}px) scale(${state.scale})">`;const p=s.querySelector('.blnk-to-product');let sx=0,sy=0,ox=0,oy=0,drag=false;p.onpointerdown=e=>{drag=true;sx=e.clientX;sy=e.clientY;ox=state.x;oy=state.y;p.setPointerCapture(e.pointerId)};p.onpointermove=e=>{if(!drag)return;state.x=ox+e.clientX-sx;state.y=oy+e.clientY-sy;p.style.transform=`translate(${state.x}px,${state.y}px) scale(${state.scale})`};p.onpointerup=()=>drag=false;}
    function save(s,name){if(!state.userUrl||!state.productUrl)return;const c=document.createElement('canvas'),w=900,h=1200;c.width=w;c.height=h;const x=c.getContext('2d'),u=new Image(),p=new Image();u.onload=()=>p.onload=()=>{x.drawImage(u,0,0,w,h);const pw=w*.62*state.scale,ph=pw*(p.naturalHeight/p.naturalWidth);x.drawImage(p,(w-pw)/2+state.x,(h-ph)/2+state.y,pw,ph);const a=document.createElement('a');a.download='BLNK-try-on.png';a.href=c.toDataURL('image/png');a.click()};u.src=state.userUrl;p.src=state.productUrl;}
  }
  window.BLNKTryOn=openTryOn;
  window.BLNKInstallTryOn=function(){document.querySelectorAll('[data-tryon]').forEach(b=>{if(b.dataset.tryonBound)return;b.dataset.tryonBound='1';b.addEventListener('click',()=>{try{const product=JSON.parse(b.getAttribute('data-tryon'));openTryOn(product)}catch(e){console.error(e)}})})};
})();
