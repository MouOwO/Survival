const fs=require('fs'),vm=require('vm'),assert=require('assert');
const src=fs.readFileSync('panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js','utf8');
const nodes={},dispatch=[];
function make(type,parent,id,hit=false){const p={id,parent,style:{},hittest:hit,hittestchildren:hit,text:'',events:{},AddClass(){},GetParent(){return this.parent;},SetPanelEvent(n,f){this.events[n]=f;}};if(id)nodes[id]=p;return p;}
const host=make('Panel',null,'host',true),snapshot={building_id:'arrow_tower',building_stat_details:{attack_technology_flat:40,attack_technology_pct:.5,attack_permanent_flat:20,attack_permanent_pct:0,attack_talent_pct:0}};
const env={host,nodes,cfg:{HandoffCombat:{Snapshot:()=>snapshot}},create:make,art:(p,id)=>make('Image',p,id),label:(p,id)=>make('Label',p,id),centered:(p,id)=>make('Label',make('Panel',p,id+'Bounds'),id),style:(p,v)=>Object.assign(p.style,v),place(){},stats:[['attack','a'],['armor','b'],['attack_speed','c'],['strength','d'],['agility','e'],['intelligence','f']],selectedUnit:()=>1,compact:String,$:{DispatchEvent:(...v)=>dispatch.push(v)}};
vm.createContext(env);
vm.runInContext(src.slice(src.indexOf('    function tooltip('),src.indexOf('    function notice(')),env);
vm.runInContext(src.slice(src.indexOf('    var bottom=create('),src.indexOf('    for(var i=0;i<6;i++)slotFrames.push')),env);
// Execute the real layout statement which used to disable all child input.
vm.runInContext(src.match(/bottom\.hittestchildren=(?:true|false);/)[0],env);
for(const id of ['HandoffBuildingBonus','HandoffBuildingPercent','HandoffBuildingHealthBonus','HandoffBuildingHealthPercent','HandoffStatBonus_attack','HandoffStatPercent_attack']){
 const p=nodes[id];assert(p.hittest,id);for(let a=p.parent;a;a=a.parent)assert(a.hittestchildren,id+' ancestor '+a.id);
 p.events.onmouseover();assert.equal(dispatch.at(-1)[0],'DOTAShowTextTooltip');p.events.onmouseout();assert.equal(dispatch.at(-1)[0],'DOTAHideTextTooltip');
}
assert.equal(nodes.HandoffBuildingPercent.style.color,'#f08078');assert.equal(nodes.HandoffBuildingBonus.style.color,'#8fe080');
assert(!env.buildingBonusHelp().includes('???'));assert(env.buildingBonusHelp().includes('40'));assert(env.buildingBonusHelp().includes('0.5%'));
assert.equal(nodes.Handoff_hp_track.hittest,false);assert.equal(nodes.HandoffPortraitFrame.hittest,false,'decoration cannot block skill/portrait input');
const sideIds=['HUDSkinMinimap','GlyphScanContainer','RoshanTimerContainer','TormentorTimerContainer'];
const map=make('Panel',null,'minimap_container'),mini=make('Panel',map,'minimap_block',true),live=make('DOTAMinimap',mini,'minimap',true);
sideIds.forEach(id=>make('Panel',map,id,true));map.FindChildTraverse=id=>nodes[id];
Object.assign(env,{native:id=>nodes[id],valid:p=>!!p});
vm.runInContext(src.slice(src.indexOf('    function layoutMinimap('),src.indexOf('    function nativeLayout(')),env);
for(let i=0;i<3;i++){nodes.GlyphScanContainer.style.visibility='visible';env.layoutMinimap({minimapSize:220});assert.equal(nodes.GlyphScanContainer.style.visibility,'collapse');}
assert.equal(live.hittest,true);assert.equal(live.hittestchildren,true);assert.equal(map.style.width,'226px');assert.equal(map.style.backgroundImage,'none');
assert(!sideIds.includes('SurvivalMinimapShortcuts'));
console.log('BONUS_HIT_PATH_AND_MINIMAP_PASS: both colored values hover through every parent; ornaments stay noninteractive; actual source text; live map input intact; native side decorations stay hidden');
