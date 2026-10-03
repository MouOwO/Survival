const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
const code=source.slice(source.indexOf('    function buildingPresentation('),source.indexOf('    function mirror()'));
const geometry=require('../panorama/src/scripts/custom_game/geometry_remaining_5d5c1152eb.js');
let snapshot={entindex:1,absolute_level:4,armor:60,attack_max:1200,building_stat_details:{armor_bonus:10,armor_pct:20,health_bonus:2500,health_pct:50,attack_bonus:200,attack_pct:20}},multi=false;
const nodes={},natives={},slices={},slots=[];
function panel(id){return {id,style:{},text:'',visible:true};}
for(const id of ['HandoffName','HandoffNameBounds','HandoffBuildingTitle','HandoffBuildingTitleBounds','HandoffHeroBase','HandoffPortraitFrame','HandoffNamePlate','HandoffInventoryBase','HandoffLevelPlate','HandoffLevelBounds','HandoffBuildingLevel','HandoffBuildingSummary','HandoffBuildingBonus','HandoffBuildingHealthBonus','HandoffBuildingPercent','HandoffBuildingHealthPercent'])nodes[id]=panel(id);
for(const type of ['hp','mp'])for(const suffix of ['_track','_fill','_valueBounds'])nodes['Handoff_'+type+suffix]=panel(type+suffix);
for(const id of ['PortraitGroup','inventory','inventory_composition_layer_container'])natives[id]=panel(id);
for(const id of ['HandoffCombatPlate','HandoffAttributesPlate'])slices[id]=panel(id);
for(let i=0;i<6;i++)slots.push(panel('slot'+i));
const sources={CombatArmorValue:{text:'60'},CombatAttackValue:{text:'1200'},SurvivalHeroLevel:{text:'4'}};
const env={nodes,slices,slotFrames:slots,assets:{hp_fill:{file:"test_hp_fill.png"}},geometry:geometry(1920,1080,4,true),cfg:{HandoffCombat:{Snapshot:()=>snapshot}},selectedUnit:()=>1,ctx:{FindChildTraverse:id=>sources[id]},native:id=>natives[id],valid:p=>!!p,
 style:(p,v)=>{if(p)Object.assign(p.style,v);},place:(p,x,y,w,h)=>{if(p)p.rect={x,y,w,h};},text:(id,value)=>nodes[id].text=String(value),compact:n=>String(n)};
