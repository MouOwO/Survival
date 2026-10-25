'use strict';
// Export exact selected native textures, never substitute placeholder artwork.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto'),{pathToFileURL,fileURLToPath}=require('node:url');
const {open}=require('../vpk_inspect.cjs');
const root=path.resolve(__dirname,'../..'),base=path.join(root,'output/ui_qa_20261025/browser');
const arg=(n,d)=>{const i=process.argv.indexOf(n);return i<0?d:process.argv[i+1];};
const label=arg('--label','baseline');if(!/^[a-z0-9_-]{1,40}$/.test(label))throw Error('Invalid label');
const discoveryLabel=arg('--discovery-label',label);if(!/^[a-z0-9_-]{1,40}$/.test(discoveryLabel))throw Error('Invalid discovery label');
const snapshot=path.join(base,label,'preview'),discovery=path.join(base,discoveryLabel,'discovery.json');
const out=path.join(base,'native_icons');fs.mkdirSync(out,{recursive:true});
const viewer=path.join(root,'output/valley_decor_v2/source2viewer/Source2Viewer-CLI.exe');
if(!fs.existsSync(viewer))throw Error('Reviewed local image decoder unavailable');
const archiveFile=path.resolve(root,'../../dota/pak01_dir.vpk'),vpk=open(archiveFile),entries=new Map(vpk.entries.map(e=>[e.path,e]));
const hash=x=>crypto.createHash('sha256').update(x).digest('hex');
const table=Array.from({length:256},(_,i)=>{let n=i;for(let j=0;j<8;j++)n=n&1?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
function crc32(raw){let n=0xffffffff;for(const b of raw)n=table[(n^b)&255]^(n>>>8);return (n^0xffffffff)>>>0;}
const aliases={},records=[],missing=[];
const uris=new Set();
const seedLabel=arg('--seed-label',label);if(!/^[a-z0-9_-]{1,40}$/.test(seedLabel))throw Error('Invalid seed label');
for(const previousManifest of new Set([path.join(base,label,'native_icons.json'),path.join(base,seedLabel,'native_icons.json')]))if(fs.existsSync(previousManifest))for(const row of JSON.parse(fs.readFileSync(previousManifest,'utf8')).records||[])if(row.uri)uris.add(row.uri);
const html=fs.readFileSync(path.join(snapshot,'index.html'),'utf8');
for(const m of html.matchAll(/file:\/\/\{images\}\/((?:control_icons|hud\/reborn|status_icons)\/[A-Za-z0-9_./-]+\.(?:png|svg|psd))/g))uris.add('file://{images}/'+m[1]);
for(const m of html.matchAll(/s2r:\/\/panorama\/images\/(?:control_icons|hud\/reborn|status_icons)\/[A-Za-z0-9_./-]+\.(?:vtex|vsvg)(?:_c)?/g))uris.add(m[0]);
const discoveryFiles=[...new Set([path.join(base,'baseline/discovery.json'),discovery])];
for(const discoveryFile of discoveryFiles)if(fs.existsSync(discoveryFile))for(const item of JSON.parse(fs.readFileSync(discoveryFile,'utf8')).cases||[])for(const image of [...item.metrics?.missingImages||[],...item.metrics?.backgrounds?.missing||[]]){
 if(image.src.startsWith('s2r://panorama/images/'))uris.add(image.src);
 else try{const full=fileURLToPath(image.src).replaceAll('\\','/'),match=full.match(/\/(?:art\/ui\/sources|panorama\/src\/images)\/(.+)$/);if(match)uris.add('file://{images}/'+match[1]);}catch(_){}
}
for(const uri of uris){
 const vector=/\.(?:svg|vsvg)(?:_c)?$/.test(uri),psd=/\.psd$/.test(uri);
 let relative=uri.startsWith('s2r://')?uri.slice('s2r://panorama/images/'.length).replace(/\.(?:vtex|vsvg)(?:_c)?$/,''):uri.slice('file://{images}/'.length).replace(/\.(?:png|svg|psd)$/,'');
 if(relative.includes('..')||!/^[-A-Za-z0-9_./]+$/.test(relative))continue;
 const candidates=vector?['panorama/images/'+relative+'.vsvg_c']:['panorama/images/'+relative+(psd?'_psd':'_png')+'.vtex_c','panorama/images/'+relative+'.vtex_c'];
 const resource=candidates.find(p=>entries.has(p));
 const originalRelative=uri.startsWith('file://{images}/')?uri.slice('file://{images}/'.length):relative.replace(/_(png|psd)$/,'')+(vector?'.svg':'.png');
 const local=path.join(root,'panorama/src/images',originalRelative);
 if(!resource&&fs.existsSync(local)){
  const pixels=fs.readFileSync(local),target=pathToFileURL(local).href;
  if(vector?!pixels.toString('utf8').includes('<svg'):pixels.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('Local original is not an expected image');
  for(const key of [uri,'file://{images}/'+originalRelative,originalRelative,pathToFileURL(path.join(root,'art/ui/sources',originalRelative)).href,target])aliases[key]=target;
  records.push({uri,kind:'actual_local_source_image',source:path.relative(root,local).replaceAll('\\','/'),sourceSha256:hash(pixels),decodedSha256:hash(pixels),width:vector?null:pixels.readUInt32BE(16),height:vector?null:pixels.readUInt32BE(20)});continue;
 }
 if(!resource){missing.push({uri,candidates});continue;}
 const entry=entries.get(resource),raw=vpk.read(entry);
 if(raw.length!==entry.length+entry.preload.length||crc32(raw)!==entry.crc)throw Error('Native texture CRC mismatch: '+resource);
 const id=hash(Buffer.from(resource)).slice(0,16),input=path.join(out,id+(vector?'.vsvg_c':'.vtex_c')),png=path.join(out,id+(vector?'.svg':'.png'));
 if(fs.existsSync(input)&&hash(fs.readFileSync(input))!==hash(raw))throw Error('Cached resource source changed; use a new export directory');
 if(!fs.existsSync(png)){if(!fs.existsSync(input))fs.writeFileSync(input,raw,{flag:'wx'});cp.execFileSync(viewer,['-i',input,'-o',png,'-d'],{windowsHide:true,stdio:'pipe',timeout:30000});}
 const pixels=fs.readFileSync(png);if(vector?!pixels.toString('utf8').includes('<svg'):pixels.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('Texture decoder returned no expected image');
 const target=pathToFileURL(png).href;
 const nativeFile='file://{images}/'+resource.slice('panorama/images/'.length).replace(/_png\.vtex_c$/,'.png').replace(/_psd\.vtex_c$/,'.psd').replace(/\.vsvg_c$/,'.svg');
 const nativeS2r='s2r://'+resource.replace(/\.vtex_c$/,'.vtex').replace(/\.vsvg_c$/,'.vsvg');
 const originalFile=nativeFile.slice('file://{images}/'.length);
 for(const key of [uri,nativeFile,nativeS2r,originalFile,pathToFileURL(path.join(root,'art/ui/sources',originalFile)).href,pathToFileURL(path.join(root,'panorama/src/images',originalFile)).href])aliases[key]=target;
 records.push({uri,resource,resourceSha256:hash(raw),crc32:entry.crc.toString(16).padStart(8,'0'),decodedSha256:hash(pixels),width:vector?null:pixels.readUInt32BE(16),height:vector?null:pixels.readUInt32BE(20),decoded:path.relative(root,png).replaceAll('\\','/')});
}
// Restrict overrides to our generated snapshot. Production and old manifests stay intact.
let patched=html.replace(/<script data-uiqa-native-icons>[\s\S]*?<\/script>/g,'');
const marker='<script src="'+pathToFileURL(path.join(snapshot,'adapter.js')).href+'"></script>';
if(!patched.includes(marker))throw Error('Expected task-owned adapter reference missing');
patched=patched.replace(marker,'<script data-uiqa-native-icons>Object.assign(window.PREVIEW_ASSET_PATHS,'+JSON.stringify(aliases)+');</script>'+marker);
let css=fs.readFileSync(path.join(snapshot,'style.css'),'utf8');
for(const [uri,target]of Object.entries(aliases))if(uri.startsWith('s2r://'))css=css.replaceAll(uri,target);
for(const [uri,target]of Object.entries(aliases))if(uri.startsWith('file://{images}/')){
 const relative=uri.slice('file://{images}/'.length);
 for(const directory of ['art/ui/sources','panorama/src/images']){const local=pathToFileURL(path.join(root,directory,relative)).href;css=css.replaceAll(local,target);}
}
fs.writeFileSync(path.join(snapshot,'index.html'),patched);fs.writeFileSync(path.join(snapshot,'style.css'),css);
const result={schema:1,kind:'exact_official_vpk_texture_pixels_browser_only',at:new Date().toISOString(),archive:path.relative(root,archiveFile).replaceAll('\\','/'),aliases,records,missing};
fs.writeFileSync(path.join(base,label,'native_icons.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify({status:'NATIVE_TEXTURE_EXPORT',label,decoded:records.length,missing:missing.length}));
