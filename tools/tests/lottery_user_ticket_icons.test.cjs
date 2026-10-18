'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const root=path.resolve(__dirname,'../..');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');

// Execute the real renderer and handoff against the active XML ancestry.
// The harness supplies Panorama panel primitives and records outbound calls.
function fixture(){
 const nodes={},requests=[];
 class Panel{
  constructor(type,parent,id=''){
   this.paneltype=type;this.parent=parent;this.id=id;this.children=[];this.style={};this.classes=new Set();this.events={};
   this.enabled=true;this.visible=true;this.text='';if(parent)parent.children.push(this);if(id)nodes[id]=this;
  }
  Children(){return this.children;} GetParent(){return this.parent;} IsValid(){return !this.deleted;}
  AddClass(value){this.classes.add(value);} RemoveClass(value){this.classes.delete(value);}
  BHasClass(value){return this.classes.has(value);} SetHasClass(value,on){on?this.AddClass(value):this.RemoveClass(value);}
  SetParent(parent){if(this.parent)this.parent.children=this.parent.children.filter(n=>n!==this);this.parent=parent;parent.children.push(this);}
  FindChildTraverse(id){if(this.id===id)return this;for(const node of this.children){const found=node.FindChildTraverse(id);if(found)return found;}return null;}
  SetPanelEvent(name,callback){this.events[name]=callback;} SetImage(uri){this.image=uri;} SetScaling(value){this.scaling=value;}
  MoveChildBefore(child,before){this.children=this.children.filter(n=>n!==child);this.children.splice(Math.max(0,this.children.indexOf(before)),0,child);}
  DeleteAsync(){this.deleted=true;if(this.parent)this.parent.children=this.parent.children.filter(n=>n!==this);for(const child of [...this.children])child.DeleteAsync();}
  RemoveAndDeleteChildren(){for(const child of [...this.children])child.DeleteAsync();}
  GetPositionWithinWindow(){let x=0,y=0;for(let n=this;n;n=n.parent){const at=String(n.style.position||'0 0').split(' ');x+=parseFloat(at[0])||0;y+=parseFloat(at[1])||0;}return{x,y};}
  get actuallayoutwidth(){return parseFloat(this.style.width)||0;} get actuallayoutheight(){return parseFloat(this.style.height)||0;}
 }
 const document=new Panel('Panel',null,'FixtureRoot');document.style.width='1920px';document.style.height='1080px';
 const stack=[document],xml=read('panorama/src/layout/custom_game/survival_hud.xml');
 for(const match of xml.matchAll(/<(\/?)(Panel|Button|Label|Image|ToggleButton|DOTAScenePanel|DOTAHeroImage|DOTAItemImage|DOTAAbilityImage)\b([^>]*?)(\/?)>/g)){
  if(match[1]){stack.pop();continue;}
  const attrs={};for(const attribute of match[3].matchAll(/([A-Za-z_][\w-]*)="([^"]*)"/g))attrs[attribute[1]]=attribute[2];
  const node=new Panel(match[2],stack.at(-1),attrs.id||'');for(const cls of (attrs.class||'').split(/\s+/).filter(Boolean))node.AddClass(cls);
  if(attrs.text)node.text=attrs.text;if(!match[4])stack.push(node);
 }
 const $=id=>document.FindChildTraverse(id.slice(1));$.GetContextPanel=()=>document;$.CreatePanel=(type,parent,id)=>new Panel(type,parent,id);
 $.Schedule=()=>1;$.CancelScheduled=()=>{};$.DispatchEvent=()=>{};
 const config={SurvivalUI:{Fit:()=>1}},env={$,
  GameUI:{CustomUIConfig:()=>config,GetCursorPosition:()=>[600,400]},
  GameEvents:{SendCustomGameEventToServer:(name,payload)=>requests.push({name,payload})}};
 const run=name=>vm.runInNewContext(read('panorama/src/scripts/custom_game/'+name+'.js'),env,{filename:name+'.js'});
 for(const name of ['common/item_resources','reward_presentation','common/tooltip_dismiss','black_lion_market','lottery_gw2_data','lottery_handoff_bb9968eef7'])run(name);
 const collect=(node,cls)=>[...(node.BHasClass(cls)?[node]:[]),...node.Children().flatMap(n=>collect(n,cls))];
 const icons=()=>[...collect(nodes.LotteryWindow,'LHTicket'),...collect(nodes.LotteryWindow,'LHDrawTicket')];
 for(const icon of icons())Object.assign(icon.style,{backgroundImage:'url("legacy_ticket.png")',opacityMask:'url("legacy_silhouette.svg")',washColor:'#f1cc72'});
 run('lottery_gw2');
 return{config,nodes,requests,collect,icons};
}
function pool(id){return{id,ticket_content_id:['map','cultivation'].includes(id)?'lottery_ticket':'special_lottery_ticket',tickets:23,unlocked:true};}
function snapshot(id,items=[]){return{selected_pool_id:id,selected_pool:pool(id),pools:['map','cultivation','dragon_knight','summer'].map(pool),items};}
function assertOriginalArt(node,uri){
 assert.equal(node.style.backgroundImage,'url("'+uri+'")');assert.equal(node.style.backgroundSize,'contain');
 assert.equal(node.style.backgroundPosition,'center');assert.equal(node.style.backgroundRepeat,'no-repeat');
 assert.equal(node.style.backgroundColor,'transparent');assert.equal(node.style.opacityMask,'none');assert.equal(node.style.washColor,'none');
 assert.equal(node.style.opacity,'1');assert.equal(node.style.saturation,'1');assert.equal(node.style.brightness,'1');
}

