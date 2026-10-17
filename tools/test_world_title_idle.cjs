'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const base='panorama/src/scripts/custom_game/';
const current=fs.readFileSync(process.argv[2]||base+'title_world_overlap_v30.js','utf8');
const before=fs.readFileSync('output/ui_refresh_audit_20261013/world_title_idle_v1_before_20261013/title_world_overlap_v30.js','utf8');
// Execute the complete actual controller and its actual active artwork/anchor
// modules. The only substitutes are Panorama/native APIs and a deterministic clock.
function fixture(source,options={}){
 let now=0,serial=0,listener=null,hostReady=options.hostReady!==false,randomSeed=731;
 const counts={schedule:0,capture:0,localPlayer:0,localHero:0,origin:0,projection:0,table:0,create:0,style:0,visible:0,image:0};
 const jobs=new Map(),nodes=[],tables={},commands={},cfg={};
 const units={100:{pos:[0,0,0],alive:true},101:{pos:[30,0,0],alive:true},102:{pos:[500,0,0],alive:true},103:{pos:[700,0,0],alive:true}};
 class Panel{
  constructor(type,parent,id){this.type=type;this.parent=parent;this.id=id||'';this.children=[];this.classes=new Set();this.valid=true;
   this.actuallayoutwidth=1920;this.actuallayoutheight=1080;this.actualuiscale_x=this.actualuiscale_y=1;
   this.style=new Proxy({}, {set:(obj,key,value)=>{counts.style++;obj[key]=value;return true;}});
   let visible=true;Object.defineProperty(this,'visible',{get:()=>visible,set:value=>{counts.visible++;visible=value;}});
   if(parent)parent.children.push(this);nodes.push(this);counts.create++;
  }
  IsValid(){return this.valid;}AddClass(value){this.classes.add(value);}SetScaling(){}
  SetImage(value){counts.image++;this.image=value;}GetParent(){return this.parent;}
  GetPositionWithinWindow(){return {x:0,y:0};}GetChildCount(){return this.children.length;}
  DeleteAsync(){this.valid=false;this.children.slice().forEach(p=>p.DeleteAsync());if(this.parent)this.parent.children=this.parent.children.filter(p=>p!==this);}
 }
 const context=new Panel('Panel',null,'context');let host=new Panel('Panel',context,'SurvivalWorldTitles');
 function $(id){return id==='#SurvivalWorldTitles'&&hostReady?host:null;}
 $.GetContextPanel=()=>context;$.Msg=()=>{};
 $.Schedule=(delay,fn)=>{counts.schedule++;const id=++serial;jobs.set(id,{at:now+(delay===0?1/60:delay),fn});return id;};
 $.CancelScheduled=id=>jobs.delete(id);$.CreatePanel=(type,parent,id)=>new Panel(type,parent,id);
 cfg.SurvivalWorldOverlayVisibility={Capture:()=>{counts.capture++;return {blocked:!!state.blocked};},Overlaps:()=>!!state.blocked};
 const state={blocked:false,localPlayer:0,localHero:100};
 const fakeMath=Object.create(Math);fakeMath.random=()=>{randomSeed=(randomSeed*1664525+1013904223)>>>0;return randomSeed/4294967296;};
 const env={$,Math:fakeMath,Date:{now:()=>now*1000},GameUI:{CustomUIConfig:()=>cfg},
  Game:{GetGameTime:()=>now,GetLocalPlayerID:()=>{counts.localPlayer++;return state.localPlayer;},
   WorldToScreenX:x=>{counts.projection++;return 960+x;},WorldToScreenY:(x,y)=>{counts.projection++;return 540-y;},
   AddCommand:(name,fn)=>{commands[name]=fn;}},
  Players:{GetPlayerHeroEntityIndex:()=>{counts.localHero++;return state.localHero;}},
  Entities:{IsValidEntity:e=>!!units[e],IsAlive:e=>!!units[e]&&units[e].alive,IsDormant:e=>!!units[e]&&!!units[e].dormant,
   IsIllusion:()=>false,GetUnitName:()=> 'hero',GetAbsOrigin:e=>{counts.origin++;return units[e].pos;},GetHealthBarOffset:()=>190},
  CustomNetTables:{GetAllTableValues:()=>Object.keys(tables).map(key=>({key,value:tables[key]})),
   GetTableValue:()=>{counts.table++;return {bar_width:120};},
   SubscribeNetTableListener:(name,fn)=>{listener=fn;return 73;},UnsubscribeNetTableListener:()=>{listener=null;}}
 };
 vm.createContext(env);
 for(const name of ['title_layered_art_polish_v8.js','title_motion_data_peak_v9.js','title_series_art_peak_v17.js','world_health_bar_anchor.js'])
  vm.runInContext(fs.readFileSync(base+name,'utf8'),env,{filename:name});
 function load(){vm.runInContext(source,env,{filename:'actual_title_controller.js'});}
 load();
 return {counts,state,units,cfg,nodes,jobs,context,load,
  advance(seconds){const end=now+seconds;let guard=0;while(true){let selected=null;for(const [id,job] of jobs)if(job.at<=end&&(!selected||job.at<selected[1].at))selected=[id,job];if(!selected)break;assert(++guard<100000,'bounded scheduler');jobs.delete(selected[0]);now=selected[1].at;selected[1].fn();}now=end;},
  equip(id,title='youlong'){const key='title_'+id,value={entindex:100+id,player_id:id,title_id:title,unit_name:'hero'};tables[key]=value;listener('survival_hero_health_bar',key,value);},
  unequip(id){const key='title_'+id,value={entindex:-1,title_id:''};tables[key]=value;listener('survival_hero_health_bar',key,value);},
  setHostReady(value){hostReady=value;},
  replaceHost(){host.DeleteAsync();host=new Panel('Panel',context,'SurvivalWorldTitles');hostReady=true;},
  unrelated(){listener('survival_hero_health_bar','unit_100',{health:90,alive:1});},
  semantic(){return nodes.filter(n=>n.valid&&n.classes.has('SurvivalWorldTitle')).map(n=>({visible:n.visible,style:JSON.parse(JSON.stringify(n.style)),children:n.children.length}));}
 };
}
function delta(after,before){return Object.fromEntries(Object.keys(after).map(k=>[k,after[k]-before[k]]));}
const oldEmpty=fixture(before),newEmpty=fixture(current);oldEmpty.advance(1);newEmpty.advance(1);
const oldStart={...oldEmpty.counts},newStart={...newEmpty.counts};oldEmpty.advance(10);newEmpty.advance(10);
const emptyBefore=delta(oldEmpty.counts,oldStart),emptyAfter=delta(newEmpty.counts,newStart);
assert(emptyBefore.capture>500&&emptyBefore.origin>500&&emptyBefore.table>500,'actual old full controller proves empty-title native work');
assert.equal(emptyAfter.capture,0,'empty titles never read HUD occlusion');assert.equal(emptyAfter.origin,0);
assert.equal(emptyAfter.projection,0);assert.equal(emptyAfter.table,0);assert.equal(emptyAfter.create,0);
assert(emptyAfter.schedule<=6,'one 2s watchdog replaces active render loop');
assert.equal(newEmpty.cfg.SurvivalWorldTitleScheduler.Inspect().framePending,false);
newEmpty.unrelated();newEmpty.advance(.1);assert.equal(newEmpty.counts.capture,0,'unrelated health table packets do not activate titles');
newEmpty.equip(0);newEmpty.advance(1/60);assert(newEmpty.semantic()[0].visible,'first actual title event wakes next render callback');
function runActive(source){
 const h=fixture(source),stages=[];h.equip(0);h.equip(1);h.equip(2,'peak_perfection');h.advance(1/60);
 const activeStart={...h.counts};h.advance(.5-1/60);stages.push(h.semantic());
 h.state.blocked=true;h.advance(.2);stages.push(h.semantic());h.state.blocked=false;h.advance(.2);stages.push(h.semantic());
 h.units[101].pos=[360,0,0];h.advance(.7);stages.push(h.semantic());
 h.units[101].dormant=true;h.advance(.2);stages.push(h.semantic());h.units[101].dormant=false;
 h.units[102].alive=false;h.advance(.2);stages.push(h.semantic());h.units[102].alive=true;h.advance(.2);stages.push(h.semantic());
 h.unequip(0);h.units[101].pos=[155,-100,0];h.advance(.8);stages.push(h.semantic());
 h.state.localPlayer=-1;h.state.localHero=-1;h.advance(.7);stages.push(h.semantic());
 return {h,stages,activeCounts:delta(h.counts,activeStart)};
}
const activeOld=runActive(before),activeNew=runActive(current);
assert.deepEqual(activeNew.stages,activeOld.stages,'full active animations/crowd/local no-title health protection/modal/fog/death/spectator behavior is identical');
assert.deepEqual(activeNew.activeCounts,activeOld.activeCounts,'active cadence and native/artwork calls are unchanged after initial event wake');
for(const id of [1,2])activeNew.h.unequip(id);const c={...activeNew.h.counts};activeNew.h.advance(6);
assert.equal(delta(activeNew.h.counts,c).capture,0,'removing last title immediately cancels active work');
activeNew.h.equip(3);activeNew.h.advance(1/60);assert(activeNew.h.semantic()[0].visible,'new title restores after long idle');
const delayed=fixture(current,{hostReady:false});delayed.equip(0);delayed.advance(1);assert.equal(delayed.semantic().length,0);
delayed.setHostReady(true);delayed.advance(1.1);assert.equal(delayed.semantic().length,1,'watchdog restores title whose native host arrives without a second packet');assert(delayed.semantic()[0].visible);
delayed.replaceHost();delayed.advance(1/60);assert.equal(delayed.semantic().length,1,'host replacement preserves states and recreates only invalid visuals');
const reload=fixture(current);reload.equip(0);reload.advance(.2);const oldScheduler=reload.cfg.SurvivalWorldTitleScheduler;
reload.load();assert(oldScheduler.Inspect().disposed,'old context scheduler is disposed on reload');assert.equal(reload.semantic().length,1);reload.advance(.3);assert.equal(reload.semantic().length,1,'reload does not duplicate native title panels');
reload.context.valid=false;reload.advance(.1);assert.equal(reload.jobs.size,0,'invalid context cancels active jobs');
const evidence={scope:'Complete actual old/new world title IIFE + loaded active artwork and projection helpers in VM; counts are mocked native/DOM calls, not elapsed native cost or FPS',stable_seconds:10,empty_before:emptyBefore,empty_after:emptyAfter,active_semantics_and_native_calls_equal:true,late_host_event_and_watchdog_recovery:true,hot_reload_and_context_dispose:true};
if(process.env.WORLD_TITLE_IDLE_EVIDENCE)fs.writeFileSync(process.env.WORLD_TITLE_IDLE_EVIDENCE,JSON.stringify(evidence,null,2)+'\n');
console.log('WORLD_TITLE_IDLE_PASS '+JSON.stringify(evidence));
