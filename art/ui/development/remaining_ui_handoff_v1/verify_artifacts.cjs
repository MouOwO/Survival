const fs=require('fs'),p=require('path'),d=__dirname;
const h=['index.html','bulk_art_game.html'].filter(name=>fs.existsSync(p.join(d,'evidence',name))).map(name=>fs.readFileSync(p.join(d,'evidence',name),'utf8')).join('\n');
const links=[...h.matchAll(/(?:href|src)="([^"]+)"/g)].map(m=>m[1]).filter(x=>!x.includes('://'));
const bad=links.filter(x=>!fs.existsSync(p.resolve(d,'evidence',x)));
if(bad.length)throw Error(bad.join('\n'));
const read=f=>JSON.parse(fs.readFileSync(p.join(d,f),'utf8').replace(/^\uFEFF/,''));
const b=read('build.json'),m=read('delivery_manifest.json'),v=read('deployment_verification.json');
if(b.version!==m.version||m.version!==v.version)throw Error('Version mismatch');
console.log('Delivery links verified:',links.length,'version',b.version);
