import assert from 'node:assert/strict';
import {readFile,stat,readdir} from 'node:fs/promises';
import worker from '../cloudflare/worker.mjs';
let checks=0;
const env={ASSETS:{async fetch(req){const pathname=new URL(req.url).pathname;try{const file=await readFile('dist-cloudflare'+pathname);return new Response(file,{headers:{'Content-Type':pathname.endsWith('.html')?'text/html':'application/octet-stream'}})}catch{return new Response('Not found',{status:404})}}}};
for(const p of ['/','/admin.html','/supplier','/supplier-finance','/suppliers-admin','/orders-admin.html','/account.html','/retail']){const r=await worker.fetch(new Request('https://blnk.test'+p),env);assert.equal(r.status,200,p);assert.match(await r.text(),/<html/i,p);checks++}
for(const p of ['/api/products','/api/customer','/api/customer-transaction','/api/customer/transaction','/api/telegram-set-webhook','/api/telegram-webhook']){const r=await worker.fetch(new Request('https://blnk.test'+p,{method:'POST',body:'{}'}),env);assert.ok([401,403,500,503].includes(r.status),p);checks++}
const config=await worker.fetch(new Request('https://blnk.test/api/public-config'),{...env,SUPABASE_URL:'https://example.test',SUPABASE_PUBLISHABLE_KEY:'public-test',SUPABASE_SERVICE_ROLE_KEY:'private-test'});assert.deepEqual(await config.json(),{supabaseUrl:'https://example.test',supabasePublishableKey:'public-test'});checks++;
assert.equal((await worker.fetch(new Request('https://blnk.test/api/products',{method:'PUT',body:'{'}),env)).status,400);checks++;
for(const p of ['/customers.json','/.git/config','/api/customer.js','/supabase/schema.sql']){assert.equal((await worker.fetch(new Request('https://blnk.test'+p),env)).status,404);checks++}
for(const p of await readdir('dist-cloudflare')){if((await stat('dist-cloudflare/'+p)).isFile())assert.ok((await stat('dist-cloudflare/'+p)).size<=25*1024*1024)}
console.log(`${checks} checks passed: pages, aliases, API adapter, auth failures, malformed JSON and private-file exclusion.`);
