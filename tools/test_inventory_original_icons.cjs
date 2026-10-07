const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {Vpk}=require('./map_c6/lib.cjs');
const vpk=new Vpk('../../dota/pak01_dir.vpk');
const manifest=JSON.parse(fs.readFileSync('panorama/src/images/custom_game/shop_v2/inventory_manifest.json','utf8'));
assert.equal(manifest.mode,'dota_native');
const cfg={}, panels=[];
const $={CreatePanel:(type,parent,id)=>{const p={type,parent,id,style:{},AddClass(c){this.className=c;},SetImage(uri){this.uri=uri;},SetScaling(v){this.scaling=v;}};panels.push(p);return p;},Schedule(){throw Error('Icons must not schedule work');}};
const env={$,GameUI:{CustomUIConfig:()=>cfg}};
const load=name=>vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name+'.js','utf8'),env);
load('native_ui_icons');load('reward_presentation');load('item_art_remaining_5d5c1152eb');
const original=cfg.SurvivalRewardPresentation.OriginalCreateIcon;
load('item_art_remaining_5d5c1152eb');assert.strictEqual(cfg.SurvivalRewardPresentation.OriginalCreateIcon,original,'reload cannot nest wrappers');
for(const[id,value]of Object.entries(manifest.icons)){
 const resource='panorama/images/'+(value.type==='item'?'items/':'spellicons/')+value.name+'_png.vtex_c';
 assert(vpk.entries.has(resource),'Missing official texture '+id+' '+resource);
 assert.equal(cfg.SurvivalNativeIcons.Resolve(id).uri,value.uri,id);
 for(const entry of [{content_id:id},{contentid:id},{icon:value.type==='item'?'item_'+value.name:value.name,icon_type:value.type}]){
  const icon=cfg.SurvivalItemArt.Create({},entry,'Icon');
  assert.equal(icon.uri,value.uri,id);assert.equal(icon.hittest,false);assert.equal(icon.hittestchildren,false);
 }
}
const lua=fs.readFileSync('scripts/vscripts/config/inventory_original_icons.lua','utf8');
for(const[id,texture]of Object.entries(manifest.mappings))assert(lua.includes('["'+id+'"] = "'+texture+'"'),id);
let nativeCount=0;
for(const m of fs.readFileSync('scripts/npc/npc_items_custom.txt','utf8').matchAll(/"(item_[^"]+)"\s*\{([^{}]*)\}/g)){
 const texture=m[2].match(/"AbilityTextureName"\s*"([^"]+)"/);
 if(!texture)continue;
 assert.equal(texture[1],manifest.mappings[m[1]],m[1]);nativeCount++;
}
assert.equal(nativeCount,manifest.nativeItems);
for(const[id,texture]of Object.entries(manifest.ability_icons))assert(vpk.entries.has('panorama/images/spellicons/'+texture+'_png.vtex_c'),id);
assert.equal(new Set([1,2,3,4,'max'].map(n=>manifest.mappings['weapon_growth_sword_'+(n==='max'?n:String(n).padStart(2,'0'))])).size,5);
const layout=fs.readFileSync('panorama/src/layout/custom_game/survival_hud.xml','utf8');
assert(layout.indexOf('native_ui_icons.js')<layout.indexOf('item_art_remaining'),'native factory must load before consumers');
load('rogue_art_remaining_5d5c1152eb');
for(const line of fs.readFileSync('data/csv/肉鸽奖励系统/rogue_reward_cards.csv','utf8').split(/\r?\n/).slice(1)){
 const id=line.split(',')[0];if(!id||id.startsWith('#'))continue;
 assert(cfg.SurvivalRogueArt.Apply({style:{}},{card_id:id}));
 const art=panels.at(-1);assert.equal(art.uri,manifest.icons[id].uri,id);
 assert.equal(art.style.width,'232px');assert.equal(art.style.height,'232px');
}
console.log('NATIVE_UI_ICONS_PASS: '+nativeCount+' engine items; '+Object.keys(manifest.ability_icons).length+' skill icons; '+Object.keys(manifest.icons).length+' UI identities; original VPK textures, shared shop/inventory images, no timers or nested wrappers');