vm.createContext(env);vm.runInContext(code,env);
function expectBuilding(){for(const p of Object.values(natives))assert.equal(p.style.visibility,'collapse',p.id);for(const p of slots)assert.equal(p.style.visibility,'collapse');assert.equal(nodes.HandoffLevelPlate.visible,false);assert.equal(nodes.HandoffLevelBounds.visible,false);assert.equal(nodes.Handoff_mp_track.style.visibility,'collapse');assert.equal(nodes.HandoffPortraitFrame.style.visibility,'collapse');}
nodes.HandoffName.text='Arrow Tower LV4';env.buildingPresentation({building:true,tower:true},false);expectBuilding();assert.equal(nodes.HandoffName.text,'Arrow Tower');assert.equal(nodes.HandoffBuildingTitle.text,'Arrow Tower');assert.equal(nodes.HandoffBuildingTitleBounds.rect.y,env.geometry.y-50*env.geometry.scale);assert.equal(nodes.HandoffNameBounds.style.visibility,'collapse');assert.equal(nodes.HandoffBuildingLevel.style.visibility,'collapse');assert.equal(nodes.Handoff_hp_track.style.visibility,'collapse');assert.equal(nodes.HandoffBuildingLevel.text,'LV4');assert.equal(nodes.HandoffBuildingLevel.rect.y,5);assert(nodes.HandoffBuildingSummary.text.includes('1000'));assert(nodes.HandoffBuildingBonus.text.includes('+200') && nodes.HandoffBuildingPercent.text.includes('20%'));
nodes.HandoffName.text='Arrow Tower 1-1';env.buildingPresentation({building:true,tower:true},false);assert.equal(nodes.HandoffName.text,'Arrow Tower 1-1');assert(!nodes.HandoffBuildingBonus.text.includes('%'));
snapshot.route_level=2;env.buildingPresentation({building:true,tower:true},false);assert.equal(nodes.HandoffBuildingLevel.text,'LV2','tower route level is its current displayed stage level');
env.buildingPresentation({building:true,wall:true},false);expectBuilding();assert.equal(nodes.Handoff_hp_track.style.visibility,'visible');assert(nodes.HandoffBuildingLevel.rect.y+nodes.HandoffBuildingLevel.rect.h<nodes.Handoff_hp_track.rect.y);assert(nodes.HandoffBuildingSummary.text.includes('50'));assert(nodes.HandoffBuildingBonus.text.includes('+10') && nodes.HandoffBuildingPercent.text.includes('20%'));assert(nodes.HandoffBuildingHealthBonus.text.includes('+2500'));
env.buildingPresentation({building:true},false);expectBuilding();assert.equal(nodes.Handoff_hp_track.style.visibility,'collapse');assert.equal(nodes.HandoffBuildingSummary.style.visibility,'collapse');assert.equal(nodes.HandoffBuildingHealthBonus.style.visibility,'collapse');
snapshot=null;env.buildingPresentation({building:true,wall:true},false);assert(!nodes.HandoffBuildingHealthBonus.text.includes('2500'),'old selected building bonuses cannot leak');
for(let i=0;i<8;i++) {env.buildingPresentation({building:true,wall:i%2===0},false);env.buildingPresentation({building:false},false);for(const p of Object.values(natives))assert.equal(p.style.visibility,'visible');for(const p of slots)assert.equal(p.style.visibility,'visible');assert.equal(nodes.HandoffLevelPlate.visible,true);assert.equal(nodes.Handoff_hp_track.style.visibility,'visible');assert.equal(nodes.Handoff_mp_track.style.visibility,'visible');assert.equal(nodes.HandoffNameBounds.rect.x,34);}
env.buildingPresentation({building:false},true);assert.equal(nodes.HandoffLevelPlate.visible,false);
for(const [w,h] of [[1280,720],[1920,1080],[2560,1440]])for(const count of [0,4,10,16,32]){
 const b=geometry(w,h,count,true),hero=geometry(w,h,count);
 assert.equal(b.heroWidth,0);assert(b.width<hero.width);assert(b.x>=0 && b.x+b.width*b.scale<=w);assert.equal(b.inventoryX,b.width);assert(b.centerWidth>=800);assert.equal(hero.heroWidth,493);
}
natives.multiunit=panel('multiunit');natives.multiunit.style.opacity='1';natives.multiunit.hittest=true;natives.multiunit.hittestchildren=true;
env.buildingPresentation({building:true},true);assert.equal(natives.multiunit.style.opacity,'0');assert.equal(natives.multiunit.hittest,false);
env.buildingPresentation({building:false},true);assert.equal(natives.multiunit.style.opacity,'1');assert.equal(natives.multiunit.hittest,true);
console.log('BUILDING_HUD_PASS: wall health/armor/bonuses, tower damage/bonus, one level location, other buildings, no portrait/inventory/mana, stale snapshot, repeated hero restoration, multi and 3 viewport sizes');
// Resource trees are compact targets, not friendly buildings or heroes.
natives.AbilitiesAndStatBranch=panel('AbilitiesAndStatBranch');
snapshot={entindex:1,is_resource_tree:1,level:3,max_level:100,armor:180,
 building_stat_details:{armor_bonus:90,armor_pct:50},display_attack_bonus:500};
