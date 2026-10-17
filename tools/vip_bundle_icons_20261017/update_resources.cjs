'use strict';
// One-time, exact ten-row art update. Runtime consumers read the maintained table.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const master='data/ui/item_resources.json',out='design_refs/vip_bundle_icons_20261017';
const sourceHash=crypto.createHash('sha256').update(fs.readFileSync(master)).digest('hex');
assert(['300dcdae35ae810712e277aef4f287463df7d4ae435fae37169b7e8015c5c4a0','ddd90bcf52fc9447df3303ed0a4dddb871704ce1e9141d11d84f52bf712cf5cf'].includes(sourceHash),'One-time importer refuses to overwrite later resource-table edits; maintain the master table directly.');
const candidates=JSON.parse(fs.readFileSync(out+'/native_candidates/manifest.json','utf8')).records;
const heroes=['kunkka','morphling','bloodseeker','faceless_void','tidehunter','drow','invoker','sven','witchdoctor','omniknight'];
const colors=['青绿金边','冰蓝银边','红金','紫色金饰','墨绿金饰','深蓝冰光','金色皇冠','银紫蓝','深紫角饰','银白金饰'];
const table=JSON.parse(fs.readFileSync(master,'utf8').replace(/^\uFEFF/,'')),selected=[];
heroes.forEach((hero,index)=>{
 const level=index+1,id='vip_package_'+String(level).padStart(2,'0'),row=table.items.find(r=>r.id===id);
 const asset=candidates.find(r=>r.key==='treasure_chest_'+hero);
 assert(row&&asset,'Exact established package and native resource exist: '+id);
 assert(row.aliases.includes('video_bundle_vip_'+String(level).padStart(2,'0')));
 assert.equal(asset.width,256);assert.equal(asset.height,170);
 assert(fs.existsSync(asset.previewPng));
 assert.equal(row.kind==='vip'||row.kind==='image',true);
 row.kind='image';row.uri=asset.uri;row.source_size=[asset.width,asset.height];delete row.vip_level;
 selected.push({level,id,color:colors[index],...asset});
});
assert.equal(new Set(selected.map(r=>r.uri)).size,10,'Every VIP bundle has distinct art');
fs.writeFileSync(master,JSON.stringify(table,null,2)+'\n');
fs.writeFileSync(out+'/selected_assets.json',JSON.stringify({kind:'reviewed_native_art_evidence_only',runtimeAuthority:master,source:'Installed Dota2 pak01_dir.vpk; original textures unchanged',referenceVideo:'bandicam 2026-10-15 12-42-43-408.mp4',records:selected},null,2)+'\n');
console.log('VIP_BUNDLE_ART_UPDATED: ten exact package rows; aliases retained; native art only');