test('Ticket identities use the actual maintained registry and both special-ticket product identities share one contain image',()=>{
 const h=fixture(),resources=h.config.SurvivalItemResources,source=JSON.parse(read('data/ui/item_resources.json'));
 const normal=resources.Lookup('lottery_ticket'),special=resources.Lookup('special_lottery_ticket');
 assert.notEqual(normal.uri,special.uri,'Normal and special ticket art are distinguishable');
 for(const id of ['lottery_ticket','special_lottery_ticket','P001','video_p001','special_lottery_ticket_single','pay_special_lottery_ticket_single']){
  const row=resources.Lookup(id),maintained=source.items.find(entry=>entry.id===row.id);
  assert.equal(row.uri,maintained.uri);assert.equal(row.fit,'contain');assert.equal(maintained.fit,'contain');
  assert.deepEqual([...row.source_size],[1536,1024]);
  assert.equal(resources.Resolve(id),id==='lottery_ticket'?normal.uri:special.uri);
 }
 assert.equal(h.requests.length,0);
});

test('Every pool switch binds header, legacy header and both draw costs to the same untinted transparent ticket image',()=>{
 const h=fixture(),presentation=h.config.SurvivalPurpleLottery,resources=h.config.SurvivalItemResources;
 presentation.Open();assert.equal(h.icons().length,3,'The actual XML has one legacy balance and two draw-cost ticket controls');
 for(const id of ['map','dragon_knight','cultivation','summer','map']){
  const data=snapshot(id),unchanged=JSON.stringify(data),uri=resources.Resolve(data.selected_pool.ticket_content_id);
  h.config.LotteryHandoff.Ticket(data.selected_pool);presentation.Pools(data.pools,id);presentation.Snapshot(data);
  for(const icon of [...h.icons(),h.nodes.LotteryGW2TicketIcon])assertOriginalArt(icon,uri);
  assert.equal(h.nodes.LotteryGW2TicketBalance.text,'23');assert.equal(JSON.stringify(data),unchanged);
 }
 assert.equal(h.requests.length,0,'Presenting ticket artwork never sends a draw or purchase');
});

test('Actual reward previews and tooltip retain the shared contain fit instead of forcing the new wide ticket artwork to cover',()=>{
 const h=fixture(),presentation=h.config.SurvivalPurpleLottery,resources=h.config.SurvivalItemResources;
 const items=['lottery_ticket','special_lottery_ticket'].map(id=>({id,name:id,quality:'sr',description:'票图原样显示',owned_count:1}));
 presentation.Open();presentation.Pools(snapshot('map').pools,'map');presentation.Snapshot(snapshot('map',items));
 const previews=h.collect(h.nodes.LotteryGW2PreviewItems,'LotteryGW2PreviewIcon');assert.equal(previews.length,2);
 for(let i=0;i<previews.length;i++){
  assert.equal(previews[i].image,resources.Resolve(items[i]));assert.equal(previews[i].scaling,'stretch-to-fit-preserve-aspect');
 }
 presentation.Tooltip(items[1],previews[1]);
 const tooltip=h.collect(h.nodes.LotteryGW2TooltipIconStage,'LotteryGW2TooltipIcon');assert.equal(tooltip.length,1);
 assert.equal(tooltip[0].image,resources.Resolve('special_lottery_ticket'));assert.equal(tooltip[0].scaling,'stretch-to-fit-preserve-aspect');
 const original=h.config.SurvivalRewardPresentation.FillIcon;h.config.SurvivalRewardPresentation.FillIcon=undefined;
 presentation.Snapshot(snapshot('map',[{...items[0],owned_count:2}]));
 assert.equal(h.collect(h.nodes.LotteryGW2PreviewItems,'LotteryGW2PreviewIcon')[0].scaling,'stretch-to-cover-preserve-aspect','No shared helper preserves the existing cover fallback');
 h.config.SurvivalRewardPresentation.FillIcon=original;assert.equal(h.requests.length,0);
});

test('An unavailable registry clears previous ticket art without falling back to an independent hardcoded image',()=>{
 const h=fixture(),presentation=h.config.SurvivalPurpleLottery;
 presentation.Open();const data=snapshot('summer');presentation.Pools(data.pools,'summer');presentation.Snapshot(data);
 const resources=h.config.SurvivalItemResources;h.config.SurvivalItemResources=undefined;
 h.config.LotteryHandoff.Ticket(data.selected_pool);presentation.Snapshot(data);
 for(const icon of [...h.icons(),h.nodes.LotteryGW2TicketIcon]){
  assert.equal(icon.style.backgroundImage,'none');assert.equal(icon.style.opacityMask,'none');assert.equal(icon.style.washColor,'none');
 }
 h.config.SurvivalItemResources=resources;assert.equal(h.requests.length,0);
});
