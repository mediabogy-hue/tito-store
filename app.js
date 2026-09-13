const productRoot = document.getElementById('products');
const cartKey = 'blnk_cart_v1';
let cart = JSON.parse(localStorage.getItem(cartKey) || '[]');
let products = Array.isArray(window.BLNK_PRODUCTS) ? window.BLNK_PRODUCTS : [];

const money = value => `EGP ${Number(value).toLocaleString()}`;
const waNumber = '201062292012';

function saveCart(){
  localStorage.setItem(cartKey, JSON.stringify(cart));
  renderCart();
}

function productImage(p){
  return p.image
    ? `<img src="${p.image}" alt="${p.name}" loading="lazy" />`
    : `<div class="product-placeholder"><span>BLNK</span><small>NO NOISE, JUST STYLE.</small></div>`;
}

function renderProducts(filter='all'){
  const list = filter === 'all' ? products : products.filter(p => p.category === filter);
  productRoot.innerHTML = list.map(p => `
    <article class="product">
      <button class="product-image product-open" data-id="${p.id}" type="button" aria-label="View ${p.name}">${productImage(p)}</button>
      <div class="product-info">
        <div class="product-name">${p.name}</div>
        <div class="product-meta">${p.note || ''}</div>
        <div class="product-price">${money(p.price)}</div>
        <button class="text-link product-open product-link-button" data-id="${p.id}" type="button">View product →</button>
      </div>
    </article>`).join('');
}

function openProduct(id){
  const p = products.find(item => item.id === id);
  if(!p) return;
  const sizes = p.sizes?.length ? p.sizes : ['One Size'];
  const colors = p.colors?.length ? p.colors : ['Default'];
  document.getElementById('productModalContent').innerHTML = `
    <div class="product-detail-grid">
      <div class="detail-image">${productImage(p)}</div>
      <div class="detail-copy">
        <p class="eyebrow">BLNK / PRODUCT</p>
        <h2 id="modalProductName">${p.name}</h2>
        <p class="detail-note">${p.note || ''}</p>
        <div class="detail-price">${money(p.price)}</div>
        <label class="choice-label">Size<select id="detailSize">${sizes.map(s=>`<option>${s}</option>`).join('')}</select></label>
        <label class="choice-label">Color<select id="detailColor">${colors.map(c=>`<option>${c}</option>`).join('')}</select></label>
        <label class="choice-label">Quantity<div class="qty"><button type="button" id="qtyMinus">−</button><input id="detailQty" value="1" min="1" type="number" /><button type="button" id="qtyPlus">+</button></div></label>
        <button class="button button-dark full-button" id="addToCart" type="button">Add to bag</button>
      </div>
    </div>`;
  const modal = document.getElementById('productModal');
  modal.classList.add('open'); modal.setAttribute('aria-hidden','false');
  const qty = document.getElementById('detailQty');
  document.getElementById('qtyMinus').onclick = () => qty.value = Math.max(1, Number(qty.value)-1);
  document.getElementById('qtyPlus').onclick = () => qty.value = Number(qty.value)+1;
  document.getElementById('addToCart').onclick = () => {
    addToCart({id:p.id, size:document.getElementById('detailSize').value, color:document.getElementById('detailColor').value, qty:Math.max(1, Number(qty.value))});
    closeOverlay('productModal');
    openCart();
  };
}

function addToCart(item){
  const existing = cart.find(x => x.id === item.id && x.size === item.size && x.color === item.color);
  if(existing) existing.qty += item.qty;
  else cart.push(item);
  saveCart();
}

