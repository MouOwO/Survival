const fs=require('fs'),vm=require('vm'),assert=require('assert');
const bars={},tasks=new Map(),listeners=new Map(),config={},table={};
let nextTask=0,nextListener=0,clock=0,valid=true,alive=true,dormant=false;
let origin=[0,0,0],name='hero',failOrigin=false,containerReady=false;
let screenX=100,screenY=100,healthBarOffset=190,offsetThrows=false,projectedHeight;
function panel(id){return {id,style:{},actualuiscale_x:1,actualuiscale_y:1,
    actuallayoutwidth:1920,actuallayoutheight:1080,
    AddClass(){},SetHasClass(){},IsValid(){return !this.deleted},DeleteAsync(){this.deleted=true},
    GetPositionWithinWindow(){return this.windowOffset||{x:0,y:0}}}}
const container=panel('SurvivalHeroWorldHealthBars'),context=panel('context');
const $=()=>containerReady?container:null;
$.GetContextPanel=()=>context;
$.CreatePanel=(_,parent,id)=>{const p=panel(id);if(id)bars[id]=p;return p};
$.Schedule=(_,fn)=>{const id=++nextTask;tasks.set(id,fn);return id};
$.CancelScheduled=id=>tasks.delete(id);
const sandbox={
    $,GameUI:{CustomUIConfig:()=>config},Players:{GetTeam:()=>2},
    Game:{GetGameTime:()=>clock,GetLocalPlayerID:()=>0,WorldToScreenX:()=>screenX,
        WorldToScreenY:(_,y,z)=>{projectedHeight=z;return screenY+z-190}},
    Entities:{IsValidEntity:()=>valid,IsAlive:()=>alive,IsDormant:()=>dormant,
        GetAbsOrigin:()=>{if(failOrigin)throw Error('entity removed during frame');return origin},
        GetUnitName:()=>name,GetHealthBarOffset:()=>{if(offsetThrows)throw Error('offset temporarily unavailable');return healthBarOffset}},
    CustomNetTables:{GetAllTableValues:()=>table,
        SubscribeNetTableListener:(_,fn)=>{const id=++nextListener;listeners.set(id,fn);return id},
        UnsubscribeNetTableListener:id=>listeners.delete(id)}
};
const source=fs.readFileSync('panorama/src/scripts/custom_game/hero_world_health_bar.js','utf8');
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/world_health_bar_anchor.js','utf8'),sandbox);
vm.runInNewContext(source,sandbox);
const state={entindex:42,health:50,max_health:100,alive:1,team:2,unit_name:'hero'};
const bar=()=>bars.SurvivalHeroWorldHealth_unit_42;
const tick=()=>{const due=[...tasks.values()];tasks.clear();due.forEach(fn=>fn())};
const emit=value=>{table.unit_42=value;[...listeners.values()].forEach(fn=>fn('survival_hero_health_bar','unit_42',value))};
const send=value=>emit({...state,...value});
const width=()=>parseFloat(bar().__fill.style.width);
send({});tick();assert.equal(bar(),undefined,'a missing XML child is retried without creating orphan panels');
assert.equal(tasks.size,1,'missing child retains one recovery loop');
containerReady=true;tick();assert.equal(bar().style.visibility,'visible');
assert.equal(width(),50);
assert.equal(bar().style.position,'69.00px 74.00px 0px','custom health bar uses the shared projection anchor');
const anchor=config.SurvivalWorldHealthBarAnchor.Project(42,origin,container);
assert.equal(anchor.left,69);assert.equal(anchor.top,74);
assert.equal(anchor.width,62);assert.equal(anchor.height,11);
assert.equal(anchor.screen_left,69);assert.equal(anchor.screen_top,74);
healthBarOffset=330;tick();assert.equal(projectedHeight,330);
assert.equal(bar().style.position,'69.00px 214.00px 0px','a cosmetic-specific offset moves the health bar with the caption');
for(const offset of [-1,0,NaN]){
    healthBarOffset=offset;tick();assert.equal(projectedHeight,190);
    assert.equal(bar().style.position,'69.00px 74.00px 0px','invalid native offsets share the same fallback');
}
offsetThrows=true;tick();assert.equal(projectedHeight,190);
assert.equal(bar().style.visibility,'visible','temporary offset errors do not hide the health bar');
offsetThrows=false;
const offsetAPI=sandbox.Entities.GetHealthBarOffset;
delete sandbox.Entities.GetHealthBarOffset;tick();assert.equal(projectedHeight,190);
sandbox.Entities.GetHealthBarOffset=offsetAPI;healthBarOffset=190;
screenX=600;screenY=400;
container.actualuiscale_x=0.75;container.actualuiscale_y=0.5;
container.windowOffset={x:90,y:45};tick();
assert.equal(bar().style.position,'649.00px 684.00px 0px','window offset and unequal scales use the shared math');
const scaledAnchor=config.SurvivalWorldHealthBarAnchor.Project(42,origin,container);
assert.equal(scaledAnchor.scale_x,0.75);assert.equal(scaledAnchor.scale_y,0.5);
assert.equal(scaledAnchor.screen_left,576.75);assert.equal(scaledAnchor.screen_top,387);
screenX=-1;tick();assert.equal(bar().style.visibility,'collapse','negative world projections hide bars');
assert.equal(config.SurvivalWorldHealthBarAnchor.Project(42,origin,container),null);
screenX=NaN;tick();assert.equal(bar().style.visibility,'collapse','non-finite projections hide bars');
assert.equal(config.SurvivalWorldHealthBarAnchor.Project(42,origin,container),null);
screenX=100;screenY=100;container.actualuiscale_x=container.actualuiscale_y=1;
container.windowOffset={x:0,y:0};tick();assert.equal(bar().style.visibility,'visible');
// Five future one-second hits kill at t=5. The lethal hit overkills; the bar
// must reach zero at t=5, not at 4.25s and not trail the actual death by 0.9s.
let hp=650, next=125;
for(let second=0;second<5;second++){
    clock=second;
    send({health:hp,max_health:1000,laser_forecast:[{start:second,due:second+1,fraction:next/1000}]});
    assert(Math.abs(width()-hp/10)<0.001);
    clock=second+0.5;tick();
    assert(Math.abs(width()-(hp-Math.min(hp,next)*0.5)/10)<0.001);
    const paused=width();tick();assert.equal(width(),paused,'pause freezes animation');
    clock=second+0.99;tick();assert(width()>0,'no premature empty bar');
    clock=second+1;tick();hp=Math.max(0,hp-next);next+=5;
    assert(Math.abs(width()-hp/10)<0.001);
}
assert.equal(width(),0,'display empty at the lethal tick, before death packet');
send({health:0,alive:0});assert.equal(bar().style.visibility,'collapse');
clock=10;send({health:50,laser_forecast:[{start:10,due:11,fraction:0.2}]});
clock=10.5;tick();assert.equal(width(),40);
send({health:50,laser_forecast:[]});assert.equal(width(),50,'stopping cancels unearned forecast');
send({health:80});assert.equal(width(),80,'healing is immediate');
send({health:60,max_health:120});assert.equal(width(),50,'maximum health correction');
clock=20;send({health:30,laser_forecast:{'1':{start:20,due:21,fraction:0.2},'2':{start:20,due:21,fraction:0.2}}});
clock=20.5;tick();assert.equal(width(),15,'concurrent beams share remaining health');
clock=21;tick();assert.equal(width(),0);
clock=21.2;tick();assert.equal(width(),30,'missed hit cannot extrapolate forever');
send({});tick();
alive=false;tick();assert.equal(bar().style.visibility,'collapse');
alive=true;dormant=true;tick();assert.equal(bar().style.visibility,'collapse');
dormant=false;origin=[0,0,-10000];tick();assert.equal(bar().style.visibility,'collapse');
origin=[0,0,0];name='thinker';tick();assert.equal(bar().style.visibility,'collapse');
name='hero';tick();assert.equal(bar().style.visibility,'visible');
failOrigin=true;tick();assert.equal(bar().style.visibility,'collapse');
assert.equal(tasks.size,1,'only the existing frame loop is used');
failOrigin=false;origin=[10,20,0];tick();assert.equal(bar().style.visibility,'visible');
valid=false;tick();assert(bar().deleted);
valid=true;send({});tick();
emit({removed:1});assert(bar().deleted,'construction/removal packets discard the displayed bar');
send({});tick();assert.equal(bar().style.visibility,'visible','completion state recreates the removed bar');
const previousBar=bar();
vm.runInNewContext(source,sandbox);
assert(previousBar.deleted,'hot reload deletes the prior instance panels');
assert.equal(tasks.size,1,'hot reload keeps one animation loop');
assert.equal(listeners.size,1,'hot reload keeps one nettable listener');
tick();assert.equal(bar().style.visibility,'visible','hot reload restores replicated state without waiting for another packet');
assert.equal(width(),50);
assert.equal(tasks.size,1);
assert.equal(typeof config.SurvivalWorldHealthBars.DebugSnapshot,'function');
context.deleted=true;tick();
assert.equal(tasks.size,0,'a disposed root cancels the frame loop');
assert.equal(listeners.size,0,'a disposed root unsubscribes its nettable listener');
assert(bar().deleted,'a disposed root clears its panels');
config.SurvivalWorldHealthBars.Stop();assert.equal(tasks.size,0,'Stop remains safe after disposal');
console.log('WORLD_HEALTH_BAR_PASS: shared anchor, scale/window offsets, fallback, delayed XML child, hot reload, 5s lethal forecast, pause, entity lifecycle');
