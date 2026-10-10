const fs=require('fs'),vm=require('vm'),assert=require('assert');
let steam='76561198104787442',toolsMode=true,badge=false,open=false,listener,props,purpleProps;
const nodes={},events={},sent=[],scheduled=[],unsubscribed=[];let unnamed=0,token=0,modalDisposals=0,purpleDisposals=0,gridRebuilds=0;
function panel(id){return nodes[id]||(nodes[id]={id,style:{},text:'',classes:new Set(),children:[],handlers:{},
 check(){assert(!this.deleted,'native methods reject deleted VIP panels');},IsValid(){return !this.deleted;},
 AddClass(c){this.check();this.classes.add(c);},RemoveClass(c){this.check();this.classes.delete(c);},BHasClass(c){this.check();return this.classes.has(c);},SetHasClass(c,v){this.check();if(v)this.classes.add(c);else this.classes.delete(c);},
 SetPanelEvent(e,f){this.check();this.handlers[e]=f;},SetImage(x){this.check();this.image=x;},Children(){this.check();return this.children;},GetParent(){this.check();return this.parent||root;},
 RemoveAndDeleteChildren(){this.check();if(this.id==='VIPGrid')gridRebuilds++;for(const child of this.children){child.deleted=true;if(child.id)delete nodes[child.id];}this.children=[];},
 GetPositionWithinWindow(){this.check();return {x:1800,y:980};},actuallayoutwidth:128,actuallayoutheight:128,actualuiscale_x:1,actualuiscale_y:1});}
const cfg={SurvivalUI:{ModalShell:{Adopt:p=>{props=p;return {Open(){open=true;},Close(){open=false;},IsOpen(){return open;},Dispose(){modalDisposals++;}};}}},SurvivalPurpleShell:{Adopt:p=>{purpleProps=p;return {Dispose(){purpleDisposals++;}};}},ReferenceWindows:{Apply(){}}};
const root={children:[],FindChildTraverse:id=>id==='VIPTooltip'&&!nodes[id]?null:panel(id),IsValid(){return !this.deleted;},actuallayoutwidth:1920,actuallayoutheight:1080,actualuiscale_x:1,actualuiscale_y:1};
const env={GameUI:{CustomUIConfig:()=>cfg},Game:{IsInToolsMode:()=>toolsMode,GetLocalPlayerID:()=>0,GetPlayerInfo:()=>({player_steamid:steam}),AddCommand(){}},
 CustomNetTables:{GetTableValue:()=>({vip_badge:badge}),SubscribeNetTableListener:(_,cb)=>{listener=cb;return ++token;},UnsubscribeNetTableListener:id=>unsubscribed.push(id)},
 GameEvents:{Subscribe:(e,cb)=>{events[e]=cb;return ++token;},Unsubscribe:id=>unsubscribed.push(id),SendCustomGameEventToServer:(e,p)=>sent.push({e,p})},
 $:{GetContextPanel:()=>root,RegisterEventHandler(){},Msg(){},Schedule(delay,fn){scheduled.push(fn);},CreatePanel:(type,parent,id)=>{let n=panel(id||'auto'+(++unnamed));parent.children.push(n);n.parent=parent;n.paneltype=type;return n;}}};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/vip_catalog.js','utf8'),env);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/vip_window.js','utf8'),env);
