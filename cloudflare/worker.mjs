import routes from './routes.mjs';
const aliases={'/':'/wholesale.html','/wholesale':'/wholesale.html','/retail':'/retail.html','/supplier':'/supplier-portal.html','/supplier-finance':'/supplier-finance.html','/suppliers-admin':'/suppliers-admin.html'};
export default {async fetch(request,env){
 const url=new URL(request.url),factory=routes[url.pathname.replace(/\/$/,'')];
 if(url.pathname.startsWith('/api/')){
  if(!factory)return Response.json({error:'Not found'},{status:404});
  let body;try{if(!['GET','HEAD'].includes(request.method)){const raw=await request.text();body=raw?JSON.parse(raw):{}}}catch{return Response.json({error:'Invalid JSON'},{status:400})}
  let status=200,result;const headers=new Headers({'Cache-Control':'no-store'});
  const res={status(n){status=n;return this},setHeader(k,v){headers.set(k,v);return this},json(value){headers.set('Content-Type','application/json; charset=utf-8');result=new Response(JSON.stringify(value),{status,headers});return this},send(value){result=new Response(value,{status,headers});return this},end(){result=new Response(null,{status,headers});return this},redirect(n,location){headers.set('Location',location);status=n;return this.end()}};
  try{await factory(env)({method:request.method,headers:Object.fromEntries(request.headers),query:Object.fromEntries(url.searchParams),body},res);return result||new Response(null,{status:204})}catch{return Response.json({error:'Server error'},{status:500,headers:{'Cache-Control':'no-store'}})}
 }
 if(aliases[url.pathname])url.pathname=aliases[url.pathname];
 const asset=await env.ASSETS.fetch(new Request(url,request));const headers=new Headers(asset.headers);headers.set('X-Content-Type-Options','nosniff');headers.set('X-BLNK-Deploy','cloudflare-migration');if(url.pathname.endsWith('.html'))headers.set('Cache-Control','no-store');return new Response(asset.body,{status:asset.status,headers});
}};
