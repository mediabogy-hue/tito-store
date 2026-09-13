const products=[
{name:'Essential T-Shirt',cat:'tshirt',price:349,note:'Clean fit / everyday essential'},
{name:'Summer Shirt',cat:'shirt',price:349,note:'Lightweight / easy fit'},
{name:'Everyday Shorts',cat:'shorts',price:299,note:'Relaxed / everyday'},
{name:'Essential T-Shirt — Last Piece',cat:'last',price:349,note:'Limited sizes'},
{name:'Summer Shirt — Last Piece',cat:'last',price:349,note:'Limited sizes'},
{name:'Shorts — Last Piece',cat:'last',price:299,note:'Limited sizes'}
];
const productRoot=document.getElementById('products');
function renderProducts(filter='all'){
 const list=filter==='all'?products:products.filter(p=>p.cat===filter);
 productRoot.innerHTML=list.map(p=>`<article class="product"><div class="product-image">BLNK</div><div class="product-info"><div class="product-name">${p.name}</div><div class="product-meta">${p.note}</div><div class="product-price">EGP ${p.price.toLocaleString()}</div><a class="text-link" href="https://wa.me/201062292012?text=${encodeURIComponent('Hi BLNK, I want to order: '+p.name)}" target="_blank" rel="noreferrer" style="display:inline-block;margin-top:14px">Order →</a></div></article>`).join('');
}
renderProducts();
document.querySelectorAll('.filter').forEach(btn=>btn.addEventListener('click',()=>{document.querySelectorAll('.filter').forEach(b=>b.classList.remove('active'));btn.classList.add('active');renderProducts(btn.dataset.filter)}));
const form=document.getElementById('styleForm');
const status=document.getElementById('formStatus');
form.addEventListener('submit',e=>{e.preventDefault();const data=new FormData(form);const text=`BLNK Style Profile%0AName: ${data.get('name')}%0AWhatsApp: ${data.get('phone')}%0AFit: ${data.get('fit')}%0AStyle: ${data.get('style')}%0ASize: ${data.get('size')}%0AWardrobe gap: ${data.get('gap')}`;window.open(`https://wa.me/201062292012?text=${text}`,'_blank');status.textContent='Your profile is ready — WhatsApp will open so BLNK can continue with you.'});
document.getElementById('year').textContent=new Date().getFullYear();