function renderCart(){
  const root = document.getElementById('cartItems');
  const count = cart.reduce((sum,item)=>sum+item.qty,0);
  document.getElementById('cartCount').textContent = count;
  if(!cart.length){
    root.innerHTML = '<div class="empty-cart">Your bag is empty.<br />Choose something from the collection.</div>';
  } else {
    root.innerHTML = cart.map((item,index)=>{
      const p = products.find(x=>x.id===item.id);
      if(!p) return '';
      return `<div class="cart-item">
        <div class="cart-item-image">${productImage(p)}</div>
        <div class="cart-item-copy"><strong>${p.name}</strong><span>${item.size} / ${item.color}</span><span>${money(p.price)} × ${item.qty}</span>
          <div class="cart-actions"><button type="button" data-cart-minus="${index}">−</button><b>${item.qty}</b><button type="button" data-cart-plus="${index}">+</button><button class="remove-item" type="button" data-cart-remove="${index}">Remove</button></div>
        </div>
      </div>`;
    }).join('');
  }
  const total = cart.reduce((sum,item)=>{const p=products.find(x=>x.id===item.id); return sum+(p?p.price*item.qty:0)},0);
  document.getElementById('cartTotal').textContent = money(total);
  root.querySelectorAll('[data-cart-minus]').forEach(btn=>btn.onclick=()=>changeQty(Number(btn.dataset.cartMinus),-1));
  root.querySelectorAll('[data-cart-plus]').forEach(btn=>btn.onclick=()=>changeQty(Number(btn.dataset.cartPlus),1));
  root.querySelectorAll('[data-cart-remove]').forEach(btn=>btn.onclick=()=>{cart.splice(Number(btn.dataset.cartRemove),1);saveCart()});
}

function changeQty(index, delta){
  if(!cart[index]) return;
  cart[index].qty += delta;
  if(cart[index].qty <= 0) cart.splice(index,1);
  saveCart();
}

function openCart(){
  document.getElementById('cartDrawer').classList.add('open');
  document.getElementById('drawerBackdrop').classList.add('open');
  document.getElementById('cartDrawer').setAttribute('aria-hidden','false');
}

function closeOverlay(id){
  const el=document.getElementById(id); if(!el) return;
  el.classList.remove('open'); el.setAttribute('aria-hidden','true');
  if(id==='cartDrawer') document.getElementById('drawerBackdrop').classList.remove('open');
}

document.addEventListener('click', e=>{
  const opener=e.target.closest('.product-open');
  if(opener) openProduct(opener.dataset.id);
  const closer=e.target.closest('[data-close]');
  if(closer) closeOverlay(closer.dataset.close);
});

document.getElementById('cartButton').onclick=openCart;
document.getElementById('shopWhatsapp').onclick=()=>window.open(`https://wa.me/${waNumber}?text=${encodeURIComponent('Hi BLNK, I want to see the available collection.')}`,'_blank');
document.getElementById('clearCart').onclick=()=>{cart=[];saveCart()};
document.getElementById('checkoutButton').onclick=()=>{
  if(!cart.length){alert('Your bag is empty.'); return;}
  const lines=cart.map((item,i)=>{const p=products.find(x=>x.id===item.id);return `${i+1}. ${p.name} | Size: ${item.size} | Color: ${item.color} | Qty: ${item.qty} | ${money(p.price*item.qty)}`});
  const total=cart.reduce((sum,item)=>{const p=products.find(x=>x.id===item.id);return sum+p.price*item.qty},0);
  const text=`Hi BLNK, I want to place an order.\n\n${lines.join('\n')}\n\nTotal: ${money(total)}\n\nName:\nAddress:\nPhone:`;
  window.open(`https://wa.me/${waNumber}?text=${encodeURIComponent(text)}`,'_blank');
};

document.querySelectorAll('.filter').forEach(btn=>btn.addEventListener('click',()=>{document.querySelectorAll('.filter').forEach(b=>b.classList.remove('active'));btn.classList.add('active');renderProducts(btn.dataset.filter)}));

const form=document.getElementById('styleForm');
const status=document.getElementById('formStatus');
form.addEventListener('submit',e=>{e.preventDefault();const data=new FormData(form);const text=`BLNK Style Profile\nName: ${data.get('name')}\nWhatsApp: ${data.get('phone')}\nFit: ${data.get('fit')}\nStyle: ${data.get('style')}\nSize: ${data.get('size')}\nWardrobe gap: ${data.get('gap')}`;window.open(`https://wa.me/${waNumber}?text=${encodeURIComponent(text)}`,'_blank');status.textContent='Your profile is ready — WhatsApp will open so BLNK can continue with you.'});

document.getElementById('year').textContent=new Date().getFullYear();

async function initProducts(){
  try{
    const response = await fetch('/api/products', {cache:'no-store'});
    if(response.ok){
      const live = await response.json();
      if(Array.isArray(live)) products = live.filter(p => p.active !== false);
    }
  }catch(error){
    // Keep the fallback catalog from products.js when the API is unavailable.
  }
  renderProducts();
  renderCart();
}

initProducts();
