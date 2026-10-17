'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {open}=require('../vpk_inspect.cjs');
const cfg={},created=[];
class Panel {
 constructor(type,parent){this.type=type;this.style={};this.children=[];this.classes=[];this.visible=true;if(parent)parent.children.push(this);created.push(this);}
 IsValid(){return true;} AddClass(value){this.classes.push(value);} SetImage(value){this.image=value;} SetScaling(value){this.scaling=value;}
}
const env=vm.createContext({GameUI:{CustomUIConfig:()=>cfg},$:{CreatePanel:(type,parent)=>new Panel(type,parent)}});
for(const name of ['common/item_resources.js','reward_presentation.js'])vm.runInContext(fs.readFileSync('panorama/src/scripts/custom_game/'+name,'utf8'),env,{filename:name});
const master=JSON.parse(fs.readFileSync('data/ui/item_resources.json','utf8'));
const targets=master.items.filter(r=>/^starjoy_lv\d+$|^vip_(?:privilege|medal)_\d+$/.test(r.id));
assert.equal(targets.length,46,'24 starjoy +12 privileges +10 formally configured medals');
const vpk=open(require('node:path').resolve('../../dota/pak01_dir.vpk')),native=new Set(vpk.entries.map(e=>e.path));
const signatures=new Set();
for(const row of targets){
 const resource=cfg.SurvivalItemResources.Lookup(row.id);assert.equal(resource.kind,'tier_badge');assert.equal(resource.badge_text,row.badge_text);
 assert(native.has(row.uri.slice('s2r://'.length)+'_c'),'exact installed base '+row.id);
 if(row.overlay_uri)assert(native.has(row.overlay_uri.slice('s2r://'.length)+'_c'),'exact installed pips '+row.id);
 const icon=cfg.SurvivalRewardPresentation.CreateRegisteredIcon(new Panel('Panel'),{id:row.id},'Icon');
 assert.equal(icon.__survivalTierBadge,true);assert.equal(icon.__itemResourceId,row.id);
 assert.equal(icon.children.length,1,'single nested stage survives archive resize loops');
 const stage=icon.children[0],base=stage.children[0],badge=stage.children.at(-1);
 assert.equal(stage.style.width,'100%');assert.equal(stage.style.height,'100%');assert.equal(base.image,row.uri);
 assert.equal(base.scaling,'stretch-to-fit-preserve-aspect','native medal silhouettes retain their aspect');
 assert.equal(badge.text,row.badge_text);assert.equal(badge.style.color,row.badge_color);assert.equal(badge.style.textOverflow,'shrink');
 for(const size of [62,78,120]){icon.style.width=size+'px';icon.style.height=size+'px';cfg.SurvivalRewardPresentation.FillIcon(icon,{id:row.id});assert.equal(stage.style.width,'100%');assert.equal(base.scaling,'stretch-to-fit-preserve-aspect');}
 const signature=[row.uri,row.overlay_uri,row.badge_text].join(':');assert(!signatures.has(signature),'each level is visibly distinct');signatures.add(signature);
}
for(let level=1;level<=24;level++){
 const row=cfg.SurvivalItemResources.Lookup('starjoy_lv'+String(level).padStart(2,'0'));
 assert.equal(row.badge_text,'LV'+level);assert(row.uri.endsWith('/rank'+Math.ceil(level/3)+'_psd.vtex'));assert(row.overlay_uri.endsWith('/pip'+((level-1)%3+1)+'_psd.vtex'));
}
for(let level=1;level<=12;level++)assert.equal(cfg.SurvivalItemResources.Lookup('vip_privilege_'+String(level).padStart(2,'0')).badge_text,'V'+level);
const original=cfg.SurvivalRewardPresentation.CreateRegisteredIcon(new Panel('Panel'),{id:'vip_package_01'},'Icon');assert.equal(original.type,'Image');assert.equal(original.image,'file://{images}/econ/tools/treasure_chest_kunkka.png');assert.equal(original.scaling,'stretch-to-cover-preserve-aspect','existing paid package art remains intact');
assert.equal(cfg.SurvivalItemResources.Lookup('vip_medal_11'),null,'no artificial entitlement rows added');
// Exercise the real VIP controller with the real shared registry/factory.
const {createHarness}=require('../tests/fixtures/menus_v10_harness.cjs'),h=createHarness();
for(const file of ['common/item_resources.js','reward_presentation.js','vip_catalog.js','vip_window.js'])h.load(file);
h.setProfile({vip_badge:1});h.emit('survival_vip_snapshot',{ok:true,level:12,balance:99999,recharge_total_fen:1250000,rows:h.cfg.VIPRewardCatalog.rewards.map(r=>({id:r.reward_id,owned:0,eligible:1,affordable:1}))});
function all(panel){return [panel,...panel.Children().flatMap(all)];}
if(h.cfg.SurvivalVIPStatus){
 // A concurrent approved feature retired the VIP popup. Its passive status must
 // still consume authoritative levels without restoring the retired window.
 const api=h.cfg.SurvivalVIPStatus;assert.equal(api.Inspect().known,true);assert.equal(api.Inspect().level,12);
 const sent=h.sent.length;assert.equal(h.cfg.SurvivalVIP.Open(),false);assert.equal(h.cfg.SurvivalVIP.Toggle(),false);assert.equal(h.cfg.SurvivalVIP.IsOpen(),false);assert.equal(h.cfg.SurvivalVIP.IsAvailable(),false);assert.equal(h.sent.length,sent,'legacy window entry points cannot submit requests');
 for(const id of ['VIPWindow','VIPScrim','VIPTooltip'])if(h.nodes[id])assert.equal(h.nodes[id].visible,false,'retired '+id+' remains hidden');
 assert(!h.nodes.VIPGrid||h.nodes.VIPGrid.Children().length===0,'passive VIP status does not rebuild popup cards');
 assert(h.sent.every(r=>r.name!=='survival_vip_request'||r.payload.action==='view'),'status subscribes read-only');
 api.Dispose();
}else{
 h.cfg.SurvivalVIP.Open();
 for(const [group,count] of [['privileges',12],['medals',10]]){
  h.click(h.nodes['VIPTab_'+group]);assert.equal(h.nodes.VIPGrid.Children().length,count);
  for(const card of h.nodes.VIPGrid.Children()){
   const icon=all(card).find(p=>p.__survivalTierBadge);assert(icon,group+' actual VIP card uses registered native icon');
   const row=h.cfg.SurvivalItemResources.Lookup(icon.__itemResourceId);assert(all(icon).some(p=>p.image===row.uri));assert(all(icon).some(p=>p.text===row.badge_text));assert(!all(card).some(p=>p.__survivalVIPBadge),'old text-only VIP badge is removed');
  }
 }
}
h.cfg.SurvivalVIP.Dispose();
console.log('PASS:46 native tier icons, exact VPK resources, unique grades, responsive62/78/120px layers, original package unchanged');
