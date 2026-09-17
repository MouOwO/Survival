const fs=require('fs'),path=require('path'),crypto=require('crypto');
const here=__dirname,repo=path.resolve(here,'../../../..'),engine=path.resolve(repo,'../../..');
const roots={content:path.join(engine,'content/dota_addons/survival_ui_handoff_v1/panorama'),runtime:path.join(engine,'game/dota_addons/survival_ui_handoff_v1/panorama'),formal:path.join(repo,'panorama/src')};
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const target=path.join(here,'baseline');
if(fs.existsSync(path.join(target,'manifest.json')))throw Error('Baseline already exists; never overwrite it');
const records=[];
for(const [kind,root]of Object.entries(roots))for(const file of walk(root)){
 const rel=path.relative(root,file);if(!/^(layout|styles|scripts)[\\/]/.test(rel))continue;
 const data=fs.readFileSync(file),out=path.join(target,kind,rel);fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,data);records.push({kind,relative:rel.replaceAll('\\','/'),sha256:hash(data)});
}
fs.writeFileSync(path.join(target,'manifest.json'),JSON.stringify({created:new Date().toISOString(),roots,records},null,2));
console.log('Backed up '+records.length+' current source/runtime files; no deployment or business changes.');
