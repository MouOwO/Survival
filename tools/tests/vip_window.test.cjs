const fs=require('fs'),vm=require('vm'),assert=require('assert');
let steam='76561198104787442',toolsMode=true,badge=false,open=false,listener,props;
const nodes={},events={},sent=[];let unnamed=0;
function panel(id){return nodes[id]||(nodes[id]={id,style:{},text:'',classes:new Set(),children:[],handlers:{},
 AddClass(c){this.classes.add(c);},SetHasClass(c,v){if(v)this.classes.add(c);else this.classes.delete(c);},
 SetPanelEvent(e,f){this.handlers[e]=f;},SetImage(x){this.image=x;},RemoveAndDeleteChildren(){this.children=[];}});}
const cfg={SurvivalUI:{ModalShell:{Adopt:p=>{props=p;return {Open(){open=true;},Close(){open=false;},IsOpen(){return open;}};}}},ReferenceWindows:{Apply(){}}};
const root={FindChildTraverse:panel};
const env={GameUI:{CustomUIConfig:()=>cfg},Game:{IsInToolsMode:()=>toolsMode,GetLocalPlayerID:()=>0,GetPlayerInfo:()=>({player_steamid:steam}),AddCommand(){}},
 CustomNetTables:{GetTableValue:()=>({vip_badge:badge}),SubscribeNetTableListener:(_,cb)=>listener=cb},
 GameEvents:{Subscribe:(e,cb)=>events[e]=cb,SendCustomGameEventToServer:(e,p)=>sent.push({e,p})},
 $:{GetContextPanel:()=>root,RegisterEventHandler(){},Msg(){},Schedule(){},CreatePanel:(type,parent,id)=>{let n=panel(id||'auto'+(++unnamed));parent.children.push(n);return n;}}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/vip_catalog.js','utf8'),env);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/vip_window.js','utf8'),env);
assert.equal(props.width,869);assert.equal(props.height,816);assert.deepEqual(Array.from(props.fit.reference),[1672,941]);
assert.equal(cfg.VIPRewardCatalog.rewards.length,33);assert.equal(nodes.VIPGrid.children.length,12);
assert(cfg.SurvivalVIP.IsAvailable());assert(cfg.SurvivalVIP.Open());assert(open);assert(!nodes.VIPAction.enabled);
assert.equal(sent[0].p.action,'view');nodes.VIPAction.handlers.onactivate();assert.equal(sent.length,1,'preview cannot claim');
cfg.SurvivalVIP.Toggle();assert(!open);
steam='76561198000000000';assert(!cfg.SurvivalVIP.IsAvailable());assert.equal(cfg.SurvivalVIP.Open(),false);
steam='76561198104787442';toolsMode=false;assert(!cfg.SurvivalVIP.IsAvailable());
badge=1;assert(cfg.SurvivalVIP.Open());assert(open);badge=0;listener('survival_player_public_profiles','0');assert(!open);
toolsMode=true;assert(cfg.SurvivalVIP.Open());props.onClose();assert(!open);
console.log('PASS Tools preview identity isolation, real VIP entitlement, archive dimensions, no preview grants');
const snap={ok:true,level:2,balance:19,rows:{}};
for(const [i,r] of cfg.VIPRewardCatalog.rewards.entries())snap.rows[i]={id:r.reward_id,owned:0,eligible:r.group_id==='privileges'&&r.level<=2||r.group_id==='packages'?1:0,affordable:r.price<=19?1:0};
events.survival_vip_snapshot(snap);
assert(nodes.VIPAction.enabled);assert.equal(nodes.VIPActionText.text,'免费领取');nodes.VIPAction.handlers.onactivate();
assert.equal(sent.at(-1).p.reward_id,'vip_privilege_01');assert.equal(sent.at(-1).p.action,'claim');assert(!nodes.VIPAction.enabled);
snap.rows[0].owned=1;events.survival_vip_snapshot(snap);
assert(nodes.VIPCard_vip_privilege_01.classes.has('VIPOwned'));assert(!nodes.VIPAction.enabled);
nodes.VIPTab_medals.handlers.onactivate();assert.equal(nodes.VIPGrid.children.length,10);assert(!nodes.VIPAction.enabled);
nodes.VIPTab_packages.handlers.onactivate();assert.equal(nodes.VIPGrid.children.length,11);
assert.equal(nodes.VIPActionText.text,'购买 · 10 付费币');nodes.VIPCard_vip_package_03.handlers.onactivate();
assert(!nodes.VIPAction.enabled);assert.equal(nodes.VIPActionText.text,'付费币不足');
nodes.VIPCard_vip_little_jacket.handlers.onactivate();assert(nodes.VIPAction.enabled);assert(nodes.VIPEffectsRight.text.includes('星悦积分+68'));
nodes.VIPAction.handlers.onactivate();assert.equal(sent.at(-1).p.action,'purchase');assert.equal(sent.at(-1).p.reward_id,'vip_little_jacket');
assert.deepEqual(Object.keys(sent.at(-1).p).sort(),['action','reward_id'],'client sends only reward identity');
console.log('PASS three tabs, 33 cards, real ownership lighting, free claims, coin prices, insufficient funds, busy gating, complete effects');

const thresholds=[50,100,250,500,1000,1500,2500,4000,6000,7500,10000,12500];
assert.deepEqual(Array.from(cfg.VIPRewardCatalog.recharge_levels,r=>r.required_recharge_yuan),thresholds);
assert.equal(cfg.VIPRewardCatalog.recharge_thresholds_pending,false);
snap.recharge_total_fen=24999;snap.level=2;events.survival_vip_snapshot(snap);
assert.equal(nodes.VIPRechargeProgress.text,'累计充值 249.99 元 · 距VIP3还差 0.01 元');
snap.recharge_total_fen=1250000;snap.level=12;events.survival_vip_snapshot(snap);
assert.equal(nodes.VIPRechargeProgress.text,'累计充值 12500 元 · 已达最高等级');
nodes.VIPTab_privileges.handlers.onactivate();
assert(nodes.VIPCondition.text.includes('50元'));assert(nodes.VIPGrid.children[11].children.some(n=>n.text==='累计 12500 元'));
console.log('PASS recharge thresholds, exact cents progress, max grade and card conditions');
