const fs=require('fs'),vm=require('vm'),assert=require('assert');
const manifest=JSON.parse(fs.readFileSync('panorama/src/images/custom_game/shop_v2/inventory_manifest.json','utf8'));
const cfg={};vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg}});
const texture=id=>{const v=cfg.SurvivalItemArt.ResolveOriginal(id);return v&&'survival_shop_v2/'+v[0]+'_'+String(v[1]).padStart(2,'0')};
let nativeCount=0;
for(const m of fs.readFileSync('scripts/npc/npc_items_custom.txt','utf8').matchAll(/"(item_[^"]+)"\s*\{([^{}]*)\}/g)){
 if(!m[2].includes('items/item_survival_weapon_shell'))continue;
 const name=m[1],expected=texture(name);assert(expected,'Missing native item art: '+name);
 assert.equal(m[2].match(/"AbilityTextureName"\s*"([^"]+)"/)[1],expected,name);nativeCount++;
 assert(fs.existsSync('panorama/images/items/'+expected+'_png.vtex_c'),'Missing compiled texture '+expected);
}
assert.equal(nativeCount,manifest.nativeItems);
const lua=fs.readFileSync('scripts/vscripts/config/inventory_original_icons.lua','utf8');
for(const[id,value]of Object.entries(manifest.mappings)){assert.equal(texture(id),value);assert(lua.includes('["'+id+'"] = "'+value+'"'));}
for(const line of fs.readFileSync('data/csv/物品系统/weapon_definitions.csv','utf8').split(/\r?\n/)){
 const id=line.split(',')[0];if(!/^(weapon_|equipment_)/.test(id))continue;
 assert(manifest.mappings[id],'Missing equipment level '+id);
 if(id.startsWith('weapon_'))assert.equal(texture(id),texture(id.replace('weapon_','item_survival_')));
}
for(const image of manifest.images){assert(fs.existsSync('panorama/src/images/items/survival_shop_v2/'+image.file));}
assert.equal(new Set([1,2,3,4,'max'].map(n=>texture('weapon_growth_sword_'+(n==='max'?n:String(n).padStart(2,'0'))))).size,5);
console.log('INVENTORY_ORIGINAL_ICONS_PASS: '+nativeCount+' native shells; all equipment levels match shop and server texture map; compiled textures present');