assert.equal(props.width,1280);assert.equal(props.height,800);assert.deepEqual(Array.from(props.fit.reference),[1920,1080]);assert.equal(purpleProps.id,'vip');assert.equal(purpleProps.navId,'','VIP does not pretend to be the mall');
assert.equal(cfg.VIPRewardCatalog.rewards.length,33);assert.equal(nodes.VIPGrid.children.length,0,'closed setup does not build reward cards');
assert(cfg.SurvivalVIP.IsAvailable());assert(cfg.SurvivalVIP.Open());assert(open);assert(!nodes.VIPAction.enabled);
assert.equal(nodes.VIPGrid.children.length,12);
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
cfg.SurvivalVIP.Open();
assert(nodes.VIPAction.enabled);assert.equal(nodes.VIPActionText.text,'免费领取');nodes.VIPAction.handlers.onactivate();
assert.equal(sent.at(-1).p.reward_id,'vip_privilege_01');assert.equal(sent.at(-1).p.action,'claim');assert(!nodes.VIPAction.enabled);
const claimCalls=sent.length;nodes.VIPAction.handlers.onactivate();assert.equal(sent.length,claimCalls,'repeated native activation while saving cannot request the reward twice');
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
cfg.SurvivalVIP.Open();const hoverCard=nodes.VIPCard_vip_privilege_12;hoverCard.handlers.onmouseover();
assert.equal(nodes.VIPTooltipName.text,'V12特权礼包');assert(nodes.VIPTooltipCondition.text.includes('12500元'));assert.equal(nodes.VIPTooltipEffect.text.split('\n').length,9,'all original reward effects remain readable in the tooltip');
assert.equal(nodes.VIPTooltip.classes.has('ArchiveHidden'),false);assert.equal(nodes.VIPTooltip.parent,root,'the tooltip stays in the original UI context outside the fitted window clip');
const [tipX,tipY]=nodes.VIPTooltip.style.position.split(' ').map(parseFloat);assert(tipX>=12&&tipX+380<=1908);assert(tipY>=12&&tipY+128<=1068);
for(const scale of [.75,1,1.5]){
 root.actualuiscale_x=scale;root.actualuiscale_y=scale;hoverCard.actualuiscale_x=scale*1.25;hoverCard.actuallayoutwidth=128*scale;nodes.VIPTooltip.actuallayoutheight=300*scale;
 hoverCard.GetPositionWithinWindow=()=>({x:1800,y:980});hoverCard.handlers.onmouseover();
 let [x,y]=nodes.VIPTooltip.style.position.split(' ').map(parseFloat);assert(x*scale>=11&&x*scale+380*scale<=1921);assert(y*scale>=11&&y*scale+300*scale<=1081);
 hoverCard.GetPositionWithinWindow=()=>({x:100,y:100});hoverCard.handlers.onmouseover();
 assert.equal(parseFloat(nodes.VIPTooltip.style.position),Math.round(100/scale+160+12),'VIP anchors use native dimensions once and only multiply the fitted panel scale ratio');
}
root.actualuiscale_x=1;root.actualuiscale_y=1;
nodes.VIPTab_packages.handlers.onactivate();assert(nodes.VIPTooltip.classes.has('ArchiveHidden'),'category changes retire the previous hovered reward');
assert.equal(nodes.VIPCard_vip_little_jacket.children.some(n=>n.classes.has('VIPRewardRank')),false,'zero catalog level does not fabricate a stock or target badge');
nodes.VIPCard_vip_little_jacket.handlers.onmouseover();assert(nodes.VIPTooltipEffect.text.includes('星悦积分+68'));assert.equal(nodes.VIPTooltipPrice.text,'价格  19 付费币');
const old=cfg.SurvivalVIP,oldSnapshot=events.survival_vip_snapshot;vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/vip_window.js','utf8'),env);
assert.equal(modalDisposals,1);assert.equal(purpleDisposals,1);assert.equal(unsubscribed.length,3);const retiredGrid=gridRebuilds;oldSnapshot(snap);assert.equal(gridRebuilds,retiredGrid,'retired snapshots cannot rebuild the replacement view');
cfg.SurvivalVIP.Open();assert.equal(nodes.VIPAction.enabled,false,'retired snapshots cannot lend authority to the replacement preview');nodes.VIPCard_vip_privilege_01.handlers.onmouseover();const oldTimers=scheduled.slice();root.deleted=true;Object.values(nodes).forEach(n=>n.deleted=true);
assert.doesNotThrow(()=>{oldTimers.forEach(fn=>fn());events.survival_vip_snapshot(snap);listener('survival_player_public_profiles','0');cfg.SurvivalVIP.Close();cfg.SurvivalVIP.Dispose();cfg.SurvivalVIP.Dispose();});assert.equal(modalDisposals,2);assert.equal(purpleDisposals,2);assert.equal(unsubscribed.length,6);assert.equal(cfg.SurvivalVIP.IsOpen(),false);assert.equal(cfg.SurvivalVIP.IsAvailable(),false,'a retired view does not advertise a live navigation target');
console.log('PASS complete effect tooltip, measured bounds, no fake quantity, safe category changes and strict deleted-subtree hot reload');
