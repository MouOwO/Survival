const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const dir='panorama/src/scripts/custom_game/';
const config={},notifications=[];
vm.runInNewContext(fs.readFileSync(dir+'ui_snapshot_cache.js','utf8'),{
 $:{Schedule(){},GetContextPanel(){return {}; }},GameUI:{CustomUIConfig:()=>config},
 GameEvents:{SendEventClientSide:(event,payload)=>notifications.push(payload)}
});
const guard=config.SurvivalActionResources;
const action={available:1,cost_wood:100,cost_gold:0,population:2};
guard.Update({wood:99,gold:0,population:0,max_population:2});assert.equal(guard.Check(action),'木材不足');
guard.Update({wood:100,gold:0,population:0,max_population:2});assert.equal(guard.Check(action),'');
assert.equal(guard.Check({...action,cost_gold:1}),'金币不足');
assert.equal(guard.Check({...action,population:3}),'人口不足');
assert.equal(guard.Check({...action,available:0,status_text:'需要研究所'}),'需要研究所');
guard.Update({wood:0,gold:0,population:0,max_population:0,debug_mode:1});assert.equal(guard.Check(action),'');
guard.Update({wood:0,gold:0,population:0,max_population:0});assert(guard.Reject(action));assert.equal(notifications.at(-1).message,'木材不足');
guard.Update({wood:1000,gold:1000,population:0,max_population:10});assert.equal(guard.Check({...action,can_afford:0}),'','current private wallet overrides stale advisory affordability');
const tooltip=fs.readFileSync(dir+'ability_tooltip.js','utf8');
const image={id:'AbilityImage',style:{brightness:'1',saturation:'1'},IsValid:()=>true};
const proxy={__survivalAbilityIndex:123,__survivalVisualAnchor:image,IsValid:()=>true};
let runtime={available:0};
const context={GameUI:{CustomUIConfig:()=>config},readTooltipTable:()=>runtime,selectedUnit:()=>1,
 externalAbilityHighlightTarget:()=>image,tooltipError:(...args)=>{throw Error(args.join(' '));}};
vm.runInNewContext(tooltip.slice(tooltip.indexOf('    function externalAbilityUnavailable('),tooltip.indexOf('    function acquireSelectiveTooltip(')),context);
context.setExternalProxyHighlight(proxy,true);assert.equal(image.style.brightness,'0.45');assert.equal(image.style.saturation,'0');
runtime={available:1};context.setExternalProxyHighlight(proxy,true);assert.equal(image.style.brightness,'1.25');
context.setExternalProxyHighlight(proxy,false);assert.equal(image.style.brightness,'1');assert.equal(image.style.saturation,'1');
context.setExternalProxyHighlight(proxy,true);runtime={available:0};context.setExternalProxyHighlight(proxy,false);
assert.equal(image.style.brightness,'0.45','locking while hovered stays gray after exit');
for (const code of ['research_queue_full', 'queued_max_level', 'queue_available']) {
 runtime={available:0,prerequisite_met:1,can_afford:0,resource_check_on_cast:1,research_status_code:code};
 context.setExternalProxyHighlight(proxy,true);
 assert.equal(image.style.saturation,'1.35',code+': queue and wallet state retain normal hover color');
 assert.equal(image.style.brightness,'1.25');
 context.setExternalProxyHighlight(proxy,false);
 assert.equal(image.style.saturation,'1');assert.equal(image.style.brightness,'1');
}
runtime={available:1,prerequisite_met:0};context.setExternalProxyHighlight(proxy,true);
assert.equal(image.style.saturation,'0','explicit missing prerequisite takes precedence over general availability');
context.setExternalProxyHighlight(proxy,false);
const blocks={},labels={};
for(const id of ['CustomAbilityCostRow','CustomAbilityGoldCostBlock','CustomAbilityWoodCostBlock'])blocks[id]={SetHasClass:(name,hidden)=>blocks[id].hidden=hidden};
const costs={runtime:{cost_wood:250,cost_gold:0},tooltipDefinition:{},byId:id=>blocks[id],setText:(id,value)=>labels[id]=value};
const start=tooltip.indexOf('        var goldCost = runtime.cost_gold'),end=tooltip.indexOf('        resetFieldRows(fields);',start);
vm.runInNewContext(tooltip.slice(start,end),costs);
assert.equal(blocks.CustomAbilityWoodCostBlock.hidden,false);assert.equal(labels.CustomAbilityWoodCost,250);
assert.equal(blocks.CustomAbilityGoldCostBlock.hidden,true);
costs.runtime={cost_wood:0,cost_gold:40};vm.runInNewContext(tooltip.slice(start,end),costs);
assert.equal(blocks.CustomAbilityGoldCostBlock.hidden,false);assert.equal(labels.CustomAbilityGoldCost,40);assert.equal(blocks.CustomAbilityWoodCostBlock.hidden,true);
costs.runtime={cost_wood:0,cost_gold:0};vm.runInNewContext(tooltip.slice(start,end),costs);assert.equal(blocks.CustomAbilityCostRow.hidden,true);
console.log('ACTION_RESOURCES_AND_TOOLTIP_PASS: fresh wallet, wood/gold/population/debug, prerequisite shading, unlock/lock during hover, nongated cost row and zero-gold hiding');
