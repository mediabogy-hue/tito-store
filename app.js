const productRoot=document.getElementById('products');
const cartKey='blnk_cart_v3';
const waNumber='201062292012';
let cart=JSON.parse(localStorage.getItem(cartKey)||'[]');
let products=[];
const money=v=>`EGP ${Number(v||0).toLocaleString('en-US')}`;
const lang=()=>localStorage.getItem('blnk_lang')||'ar';
function saveCart(){localStorage.setItem(cartKey,JSON.stringify(cart));renderCart()}
function productImage(p){return p.image?`<img src="${p.image}" alt="${p.name||'BLNK'}" loading="lazy" onerror="this.style.display='none';this.parentElement.classList.add('image-fallback')">`:`<div class="product-placeholder"><span>BLNK</span><small>NO NOISE, JUST STYLE.</small></div>`}
function renderProducts(filter='all'){
 const list=filter==='all'?products:products.filter(p=>filter==='last'?(p.lastPieces===true||p.category==='last'):p.category===filter);
 if(!list.length){productRoot.innerHTML=`<div class="empty-cart" style="grid-column:1/-1">${lang()==='ar'?'مفيش منتجات متاحة دلوقتي.':'No products available right now.'}</div>`;return}
 productRoot.innerHTML=list.map(p=>`<article class="product" data-product-id="${p.id}">
  <button class="product-image product-open" data-id="${p.id}" type="button" aria-label="${p.name}">${productImage(p)}</button>
  <div class="product-info"><div class="product-name">${p.name}</div><div class="product-meta">${p.note||''}</div><div class="product-price">${money(p.price)}</div>
  <div class="product-card-actions"><button class="button button-dark product-open" data-id="${p.id}" type="button">${lang()==='ar'?'اختار المقاس واللون ←':'Choose size & color →'}</button></div></div></article>`).join('');
 if(window.setLanguage)window.setLanguage(lang());
}
function openProduct(id){
 const p=products.find(x=>String(x.id)===String(id));if(!p)return;
 const sizes=Array.isArray(p.sizes)&&p.sizes.length?p.sizes:['One Size'];
 const colors=Array.isArray(p.colors)&&p.colors.length?p.colors:['Default'];
 const stock=Number(p.stock||0);
 document.getElementById('productModalContent').innerHTML=`<div class="product-detail-grid"><div class="detail-image">${productImage(p)}</div><div class="detail-copy"><p class="eyebrow">BLNK / ${lang()==='ar'?'المنتج':'PRODUCT'}</p><h2>${p.name}</h2><p class="detail-note">${p.note||''}</p><div class="detail-price">${money(p.price)}</div>${stock===1?`<p class="stock-note">${lang()==='ar'?'آخر قطعة متاحة':'Last piece available'}</p>`:''}<label class="choice-label">${lang()==='ar'?'المقاس':'SIZE'}<select id="detailSize">${sizes.map(s=>`<option value="${s}">${s}</option>`).join('')}</select></label><label class="choice-label">${lang()==='ar'?'اللون':'COLOR'}<select id="detailColor">${colors.map(c=>`<option value="${c}">${c}</option>`).join('')}</select></label><label class="choice-label">${lang()==='ar'?'الكمية':'QUANTITY'}<div class="qty"><button type="button" id="qtyMinus">−</button><input id="detailQty" value="1" min="1" max="99" type="number"><button type="button" id="qtyPlus">+</button></div></label><button class="button button-dark full-button" id="addToCart" type="button">${lang()==='ar'?'أضف للسلة':'ADD TO BAG'}</button><button class="button button-light full-button" id="buyNow" type="button">${lang()==='ar'?'اطلب دلوقتي':'BUY NOW'}</button></div></div>`;
 const modal=document.getElementById('productModal');modal.classList.add('open');modal.setAttribute('aria-hidden','false');
 const qty=document.getElementById('detailQty');
 document.getElementById('qtyMinus').onclick=()=>qty.value=Math.max(1,Number(qty.value||1)-1);
 document.getElementById('qtyPlus').onclick=()=>qty.value=Math.min(99,Number(qty.value||1)+1);
 const selected=()=>({id:p.id,size:document.getElementById('detailSize').value,color:document.getElementById('detailColor').value,qty:Math.max(1,Number(qty.value||1))});
 document.getElementById('addToCart').onclick=()=>{addToCart(selected());closeOverlay('productModal');openCart()};
 document.getElementById('buyNow').onclick=()=>{addToCart(selected());closeOverlay('productModal');openCart();setTimeout(checkout,150)};
}
function addToCart(item){const e=cart.find(x=>String(x.id)===String(item.id)&&x.size===item.size&&x.color===item.color);if(e)e.qty+=item.qty;else cart.push(item);saveCart()}
function renderCart(){
 const root=document.getElementById('cartItems');
 const count=cart.reduce((s,i)=>s+i.qty,0);document.getElementById('cartCount').textContent=count;
 if(!cart.length){root.innerHTML=`<div class="empty-cart">${lang()==='ar'?'السلة فاضية. اختار منتج من المتجر.':'Your bag is empty. Choose a product.'}</div>`;document.getElementById('cartTotal').textContent=money(0);return}
 root.innerHTML=cart.map((item,i)=>{const p=products.find(x=>String(x.id)===String(item.id));if(!p)return '';return `<div class="cart-item"><div class="cart-item-image">${productImage(p)}</div><div class="cart-item-copy"><strong>${p.name}</strong><span>${item.size} / ${item.color}</span><span>${money(p.price)} × ${item.qty}</span><div class="cart-actions"><button type="button" data-cart-minus="${i}">−</button><b>${item.qty}</b><button type="button" data-cart-plus="${i}">+</button><button type="button" class="remove-item" data-cart-remove="${i}">${lang()==='ar'?'حذف':'Remove'}</button></div></div></div>`}).join('');
 const total=cart.reduce((s,i)=>{const p=products.find(x=>String(x.id)===String(i.id));return s+(p?Number(p.price)*i.qty:0)},0);document.getElementById('cartTotal').textContent=money(total);
 root.querySelectorAll('[data-cart-minus]').forEach(b=>b.onclick=()=>changeQty(+b.dataset.cartMinus,-1));root.querySelectorAll('[data-cart-plus]').forEach(b=>b.onclick=()=>changeQty(+b.dataset.cartPlus,1));root.querySelectorAll('[data-cart-remove]').forEach(b=>b.onclick=()=>{cart.splice(+b.dataset.cartRemove,1);saveCart()});
}
function changeQty(i,d){if(!cart[i])return;cart[i].qty+=d;if(cart[i].qty<=0)cart.splice(i,1);saveCart()}
function openCart(){renderCart();document.getElementById('cartDrawer').classList.add('open');document.getElementById('drawerBackdrop').classList.add('open');document.getElementById('cartDrawer').setAttribute('aria-hidden','false')}
function closeOverlay(id){const e=document.getElementById(id);if(!e)return;e.classList.remove('open');e.setAttribute('aria-hidden','true');if(id==='cartDrawer')document.getElementById('drawerBackdrop').classList.remove('open')}
function checkout(){
 if(!cart.length){alert(lang()==='ar'?'السلة فاضية.':'Your bag is empty.');return}
 const lines=cart.map((i,n)=>{const p=products.find(x=>String(x.id)===String(i.id));return `${n+1}. ${p.name} | ${lang()==='ar'?'المقاس':'Size'}: ${i.size} | ${lang()==='ar'?'اللون':'Color'}: ${i.color} | ${lang()==='ar'?'الكمية':'Qty'}: ${i.qty} | ${money(Number(p.price)*i.qty)}`});
 const total=cart.reduce((s,i)=>{const p=products.find(x=>String(x.id)===String(i.id));return s+(p?Number(p.price)*i.qty:0)},0);
 const text=lang()==='ar'?`يا BLNK، عايز أعمل طلب.\n\n${lines.join('\n')}\n\nالإجمالي: ${money(total)}\n\nالاسم:\nالعنوان:\nرقم الموبايل:`:`Hi BLNK, I want to place an order.\n\n${lines.join('\n')}\n\nTotal: ${money(total)}\n\nName:\nAddress:\nMobile:`;
 window.open(`https://wa.me/${waNumber}?text=${encodeURIComponent(text)}`,'_blank');
}
document.addEventListener('click',e=>{const p=e.target.closest('.product-open');if(p){e.preventDefault();openProduct(p.dataset.id);return}const c=e.target.closest('[data-close]');if(c)closeOverlay(c.dataset.close)});
document.getElementById('cartButton').onclick=openCart;
document.getElementById('clearCart').onclick=()=>{cart=[];saveCart()};
document.getElementById('checkoutButton').onclick=checkout;
document.getElementById('shopWhatsapp').onclick=()=>window.open(`https://wa.me/${waNumber}?text=${encodeURIComponent(lang()==='ar'?'يا BLNK، عايز أشوف المجموعة المتاحة.':'Hi BLNK, I want to see the available collection.')}`,'_blank');
document.querySelectorAll('.filter').forEach(b=>b.onclick=()=>{document.querySelectorAll('.filter').forEach(x=>x.classList.remove('active'));b.classList.add('active');renderProducts(b.dataset.filter)});
const form=document.getElementById('styleForm');const status=document.getElementById('formStatus');form.onsubmit=e=>{e.preventDefault();const d=new FormData(form);window.open(`https://wa.me/${waNumber}?text=${encodeURIComponent(`BLNK Style Profile\nالاسم: ${d.get('name')}\nواتساب: ${d.get('phone')}\nالقَصّة: ${d.get('fit')}\nالستايل: ${d.get('style')}\nالمقاس: ${d.get('size')}\nالناقص في الدولاب: ${d.get('gap')}`)}`,'_blank');status.textContent=lang()==='ar'?'تمام، فتحنا واتساب عشان نكمل معاك.':'Done — WhatsApp is open.'};
document.getElementById('year').textContent=new Date().getFullYear();
async function fetchCatalog(url){try{const r=await fetch(url,{cache:'no-store'});if(!r.ok)return null;const data=await r.json();return Array.isArray(data)?data:null}catch(e){return null}}
async function initProducts(){
 let live=await fetchCatalog('https://raw.githubusercontent.com/mediabogy-hue/tito-store/main/products.json?v='+Date.now());
 if(!live)live=await fetchCatalog('/api/products?v='+Date.now());
 if(live&&live.length)products=live.filter(p=>p.active!==false);
 else if(Array.isArray(window.BLNK_PRODUCTS))products=window.BLNK_PRODUCTS.filter(p=>p.active!==false);
 localStorage.setItem('blnk_products_v1',JSON.stringify(products));
 renderProducts();renderCart();if(window.initLanguage)window.initLanguage();
}
initProducts();
setInterval(async()=>{const live=await fetchCatalog('https://raw.githubusercontent.com/mediabogy-hue/tito-store/main/products.json?v='+Date.now());if(live&&live.length){products=live.filter(p=>p.active!==false);renderProducts();renderCart()}},60000);
