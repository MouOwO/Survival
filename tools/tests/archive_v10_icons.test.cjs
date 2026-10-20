'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..'),data=require(path.join(root,'data/ui/archive_v10_icon_bindings.json')),cfg={};
const {textureDimensions}=require('../archive_v10/build_icons.cjs');
assert.deepEqual(textureDimensions('Width = 256\nHeight = 256\nDisplayRectW = 256\nDisplayRectH = 170','fixture').size,[256,170],'Padded storage height must never distort the actual inventory image');
assert.deepEqual(textureDimensions('Width = 88\nHeight = 64\nDisplayRectW = 0\nDisplayRectH = 0','fixture').size,[88,64],'Textures with no display rectangle use the actual storage dimensions');
assert.deepEqual(textureDimensions('Width = 88\nHeight = 64','fixture').size,[88,64],'Older metadata without display fields has a safe native-size fallback');
assert.throws(()=>textureDimensions('Width = 0\nHeight = 0\nDisplayRectW = 0\nDisplayRectH = 0','fixture'),/No real texture dimensions/);
for(const file of ['common/item_resources.js','archive_v10_icons.js'])vm.runInNewContext(fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game',file),'utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const api=cfg.ArchiveV10Icons;assert(api&&typeof api.Resolve==='function');
assert.equal(data.bindings.length,35);assert.equal(data.bindings.filter(r=>r.category==='fragment').length,12);assert.equal(data.bindings.filter(r=>r.category==='building').length,9);assert.equal(data.bindings.filter(r=>r.category==='points').length,14);
const seen=new Set();for(const row of data.bindings){
 const key=row.category+':'+row.id;assert(!seen.has(key),'No ambiguous binding: '+key);seen.add(key);
 const item={id:row.id,name:row.name,count:7,level:3,description:'正式属性保持'},before=JSON.stringify(item),resolved=api.Resolve(item,row.category);
 const canonical=cfg.SurvivalItemResources.Lookup(item);assert(canonical,'historical formal entry remains registered');
 assert.equal(JSON.stringify(item),before,'Resolving cannot modify authoritative data');assert.equal(resolved.uri,canonical.uri);assert.equal(resolved.fit,canonical.fit||(canonical.kind==='image'||canonical.kind==='hero'?'cover':'contain'));assert.equal(resolved.iconKey,canonical.id+':'+canonical.uri);assert.deepEqual(Array.from(resolved.sourceSize),Array.from(canonical.source_size||[84,84]));
 assert(row.evidence.formal_file.startsWith('data/csv/'));assert(row.evidence.formal_name===row.name);assert(row.evidence.resource_sha256.length===64);assert(row.source_size.every(n=>n>0));
 resolved.sourceSize[0]=1;assert.equal(api.Resolve(item,row.category).sourceSize[0],(canonical.source_size||[84,84])[0],'Returned size arrays cannot corrupt future resolutions');
}
assert.equal(api.Resolve(null,'building'),null);assert.equal(api.Resolve({id:'unknown'},'points'),null);
assert.equal(api.Resolve({id:'vip_privilege_12'},'commerce_goods').fit,'contain','VIP numbers retain their dedicated layout');
assert.equal(api.Resolve({id:'fragment_01'},'points').uri,api.Resolve({id:'fragment_01'},'fragment').uri,'A stable item identity resolves equally in different UIs');
for(let i=1;i<=23;i++){const id='shadow_'+String(i).padStart(2,'0');assert.equal(api.Resolve({id},'shadow').uri,cfg.SurvivalItemResources.Resolve(id),'Confirmed shadow resource is centralized');}
assert(api.Resolve({id:'fragment_10'},'fragment').uri.includes('blades_voth_domosh/blades_voth_domosh.png'),'The actually missing native Legion Commander path is repaired');
assert(data.bindings.find(r=>r.id==='fragment_10').evidence.native_path_correction,'Resource correction retains explicit evidence');
assert(api.Resolve({id:'fragment_09'},'fragment').uri.includes('weaver_ti7_immortal_head_gold'),'Golden Touch retains exact Golden Cyrridae source, not a generic gold item');
assert.deepEqual(data.bindings.find(r=>r.id==='fragment_11').source_size,[256,170],'Historical Clinkz binding keeps its 256x170 display rectangle as evidence');
assert.deepEqual(data.bindings.find(r=>r.id==='fragment_11').evidence.texture_storage_size,[256,256],'Padded storage is retained separately as source evidence');
for(const id of ['lottery_attribute_crystal','lottery_time_orb','lottery_windspeed_bowstring','lottery_echo_compass','lottery_magical_girl_juggernaut'])assert.equal(api.Resolve({id},'points').uri,cfg.SurvivalItemResources.Resolve(id),'Every specific item uses the central resource: '+id);
const adapter=fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/archive_v10_icons.js'),'utf8');assert(adapter.includes('SurvivalItemResources'));assert(!adapter.includes('var rows=['),'Archive cannot reintroduce a competing item resource table');
console.log('ARCHIVE_V10_ICONS_PASS: historical 35-item Valve evidence retained; runtime resolves only the shared table; correct native source dimensions; stable identities across UI categories; no authoritative data mutation.');
