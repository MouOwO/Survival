// Actual Lua sender -> actual Panorama module. No native/game/backend actions.
// Default reads production sources; optional argv[2] is an isolated source root.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),cp=require('node:child_process');
const root=path.resolve(process.argv[2]||'.');
const lua=process.env.LUA||'C:/Program Files/lua/bin/lua5.1.exe';
const result=cp.spawnSync(lua,[path.join(__dirname,'test_gold_income_compact.lua'),root],{encoding:'utf8'});
assert.equal(result.status,0,result.stderr||result.stdout);
assert(!/handler error|assertion failed/i.test(result.stdout));
assert.match(result.stdout,/GOLD_COMPACT_LUA_PASS/);
const vectors=result.stdout.split(/\r?\n/).filter(x=>x.startsWith('VECTOR\t')).map(line=>{
 const [,p,event,e,a,c]=line.split('\t');return {player:Number(p),event,payload:{e:Number(e),a:Number(a),c:Number(c)}};
});
assert.equal(vectors.length,56);
const source=fs.readFileSync(path.join(root,'panorama/src/scripts/custom_game/gold_mine_income_numbers.js'),'utf8');
let checks=0;
function check(fn){fn();checks++;}
function harness(){
 let now=0,camera=0,blocked=false,next=0,created=0,projections=0,origins=0;
 const subscriptions=new Map(),timers=new Map(),loadingSubscriptions=new Map(),outbound=[],labels=[],invalid=new Set();
 let loading={admission_complete:1,profiles_ready:1,session_id:'synthetic-world-01'};
 const container={actualuiscale_x:1,actualuiscale_y:1,IsValid(){return !this.deleted;}};
 const config={SurvivalNumberFormatter:{Format:n=>String(n)},SurvivalWorldOverlayVisibility:{
  Capture:()=>null,Overlaps:()=>blocked}};
 const $=()=>container;
 $.Schedule=(delay,fn)=>{const id=++next;timers.set(id,fn);return id;};
 $.CancelScheduled=id=>timers.delete(id);
 $.CreatePanel=()=>{
  created++;const panel={style:{},classes:[],AddClass(c){this.classes.push(c);},
   IsValid(){return !this.deleted;},DeleteAsync(){this.deleted=true;}};
  labels.push(panel);return panel;
 };
 const context=vm.createContext({$,
  GameUI:{CustomUIConfig:()=>config},
  Game:{GetGameTime:()=>now,GetLocalPlayerID:()=>0,
   WorldToScreenX:x=>{projections++;return x+camera;},
   WorldToScreenY:y=>{projections++;return y+camera;}},
  Players:{GetSelectedEntities:()=>[]},
  Entities:{IsValidEntity:id=>!invalid.has(id),GetAbsOrigin:id=>{origins++;return [400+id,400,0];}},
  CustomNetTables:{GetTableValue:()=>loading,
   SubscribeNetTableListener:(table,fn)=>{assert.equal(table,'survival_loading');const id=++next;loadingSubscriptions.set(id,fn);return id;},
   UnsubscribeNetTableListener:id=>loadingSubscriptions.delete(id)},
  GameEvents:{Subscribe:(event,fn)=>{const id=++next;subscriptions.set(id,{event,fn});return id;},
   Unsubscribe:id=>subscriptions.delete(id),SendCustomGameEventToServer:(event,payload)=>outbound.push({event,payload})},
 });
 const api={labels,config,container,subscriptions,timers,outbound,invalid,loadingSubscriptions,
  loading:value=>{loading=value;Array.from(loadingSubscriptions.values()).forEach(fn=>fn('survival_loading','state'));},
  load:()=>vm.runInContext(source,context),
  emit:(event,payload)=>Array.from(subscriptions.values()).filter(s=>s.event===event).forEach(s=>s.fn(payload)),
  step:(time,move=0)=>{now=time;camera=move;const tasks=Array.from(timers.values());timers.clear();tasks.forEach(fn=>fn());},
  block:value=>blocked=value,
  counts:()=>({created,projections,origins}),
 };
 api.load();return api;
}
// Four recipient fixtures consume only their server-addressed frames. Shape and
// data are the real Lua output, not a second implementation of its encoder.
for(let id=0;id<4;id++){
 const h=harness(),rows=vectors.filter(v=>v.player===id);
 check(()=>assert.equal(h.outbound.filter(x=>x.event==='survival_gold_number_ready').length,1));
 check(()=>assert.equal(h.timers.size,0,'idle has no timer'));
 for(const row of rows)h.emit(row.event,row.payload);
 h.step(.1,20);
 check(()=>assert.equal(h.labels.length,rows.length));
 rows.forEach((row,i)=>{
  check(()=>assert.equal(h.labels[i].text,'+'+String(row.payload.a)));
  check(()=>assert.equal(h.labels[i].classes.includes('Critical'),row.payload.c===1));
  check(()=>assert.equal(h.labels[i].style.visibility,'visible'));
 });
 check(()=>assert.equal(h.timers.size,1,'one existing animation loop per UI, not per event'));
 h.step(1.1);
 check(()=>assert.equal(h.timers.size,0));
 check(()=>assert(h.labels.every(p=>p.deleted)));
 check(()=>assert.equal(h.outbound.length,2,'only initial ready + existing selection, never per-income uplink'));
}
// Equivalent legacy and new input retains formatted amount, critical style,
// moving camera, occlusion, and elapsed time fade.
{
 const a=harness(),b=harness();
 for(const row of vectors.filter(v=>v.player===0)){
  a.emit('gn',row.payload);b.emit('survival_gold_mine_income_number',{
   target_entindex:row.payload.e,amount:row.payload.a,critical:row.payload.c});
 }
 for(let i=0;i<30;i++){
  const time=i/60;a.step(time,i*8);b.step(time,i*8);
  check(()=>assert.deepEqual(a.labels.map(x=>[x.text,x.classes,x.style]),b.labels.map(x=>[x.text,x.classes,x.style])));
 }
 a.block(true);a.step(.6);check(()=>assert(a.labels.every(x=>x.style.visibility==='collapse')));
 a.block(false);a.step(.7);check(()=>assert(a.labels.every(x=>x.style.visibility==='visible')));
 a.invalid.add(1000);a.step(.8);check(()=>assert(a.labels.every(x=>x.deleted)));
 check(()=>assert.equal(a.timers.size,0));
}
// Malformed data cannot render misleading values or start a timer.
{
 const h=harness();
 for(const payload of [null,{}, {e:1,a:0,c:0},{e:1,a:Infinity,c:0},
  {e:NaN,a:1,c:0},{e:1.5,a:1,c:0},{e:-1,a:1,c:0},{e:1,a:1,c:2},
  {e:'1',a:2,c:0},{e:1,a:'2',c:0}])h.emit('gn',payload);
 check(()=>assert.equal(h.labels.length,0));check(()=>assert.equal(h.timers.size,0));
}
// Real layout reload tears down the old receiver/animation even if a cancelled
// callback is delivered late. Stable selection does not re-advertise capability.
{
 const h=harness();h.emit('gn',{e:10,a:3,c:1});
 const callbacks=Array.from(h.timers.values()),oldSubscribers=Array.from(h.subscriptions.values());
 const old=h.labels[0];h.load();
 check(()=>assert(old.deleted));check(()=>assert.equal(h.subscriptions.size,4));
 check(()=>assert.equal(h.timers.size,0));
 callbacks.forEach(fn=>fn());oldSubscribers.filter(x=>x.event==='gn').forEach(x=>x.fn({e:10,a:9,c:0}));
 check(()=>assert.equal(h.labels.length,1,'retired receivers cannot make another label'));
 h.emit('gn',{e:10,a:11,c:0});check(()=>assert.equal(h.labels.length,2));
 for(let i=0;i<1000;i++)h.emit('dota_player_update_selected_unit',{});
 check(()=>assert.equal(h.outbound.filter(x=>x.event==='survival_gold_number_ready').length,2,'once per real UI lifetime'));
 h.container.deleted=true;h.step(.1);
 check(()=>assert.equal(h.subscriptions.size,0));check(()=>assert.equal(h.timers.size,0));
 check(()=>assert.equal(h.loadingSubscriptions.size,0));
 check(()=>assert(h.labels.every(x=>x.deleted)));
}
{
 const h=harness();h.emit('gn',{e:10,a:10,c:0});
 const stable={admission_complete:1,profiles_ready:1,session_id:'synthetic-world-01'};
 const oldWorldCallbacks=Array.from(h.timers.values());
 for(let i=0;i<1000;i++)h.loading(stable);
 check(()=>assert.equal(h.outbound.length,2,'stable ready state causes zero extra capability sends'));
 h.loading({...stable,session_id:'synthetic-world-02'});
 check(()=>assert(h.labels.every(x=>x.deleted),'world transition retires old labels'));
 check(()=>assert.equal(h.timers.size,0));
 h.emit('gn',{e:10,a:3,c:0});
 const calls=h.counts().projections;
 oldWorldCallbacks.forEach(fn=>fn());
 check(()=>assert.equal(h.counts().projections,calls,'cancelled old-world callback cannot duplicate the new animation loop'));
 check(()=>assert.equal(h.timers.size,1));
 check(()=>assert.equal(h.outbound.filter(x=>x.event==='survival_gold_number_ready').length,2));
 h.loading({admission_complete:1,profiles_ready:0,session_id:'synthetic-world-03'});
 check(()=>assert.equal(h.outbound.filter(x=>x.event==='survival_gold_number_ready').length,2,'not-ready scope never announces'));
 h.loading({admission_complete:1,profiles_ready:1,session_id:'synthetic-world-03'});
 check(()=>assert.equal(h.outbound.filter(x=>x.event==='survival_gold_number_ready').length,3,'ready transition announces without click'));
 h.loading({admission_complete:1,profiles_ready:1,session_id:'bad!'});
 check(()=>assert.equal(h.outbound.filter(x=>x.event==='survival_gold_number_ready').length,3));
}
// 9379 incoming income displays are not silently coalesced, omitted or doubled.
// Existing frame animation remains O(active labels), no additional poller.
{
 const h=harness();for(let i=1;i<=9379;i++)h.emit('gn',{e:11,a:i,c:i%2});
 check(()=>assert.equal(h.labels.length,9379));check(()=>assert.equal(h.timers.size,1));
 check(()=>assert.equal(h.outbound.length,2));
 h.step(1.1);check(()=>assert.equal(h.timers.size,0));
 check(()=>assert.equal(h.labels.reduce((n,p)=>n+Number(p.text.slice(1)),0),9379*9380/2));
}
console.log(JSON.stringify({status:'PASS',js_checks:checks,lua_checks:Number(result.stdout.match(/checks=(\d+)/)[1]),
 vectors:vectors.length,emissions:9379,native_measurement:false,network_requests:0,source_root:root}));
