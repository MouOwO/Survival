const fs=require('fs'),vm=require('vm'),assert=require('assert');
const cfg={},root={actuallayoutwidth:1920,actuallayoutheight:1080,GetParent:()=>null,GetPositionWithinWindow:()=>({x:0,y:0})};
const parent={...root,actualuiscale_x:1,actualuiscale_y:1,GetParent:()=>root};
let x=600;const source={actuallayoutwidth:116,__survivalWindowWidth:58,GetParent:()=>root,GetPositionWithinWindow:()=>({x,y:900})};
const tooltip={style:{},GetParent:()=>parent};let schedules=0;
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/tooltip_position.js','utf8'),{GameUI:{CustomUIConfig:()=>cfg},$:{Schedule:()=>schedules++}});
for(const height of [80,350,120,260]){tooltip.actuallayoutheight=height;cfg.SurvivalTooltipPosition.PlaceAbilityAbove(tooltip,source,337);assert.equal(tooltip.style.marginBottom,'185px');assert.equal(tooltip.style.verticalAlign,'bottom');}
const oldX=tooltip.style.position;x=900;cfg.SurvivalTooltipPosition.PlaceAbilityAbove(tooltip,source,337);assert.notEqual(oldX,tooltip.style.position);assert.equal(tooltip.style.marginBottom,'185px');assert.equal(schedules,0,'position must settle synchronously');
let created=0;class Panel{constructor(){this.style={};this.visible=true;}AddClass(){}SetImage(v){this.image=v;}}
const env={$:{CreatePanel:()=>{created++;return new Panel();}},propertyIcon:label=>label==='attack'?{type:'item',name:'item_broadsword'}:null,localizedFieldLabel:v=>v,localizedFieldValue:(_,v)=>v};
const code=fs.readFileSync('panorama/src/scripts/custom_game/ability_tooltip.js','utf8');
vm.runInNewContext(code.slice(code.indexOf('    function addField('),code.indexOf('    function render(')),env);
const fields={};env.addField(fields,'attack',12);env.addField(fields,'speed',15);const firstCreated=created,firstRow=fields.__fieldRows[0];
for(let i=0;i<10;i++){fields.__fieldCursor=0;fields.__fieldRows.forEach(r=>r.visible=false);env.addField(fields,'attack',i);}
assert.equal(created,firstCreated);assert.strictEqual(firstRow,fields.__fieldRows[0]);assert(!fields.__fieldRows[1].visible);assert.equal(firstRow.__right.text,'9');
const pending=[],tip={owner:'selective_proxy',classes:new Set(),style:{},BHasClass(c){return this.classes.has(c)},AddClass(c){this.classes.add(c)},RemoveClass(c){this.classes.delete(c)}};tip.__survivalTooltipOwner='selective_proxy';
const fadeEnv={setExternalProxyHighlight:()=>{},activeSourcePanel:{},externalHoverExitSerial:0,nativeTooltipSuppressionSerial:0,activeAbilityIndex:1,activeAbilityName:'test',byId:()=>tip,selectiveTooltipOwner:'selective_proxy',tooltipAnimationSerial:0,tooltipFadeDuration:.1,tooltipAnimationFrame:.016,scheduleActive:(d,f)=>pending.push(f),releaseSelectiveTooltip:()=>{tip.__survivalTooltipOwner='';}};
vm.runInNewContext(code.slice(code.indexOf('    function hideCustomTooltip('),code.indexOf('    function showNativeAbilityTooltip(')),fadeEnv);
fadeEnv.hideCustomTooltip();assert(tip.BHasClass('FadingOut'));
fadeEnv.tooltipAnimationSerial++;tip.RemoveClass('FadingOut');pending.shift()();assert(!tip.BHasClass('Hidden'),'old fade must not hide newly shown ability');
fadeEnv.hideCustomTooltip();pending.shift()();assert(tip.BHasClass('Hidden'));assert.equal(tip.visible,undefined,'hiding must not collapse panel through visible property');
console.log('ABILITY_TOOLTIP_STABILITY_PASS: fixed bottom across heights, synchronous skill switch, pooled fields, stale hide cancelled');
