const fs=require('fs'),vm=require('vm'),assert=require('assert');
const bars={},tasks=[];
let callback,valid=true,alive=true,dormant=false,origin=[0,0,0],name='hero';
function panel(id){return {style:{},actualuiscale_x:1,actualuiscale_y:1,
    AddClass(){},SetHasClass(){},IsValid(){return !this.deleted},DeleteAsync(){this.deleted=true}}}
const container=panel();
const $=()=>container;
$.CreatePanel=(_,parent,id)=>{const p=panel(id);if(id)bars[id]=p;return p};
$.Schedule=(_,fn)=>tasks.push(fn);
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/hero_world_health_bar.js','utf8'),{
    $,Players:{GetTeam:()=>2},Game:{GetLocalPlayerID:()=>0,WorldToScreenX:()=>100,WorldToScreenY:()=>100},
    Entities:{IsValidEntity:()=>valid,IsAlive:()=>alive,IsDormant:()=>dormant,GetAbsOrigin:()=>origin,GetUnitName:()=>name},
    CustomNetTables:{GetAllTableValues:()=>({}),SubscribeNetTableListener:(_,fn)=>callback=fn}
});
const state={entindex:42,health:50,max_health:100,alive:1,team:2,unit_name:'hero'};
const bar=()=>bars.SurvivalHeroWorldHealth_unit_42;
const tick=()=>tasks.shift()();
callback('survival_hero_health_bar','unit_42',state);tick();
assert.equal(bar().style.visibility,'visible');
alive=false;tick();assert.equal(bar().style.visibility,'collapse');
alive=true;dormant=true;tick();assert.equal(bar().style.visibility,'collapse');
dormant=false;origin=[0,0,-10000];tick();assert.equal(bar().style.visibility,'collapse');
origin=[0,0,0];name='thinker';tick();assert.equal(bar().style.visibility,'collapse');
name='hero';tick();assert.equal(bar().style.visibility,'visible');
valid=false;tick();assert(bar().deleted);
valid=true;callback('survival_hero_health_bar','unit_42',state);tick();
callback('survival_hero_health_bar','unit_42',{removed:1});assert(bar().deleted);
console.log('WORLD_HEALTH_BAR_PASS: death, dormancy, hidden anchor, reused entity index, removal');
