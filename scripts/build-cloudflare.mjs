import {readdir,readFile,writeFile,mkdir,rm,copyFile,stat} from 'node:fs/promises';
import path from 'node:path';
const out='dist-cloudflare';
await rm(out,{recursive:true,force:true}); await mkdir(out,{recursive:true});
const generated='cloudflare/generated';await rm(generated,{recursive:true,force:true});await mkdir(generated,{recursive:true});
let count=0,largest=0;
async function copy(src,dest){const s=await stat(src);if(s.size>25*1024*1024)throw Error(`Asset too large: ${src} (${s.size} bytes)`);await mkdir(path.dirname(dest),{recursive:true});await copyFile(src,dest);count++;largest=Math.max(largest,s.size)}
// Explicit web-file allowlist: never upload git history, node_modules, APKs, SQL or customer records.
for(const name of await readdir('.'))if(/\.(html|css|js|svg|webmanifest)$/.test(name))await copy(name,`${out}/${name}`);
await copy('products.json',`${out}/products.json`);
await copy('admin/scanner.html',`${out}/admin/scanner.html`);
let imports=[],routes=[];
async function api(dir){for(const e of await readdir(dir,{withFileTypes:true})){const p=`${dir}/${e.name}`;if(e.isDirectory()){await api(p);continue}if(!p.endsWith('.js'))continue;let source=await readFile(p,'utf8');let top=[];source=source.replace(/import\s+[^;]+;/g,m=>{top.push(m);return ''});
if(p==='api/source-image-proxy.js'){top=[];source=source.replace("JSON.parse(await fs.readFile(path.join(process.cwd(),'products.json'),'utf8'))","await env.ASSETS.fetch(new Request('https://assets.local/products.json')).then(r=>r.json())")}
source=source.replaceAll('process.env','env').replace(/export default (async )?function handler/,(_,a)=>`${a||''}function handler`);
const rel=p.slice(4).replace(/\.js$/,'.mjs'),target=`${generated}/${rel}`;await mkdir(path.dirname(target),{recursive:true});await writeFile(target,`import { Buffer } from 'node:buffer';\n${top.join('\n')}\nexport default function createHandler(env){\n${source}\nreturn handler;\n}\n`);const id=`handler${imports.length}`;imports.push(`import ${id} from './generated/${rel}';`);routes.push(`  ${JSON.stringify('/'+p.replace(/\.js$/,''))}: ${id}`)}}
await api('api');
await writeFile('cloudflare/routes.mjs',`${imports.join('\n')}\nexport default {\n${routes.join(',\n')}\n};\n`);
console.log(JSON.stringify({assets:count,largestAssetBytes:largest,apiRoutes:routes.length}));
