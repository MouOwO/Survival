const fs=require('fs'),vm=require('vm'),assert=require('assert');
const panels=[],tasks=[];let listener,now=10,alive=true,dormant=false;
function panel(){const p={style:{},IsValid(){return !this.deleted},DeleteAsync(){this.deleted=true},AddClass(c){this.className=c}};panels.push(p);return p;}
const container=panel();container.actualuiscale_x=container.actualuiscale_y=1;
const $=()=>container;$.CreatePanel=()=>panel();$.Schedule=(_,fn)=>tasks.push(fn);
const state={entindex:42,team:2,start:10,duration:3,x:100,y:200,z:0};
vm.runInNewContext(fs.readFileSync('panorama/src/scripts/custom_game/building_construction_progress.js','utf8'),{
    $,Game:{GetGameTime:()=>now,GetLocalPlayerID:()=>0,WorldToScreenX:()=>100,WorldToScreenY:()=>200},
    Players:{GetTeam:()=>2},GameUI:{CustomUIConfig:()=>({})},
    Entities:{IsValidEntity:()=>true,IsAlive:()=>alive,IsDormant:()=>dormant},
    CustomNetTables:{SubscribeNetTableListener:(_,fn)=>listener=fn,GetAllTableValues:()=>({'construction_42':state})}
});
const bar=panels.find(p=>p.className==='ConstructionBar');
const fill=panels.find(p=>p.className==='ConstructionFill');
assert.equal(panels.find(p=>p.className==='ConstructionText').text,'建造中');
assert.equal(fill.style.width,'0.00%');assert.equal(bar.style.visibility,'visible');
const tick=()=>tasks.shift()();
now=11.5;tick();assert.equal(fill.style.width,'50.00%');
tick();assert.equal(fill.style.width,'50.00%','pause holds progress');
now=13;tick();assert.equal(fill.style.width,'100.00%');
assert(!bar.deleted,'deadline alone cannot fake server completion');
dormant=true;tick();assert.equal(bar.style.visibility,'collapse');
dormant=false;alive=false;tick();assert.equal(bar.style.visibility,'collapse');
listener('survival_ui_state','construction_42',{removed:1});assert(bar.deleted);
tick();assert.equal(tasks.length,0,'no recurring loop with no construction');
listener('survival_ui_state','unrelated',{foo:1});assert.equal(tasks.length,0);
console.log('CONSTRUCTION_PROGRESS_PASS: reload snapshot, label, 3-second clock, pause, server completion, death/dormancy, idle cleanup');
