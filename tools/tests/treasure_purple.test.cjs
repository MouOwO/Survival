const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path'),project=path.resolve(__dirname,'../..'),nodes={},scheduled=[],listeners={};
class Panel{
 constructor(type,parent,id=''){this.type=type;this.id=id;this.parent=parent;this.children=[];this.classes=new Set();this.style={};this.events={};this.visible=true;this.actuallayoutwidth=128;this.actuallayoutheight=128;this.actualuiscale_x=1;this.actualuiscale_y=1;if(parent)parent.children.push(this);if(id)nodes[id]=this;}
 check(){assert(!this.deleted,'native methods cannot access deleted panels');}
 AddClass(c){this.check();this.classes.add(c);}RemoveClass(c){this.check();this.classes.delete(c);}BHasClass(c){this.check();return this.classes.has(c);}IsValid(){return !this.deleted;}
 Children(){this.check();return this.children;}RemoveAndDeleteChildren(){this.check();for(const child of this.children.slice())child.DeleteAsync();this.children=[];}DeleteAsync(){for(const child of this.children.slice())child.DeleteAsync();this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);}
 FindChildTraverse(id){this.check();if(this.id===id)return this;for(const child of this.children){if(!child.IsValid())continue;const result=child.FindChildTraverse(id);if(result)return result;}return null;}
 SetParent(parent){if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);this.parent=parent;parent.children.push(this);}
 GetParent(){return this.parent;}
 MoveChildBefore(child,before){this.children=this.children.filter(p=>p!==child);this.children.splice(this.children.indexOf(before),0,child);}
 SetPanelEvent(name,fn){this.events[name]=fn;}SetImage(value){this.image=value;}SetFocus(){}
 GetPositionWithinWindow(){return {x:1800,y:980};}
}
let root,archiveRoot,win,tip;
function fixture(){
root=new Panel('Panel',null,'Root');root.actuallayoutwidth=1920;root.actuallayoutheight=1080;
archiveRoot=new Panel('Panel',root,'ArchiveRoot');win=new Panel('Panel',archiveRoot,'TreasureWindow');const content=new Panel('Panel',win,'TreasureContent'),header=new Panel('Panel',content,'TreasureHeader');
for(const id of ['TreasureAtmosphere','TreasureFrame'])new Panel('Panel',win,id);
new Panel('Button',root,'TreasureScrim');new Panel('Label',header,'TreasureCount');
for(const id of ['TreasureHint','TreasureCards','TreasureDetail'])new Panel('Panel',content,id);
new Panel('Image',nodes.TreasureDetail,'TreasureDetailDivider');new Panel('Label',nodes.TreasureDetail,'TreasureDetailHint');
tip=new Panel('Panel',nodes.TreasureDetail,'TreasureTooltip');tip.actuallayoutheight=240;
new Panel('Label',tip,'TreasureTooltipName');new Panel('Label',tip,'TreasureTooltipEffect');
}fixture();
let snapshot={history:[]},modalProps,purpleProps,openCalls=0,closeCalls=0,modalDisposals=0,purpleDisposals=0,subscriptionId=0;const unsubscribed=[];
const cfg={SurvivalUI:{ModalShell:{Adopt(props){modalProps=props;return {Open(){openCalls++;},Close(){closeCalls++;},Dispose(){modalDisposals++;}};}}},SurvivalPurpleShell:{Adopt(props){purpleProps=props;return {Dispose(){purpleDisposals++;}};}}};
const dollar=id=>nodes[id.slice(1)];dollar.GetContextPanel=()=>root;dollar.CreatePanel=(type,parent,id)=>new Panel(type,parent,id);dollar.Schedule=(seconds,fn)=>{scheduled.push(fn);};dollar.RegisterEventHandler=()=>{};
const source=fs.readFileSync(path.join(project,'panorama/src/scripts/custom_game/treasure_history.js'),'utf8');
const context={
 GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0,IsInToolsMode:()=>false},$ :dollar,
 CustomNetTables:{GetTableValue:()=>snapshot,SubscribeNetTableListener:(name,fn)=>{listeners[name]=fn;return ++subscriptionId;},UnsubscribeNetTableListener:id=>unsubscribed.push(id)}
};
vm.runInNewContext(source,context);
assert.equal(modalProps.id,'treasure');assert.deepEqual(Array.from(modalProps.fit.reference),[1920,1080]);assert.equal(purpleProps.id,'treasure');
assert.equal(tip.parent,archiveRoot,'the tooltip remains under the original scoped UI root, within this context and outside the fitted content clip');
cfg.SurvivalTreasure.Open();cfg.SurvivalTreasure.Open();assert.equal(openCalls,1);assert.equal(cfg.SurvivalTreasure.IsOpen(),true);
assert.equal(nodes.TreasureCards.children.length,0,'empty history renders an empty state, not twenty vacant rewards');assert.equal(nodes.TreasureEmpty.visible,true);
snapshot={history:Array.from({length:27},(_,i)=>({name:'宝物'+i,description:'效果'+i,icon_name:i===0?'survival/native/frozen_wall':'lich_frost_shield',...(i===0?{quantity:3}:{})}))};
listeners.survival_rogue_reward('survival_rogue_reward','1',snapshot);assert.equal(nodes.TreasureCards.children.length,0,'another player does not alter local history');
listeners.survival_rogue_reward('survival_rogue_reward','0',snapshot);
assert.equal(nodes.TreasureCards.children.length,20);assert.equal(nodes.TreasureCount.text,'20 / 20');assert.equal(nodes.TreasureEmpty.visible,false);
const cards=nodes.TreasureCards.children,first=cards[0];assert.equal(first.style.width,'128px');assert.equal(first.style.height,'128px');
assert.equal(first.children.find(p=>p.BHasClass('TreasureQuantity')).text,'×3');assert.equal(cards[1].children.some(p=>p.BHasClass('TreasureQuantity')),false,'one history record does not imply a fabricated inventory quantity');
assert.equal(first.children.find(p=>p.BHasClass('TreasureArt')).children[0].image,'file://{images}/spellicons/survival/native/frozen_wall.png');
first.events.onmouseover();assert.equal(nodes.TreasureTooltipName.text,'宝物0');assert.equal(nodes.TreasureTooltipEffect.text,'效果0');assert.equal(nodes.TreasureTooltipCount.text,'拥有数量  3');
assert.equal(tip.BHasClass('ArchiveHidden'),false);const [x,y]=tip.style.position.split(' ').map(parseFloat);assert(x>=12&&x+380<=1908);assert(y>=12&&y+240<=1068);
cfg.SurvivalTreasure.Close();assert.equal(closeCalls,1);assert.equal(cfg.SurvivalTreasure.IsOpen(),false);assert.equal(tip.BHasClass('ArchiveHidden'),true);
const scheduledCount=scheduled.length;for(const fn of scheduled.slice())fn();assert.equal(scheduled.length,scheduledCount,'closing cancels the tooltip position generation');
const oldApi=cfg.SurvivalTreasure,oldListener=listeners.survival_rogue_reward;
vm.runInNewContext(source,context);
assert.equal(modalDisposals,1);assert.equal(purpleDisposals,1);assert.deepEqual(unsubscribed,[1]);assert.equal(oldApi.IsOpen(),false);
assert.equal(nodes.TreasureContent.children.filter(p=>p.id==='TreasureEmpty').length,1,'hot reload reuses the empty label');
assert.equal(tip.children.filter(p=>p.id==='TreasureTooltipCount').length,1,'hot reload reuses quantity label');
assert.equal(tip.children.filter(p=>p.BHasClass('TreasureTooltipHeading')).length,1,'hot reload reuses effect heading');
cfg.SurvivalTreasure.Open();oldListener('survival_rogue_reward','0',{history:[]});assert.equal(nodes.TreasureCards.children.length,20,'retired subscriptions cannot change the new view');
nodes.TreasureCards.children[0].events.onmouseover();const retiredApi=cfg.SurvivalTreasure,retiredListener=listeners.survival_rogue_reward,pending=scheduled.slice();root.DeleteAsync();
assert.doesNotThrow(()=>{pending.forEach(fn=>fn());retiredListener('survival_rogue_reward','0',snapshot);retiredApi.Close();retiredApi.Dispose();retiredApi.Dispose();});
assert.equal(retiredApi.IsOpen(),false);assert.deepEqual(unsubscribed,[1,2]);assert.equal(modalDisposals,2);assert.equal(purpleDisposals,2);
fixture();assert.doesNotThrow(()=>vm.runInNewContext(source,context));cfg.SurvivalTreasure.Open();assert.equal(nodes.TreasureCards.children.length,20,'a replacement native subtree starts normally after disposal');
console.log('TREASURE_PURPLE_PASS: shared modal, empty state, authoritative cap, player isolation, real quantity, original icons, measured tooltip, close and strict deleted-subtree hot reload');