env.geometry=geometry(1920,1080,0,false,true);
nodes.HandoffName.text='Resource tree 3/100';
env.buildingPresentation({building:false,tree:true,combat:false,attributes:false},false);
assert.equal(nodes.HandoffBuildingTitle.text,'\u5927\u6811  LV3 / 100');
assert.equal(nodes.HandoffBuildingSummary.text,'\u62a4\u7532\uff1a180','resource defense must not subtract player bonuses');
assert.equal(nodes.Handoff_hp_track.style.visibility,'visible');
assert.equal(nodes.Handoff_mp_track.style.visibility,'collapse');
assert.equal(nodes.Handoff_hp_fill.style.backgroundImage,'none');
assert(nodes.Handoff_hp_fill.style.backgroundColor.includes('#e4473d'));
assert.equal(natives.PortraitGroup.style.visibility,'collapse');
assert.equal(natives.inventory.style.visibility,'collapse');
assert.equal(natives.AbilitiesAndStatBranch.style.visibility,'collapse');
for(const id of ['HandoffBuildingBonus','HandoffBuildingPercent','HandoffBuildingHealthBonus','HandoffBuildingHealthPercent'])assert.equal(nodes[id].style.visibility,'collapse',id);
assert(nodes.Handoff_hp_track.rect.y+44<env.geometry.height-23);
assert(nodes.HandoffBuildingSummary.rect.y+44<env.geometry.height-23);
snapshot.armor=100;env.buildingPresentation({tree:true},false);assert.equal(nodes.HandoffBuildingSummary.text,'\u62a4\u7532\uff1a100');
env.buildingPresentation({tree:true},true);assert.equal(nodes.HandoffBuildingTitleBounds.style.visibility,'collapse');assert.equal(nodes.HandoffBuildingSummary.style.visibility,'collapse');
env.geometry=geometry(1920,1080,4,false);env.buildingPresentation({building:false},false);
assert.equal(nodes.Handoff_hp_fill.style.backgroundColor,'transparent');assert(nodes.Handoff_hp_fill.style.backgroundImage.includes('test_hp_fill.png'));
assert.equal(natives.PortraitGroup.style.visibility,'visible');assert.equal(natives.inventory.style.visibility,'visible');assert.equal(natives.AbilitiesAndStatBranch.style.visibility,'visible');assert.equal(nodes.Handoff_mp_track.style.visibility,'visible');assert.equal(nodes.HandoffBuildingSummary.style.visibility,'collapse');
for(const [w,h] of [[1280,720],[1920,1080],[2560,1440]]){const t=geometry(w,h,0,false,true);assert.equal(t.height,185);assert.equal(t.heroWidth,0);assert(t.x>=0&&t.x+t.width*t.scale<=w);assert(t.y+t.height*t.scale<=h);}
console.log('RESOURCE_TREE_HUD_PASS: live defense, no inherited bonuses, compact bounds, selection restoration');

// Utility buildings fit one full-sized icon row and retain a comfortable width.
for(const [w,h] of [[1280,720],[1920,1080],[2560,1440]]) {
 for(const count of [1,2,4,10]) {
  const compact=geometry(w,h,count,true,false,{building:true,wall:false,tower:false});
  const wall=geometry(w,h,count,true,false,{building:true,wall:true});
  const tower=geometry(w,h,count,true,false,{building:true,tower:true});
  assert.equal(compact.height,205);
  assert.equal(compact.slot,116);
  assert(compact.centerWidth>=800);
  assert(23+38+compact.slot+20<=compact.height,'icon row has bottom padding');
  for(const g of [compact,wall,tower]) {
   assert(Math.abs(g.y+g.height*g.scale-(h-6))<0.001,'all building panels stay bottom anchored');
   assert(g.x>=0 && g.x+g.width*g.scale<=w);
  }
  assert.equal(wall.height,330);assert.equal(tower.height,330);
 }
}
assert(source.includes('presentation.tree,presentation)'),'live HUD supplies building presentation');
assert(source.includes('g.heroWidth,g.height,selectedUnit()'),'height changes trigger native and decorative reflow');
console.log('COMPACT_UTILITY_BUILDINGS_PASS: one icon row, minimum width, bottom anchoring, combat building space, three viewport sizes');

