'use strict';
// Scoped visual update. No CSV, reward entitlement, inventory, price or odds writes.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const file='data/ui/item_resources.json',before=JSON.parse(fs.readFileSync(file,'utf8'));
const table=JSON.parse(JSON.stringify(before)),index=new Map(table.items.map(r=>[r.id,r]));
const native=JSON.parse(fs.readFileSync('design_refs/archive_reward_icons_20261017/native/manifest.json','utf8')).records;
const nativeIndex=new Map(native.map(r=>[r.key,r])),changed=[];
const rankColors=['#8fc779','#73c5c9','#77bdf1','#8cacf0','#bd96ee','#e5b77c','#f2d57e','#f58c75'];
function put(id,key,text,color,overlay){
 const row=index.get(id),asset=nativeIndex.get(key);assert(row&&asset,'Established item and installed native art '+id);
 Object.assign(row,{kind:'tier_badge',uri:asset.uri,source_size:[asset.width,asset.height],badge_text:text,badge_color:color});
 delete row.vip_level;if(overlay)row.overlay_uri=nativeIndex.get(overlay).uri;else delete row.overlay_uri;
 changed.push(id);
}
for(let n=1;n<=24;n++){const tier=Math.ceil(n/3),pip=(n-1)%3+1;put('starjoy_lv'+String(n).padStart(2,'0'),'rank_tier_icons/rank'+tier+'_psd','LV'+n,rankColors[tier-1],'rank_tier_icons/pip'+pip+'_psd');}
const chests=['kunkka','morphling','bloodseeker','faceless_void','tidehunter','drow','invoker','sven','witchdoctor','omniknight','dragon_knight','international_2013'];
for(let n=1;n<=12;n++)put('vip_privilege_'+String(n).padStart(2,'0'),'econ/tools/treasure_chest_'+chests[n-1]+'_png','V'+n,['#75c8ef','#be9beb','#efcd78','#f48d79'][Math.floor((n-1)/3)]);
const medals=['1','2','3','4','5','6','7','8','8a','8b'];
for(let n=1;n<=10;n++)put('vip_medal_'+String(n).padStart(2,'0'),'rank_tier_icons/rank'+medals[n-1]+'_psd','V'+n,rankColors[Math.min(n-1,7)]);
assert.equal(changed.length,46);const targets=new Set(changed);
for(let i=0;i<table.items.length;i++)if(!targets.has(table.items[i].id))assert.deepEqual(table.items[i],before.items[i],'Preserve unrelated resource '+table.items[i].id);
assert.equal(table.items.length,before.items.length,'No new economic or identity rows');
fs.writeFileSync(file,JSON.stringify(table,null,2)+'\n');
fs.writeFileSync('design_refs/archive_reward_icons_20261017/selected_assets.json',JSON.stringify({kind:'visual_native_tier_binding_only',master:file,source_sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'),changed_ids:changed,rows:table.items.filter(r=>targets.has(r.id))},null,2)+'\n');
console.log('PASS:46 exact icon rows updated; all other resources and aliases preserved');
