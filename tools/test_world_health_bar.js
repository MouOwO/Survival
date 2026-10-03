const fs=require('fs'),vm=require('vm'),assert=require('assert');
const bars={},tasks=[];
let callback,clock=0,valid=true,alive=true,dormant=false,origin=[0,0,0],name='hero',failOrigin=false;
function panel(id){return {style:{},actualuiscale_x:1,actualuiscale_y:1,
    AddClass(){},SetHasClass(){},IsValid(){return !this.deleted},DeleteAsync(){this.deleted=true}}}
const container=panel();
const $=()=>container;
$.CreatePanel=(_,parent,id)=>{const p=panel(id);if(id)bars[id]=p;return p};
$.Schedule=(_,fn)=>tasks.push(fn);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/hero_world_health_bar.js','utf8'),{
    $,Players:{GetTeam:()=>2},Game:{GetGameTime:()=>clock,GetLocalPlayerID:()=>0,WorldToScreenX:()=>100,WorldToScreenY:()=>100},
    Entities:{IsValidEntity:()=>valid,IsAlive:()=>alive,IsDormant:()=>dormant,GetAbsOrigin:()=>{if(failOrigin)throw Error('entity removed during frame');return origin},GetUnitName:()=>name},
    CustomNetTables:{GetAllTableValues:()=>({}),SubscribeNetTableListener:(_,fn)=>callback=fn}
});
const state={entindex:42,health:50,max_health:100,alive:1,team:2,unit_name:'hero'};
const bar=()=>bars.SurvivalHeroWorldHealth_unit_42;
const tick=()=>tasks.shift()();
const send=value=>callback('survival_hero_health_bar','unit_42',{...state,...value});
const width=()=>parseFloat(bar().__fill.style.width);
send({});tick();assert.equal(bar().style.visibility,'visible');
assert.equal(width(),50);
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
assert.equal(tasks.length,1,'only the existing frame loop is used');
failOrigin=false;origin=[10,20,0];tick();assert.equal(bar().style.visibility,'visible');
valid=false;tick();assert(bar().deleted);
valid=true;send({});tick();
callback('survival_hero_health_bar','unit_42',{removed:1});assert(bar().deleted);
console.log('WORLD_HEALTH_BAR_PASS: 5s lethal forecast, overkill, pause, stop, healing, concurrent beams, expiry, entity lifecycle');