for(const lumberjack of [false,true])for(const multi of [false,true]){
 const shown={worker:true,lumberjack,repairer:!lumberjack,multi};
 env.geometry=geometry(1920,1080,1,false,false,shown);
 nodes.HandoffName.text=lumberjack?'Worker LV4':'Repairer';
 env.buildingPresentation(shown,multi);
 for(const id of ['PortraitGroup','inventory','inventory_composition_layer_container'])assert.equal(natives[id].style.visibility,id==='PortraitGroup'&&lumberjack&&multi?'visible':'collapse');
 assert.equal(natives.multiunit.hittest,lumberjack&&multi);
 for(const type of ['hp','mp'])for(const suffix of ['_track','_fill','_valueBounds'])assert.equal(nodes['Handoff_'+type+suffix].style.visibility,'collapse');
 assert.equal(nodes.HandoffLevelPlate.visible,false);
 assert.equal(nodes.HandoffBuildingTitle.text,nodes.HandoffName.text);
 assert.equal(nodes.HandoffBuildingTitleBounds.style.visibility,'visible');
 assert.equal(natives.AbilitiesAndStatBranch.style.visibility,'visible');
 assert.equal(env.geometry.height,lumberjack&&multi?330:lumberjack?260:205);
 assert.equal(env.geometry.heroWidth,lumberjack&&multi?320:0);
 assert.equal(env.geometry.inventoryX,env.geometry.width);
}
env.buildingPresentation({attributes:true,combat:true},false);
assert.equal(natives.PortraitGroup.style.visibility,'visible');
assert.equal(natives.inventory.style.visibility,'visible');
assert.equal(nodes.Handoff_mp_track.style.visibility,'visible');
const workerEnv={nodes,place:env.place,style:env.style,stats:[['attack'],['armor'],['attack_speed']]};
for(const stat of workerEnv.stats)for(const prefix of ['HandoffStatIcon_','HandoffStatName_','HandoffStat_','HandoffStatBonus_','HandoffStatPercent_'])nodes[prefix+stat[0]]=panel(prefix+stat[0]);
vm.createContext(workerEnv);vm.runInContext(source.slice(source.indexOf('    function layoutStats('),source.indexOf('    ["hp","mp"].forEach')),workerEnv);
const wg=geometry(1920,1080,1,false,false,{worker:true,lumberjack:true});workerEnv.layoutStats(wg);
for(const stat of ['attack','attack_speed'])for(const prefix of ['HandoffStatName_','HandoffStat_']){
 const r=nodes[prefix+stat].rect;assert(r.x>=0 && r.x+r.w<=wg.width);assert(r.y>=177 && r.y+r.h<wg.height);
}
console.log('COMPACT_WORKER_HUD_PASS: single portrait hidden, lumberjack multi grid restored, inventory/health/mana hidden, queue title and stat bounds');

// Monster selection uses hero visual metrics but removes all inventory layers.
for(const [w,h] of [[1280,720],[1920,1080],[2560,1440]])for(const count of [0,1,4,10]){
 const heroGeometry=geometry(w,h,count,false,false,{attributes:true});
 const monsterGeometry=geometry(w,h,count,false,false,{monster:true});
 assert.equal(monsterGeometry.width,monsterGeometry.attributeX);
 for(const key of ['scale','heroWidth','portraitSize','centerWidth','barWidth','x','y'])assert.equal(monsterGeometry[key],heroGeometry[key],key);
 assert(monsterGeometry.x+monsterGeometry.width*monsterGeometry.scale<=w);
 env.geometry=monsterGeometry;
 for(const multi of [false,true]){
  env.buildingPresentation({monster:true,combat:true,attributes:false},multi);
  for(const id of ['inventory','inventory_composition_layer_container'])assert.equal(natives[id].style.visibility,'collapse',id);
  assert.equal(nodes.HandoffInventoryBase.style.visibility,'collapse');
  assert.equal(slices.HandoffAttributesPlate.style.visibility,'collapse');
  assert.equal(slices.HandoffCombatPlate.style.visibility,'visible');
  assert.equal(natives.PortraitGroup.style.visibility,'visible');
  assert.equal(nodes.HandoffLevelPlate.visible,false);
  for(const slot of slots)assert.equal(slot.style.visibility,'collapse');
  for(const suffix of ['_track','_fill','_valueBounds']){
   assert.equal(nodes['Handoff_hp'+suffix].style.visibility,'visible');
   assert.equal(nodes['Handoff_mp'+suffix].style.visibility,'collapse');
  }
 }
 env.geometry=heroGeometry;env.buildingPresentation({attributes:true,combat:true},false);
 for(const id of ['inventory','inventory_composition_layer_container'])assert.equal(natives[id].style.visibility,'visible');
 assert.equal(nodes.HandoffInventoryBase.style.visibility,'visible');
 assert.equal(slices.HandoffAttributesPlate.style.visibility,'visible');
 assert.equal(nodes.Handoff_mp_track.style.visibility,'visible');
 assert.equal(nodes.HandoffLevelPlate.visible,true);
 for(const slot of slots)assert.equal(slot.style.visibility,'visible');
}
console.log('MONSTER_HUD_PASS: no inventory/backplates/slots/mana/attributes/level; shared hero metrics, reduced bounds, hero recovery');
