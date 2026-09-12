// Run the actual module functions against a strict Panorama-style setter and
// destroyed native panels. No copies of production callback/portrait logic.
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync(process.argv[2]||'panorama/src/scripts/custom_game/combat_stats.js','utf8');
const seam='    // NetTable is the single regular synchronization path.';
assert(source.includes(seam));
const instrumented=source.replace(seam,`    __test({scheduleActive:scheduleActive, cosmeticPortraitSentinel:cosmeticPortraitSentinel,
        resetScale:resetTowerPortraitContentScale, applyScale:applyTowerPortraitContentScale,
        restoreHotkey:restoreNativeAbilityHotkey, suppressHotkey:suppressNativeAbilityHotkey,
        refreshAbilities:refreshAbilities, shutdown:shutdownCombatContext,
        positionNumber:positionRelativeToNativeNumber, positionRow:positionRelativeToStatRow,
        positionAttributes:positionLogicalAttributeOverlay, positionPortrait:positionCosmeticPortrait,
        subscribeTable:subscribeCombatTable, subscribeEvent:subscribeCombatEvent});
    return;
`+seam);
function setup(){
 const cfg={},jobs=new Map(),messages=[],subscriptions=new Map();let serial=0,api;
 class Panel{
  constructor(id,parent){this.id=id;this.parent=parent;this.children=[];this.alive=true;this.hittest=true;this.hittestchildren=true;this.values={};if(parent)parent.children.push(this);
   this.style=new Proxy(this.values,{set:(o,k,v)=>{if(!this.alive)throw Error('native panel destroyed');if(v===null||v===undefined||/NaN|Infinity/.test(String(v)))throw Error('native style rejected '+k+'='+v);o[k]=v;return true;}});
  }
  IsValid(){if(this.alive==='throw')throw Error('native handle released');return this.alive}
  GetParent(){return this.parent}FindChildTraverse(id){if(this.id===id)return this;for(const c of this.children){const p=c.FindChildTraverse(id);if(p)return p;}return null}
  AddClass(){} GetChildCount(){return this.children.length}GetChild(i){return this.children[i]}
 }
 const root=new Panel('Hud'),context=new Panel('Context',root),overlay=new Panel('SurvivalTowerPortraitOverlay',context),scene=new Panel('SurvivalTowerPortraitScene',overlay);
 const $=id=>context.FindChildTraverse(id.slice(1));$.GetContextPanel=()=>context;$.Schedule=(delay,fn)=>{const id=++serial;jobs.set(id,{delay,fn});return id};$.CancelScheduled=id=>jobs.delete(id);$.Msg=(...s)=>messages.push(s.join(''));$.Warning=$.Msg;
 const subscribe=(name,fn)=>{const id=++serial;subscriptions.set(id,{name,fn});return id};
 vm.runInNewContext(instrumented,{$,GameUI:{CustomUIConfig:()=>cfg},Game:{GetLocalPlayerID:()=>0},Players:{GetPlayerHeroEntityIndex:()=>-1},Entities:{},CustomNetTables:{GetTableValue:()=>null,SubscribeNetTableListener:subscribe,UnsubscribeNetTableListener:id=>subscriptions.delete(id)},GameEvents:{Subscribe:subscribe,Unsubscribe:id=>subscriptions.delete(id)},__test:x=>api=x},{filename:'combat_stats.js'});
 function run(id){const job=jobs.get(id);assert(job);jobs.delete(id);job.fn()}
 return {api,root,context,overlay,scene,cfg,jobs,messages,subscriptions,run,Panel};
}
// The reported callback entry is used by the 0.1s portrait sentinel. Hiding a
// scene must not pass null to a native style setter or kill the next tick.
const a=setup();a.api.applyScale(a.scene);
assert.doesNotThrow(()=>a.run(a.api.scheduleActive(.1,a.api.cosmeticPortraitSentinel)));
assert.equal(a.scene.values.transform,'scale3d(1, 1, 1)');assert.equal(a.scene.values.transformOrigin,'50% 50%');assert.equal(a.scene.values.visibility,'collapse');assert.equal(a.jobs.size,1);
// Resetting a released Scene and shutting down a released context must not touch
// the stale style bridge, even if IsValid itself throws.
a.scene.alive='throw';assert.doesNotThrow(()=>a.api.resetScale(a.scene));
a.context.alive='throw';assert.doesNotThrow(()=>a.run([...a.jobs.keys()][0]));assert.equal(a.jobs.size,0);
// Empty inline opacity restores visibility; explicitly recorded zero stays zero.
for(const original of ['', '0', '0.35']){
 const b=setup(),button=new b.Panel('Ability0',b.root),hotkey=new b.Panel('HotkeyContainer',button);hotkey.values.opacity=original;hotkey.hittestchildren=false;
 b.api.suppressHotkey(button);assert.equal(hotkey.values.opacity,'0');
 b.api.restoreHotkey(button);assert.equal(hotkey.values.opacity,original||'1');assert.equal(hotkey.hittest,true);assert.equal(hotkey.hittestchildren,false);
}
// The no-selection polling branch must be cancelled together with other jobs.
const c=setup();c.api.refreshAbilities();assert.equal(c.jobs.size,1);const late=[...c.jobs.values()][0].fn;
c.api.shutdown('replacement_context');assert.equal(c.jobs.size,0);assert.doesNotThrow(late);assert.equal(c.jobs.size,0);
let called=false;assert.equal(c.api.scheduleActive(.1,()=>{called=true}),null);assert(!called);
// A generation change prevents old callbacks from executing against the new HUD.
const d=setup(),id=d.api.scheduleActive(.1,()=>{called=true});d.cfg.SurvivalInputLifecycleGeneration=1;d.run(id);assert(!called);assert.equal(d.jobs.size,0);
// Unexpected errors retain their identity/stack and gain the originating task.
const e=setup(),failure=Error('intentional native failure'),errorJob=e.api.scheduleActive(.1,()=>{throw failure},'portrait_probe');
assert.throws(()=>e.run(errorJob),x=>x===failure);assert(e.messages.some(s=>s.includes('[COMBAT_STATS_CALLBACK_ERROR] task=portrait_probe')&&s.includes('intentional native failure')&&s.includes('stack=')));assert.equal(e.jobs.size,0);
// Native coordinates can be indexed vectors. Verify the real positioning paths
// at two HUD scales, then unavailable geometry followed by a successful retry.
for (const scale of [1, 0.75]) for (const indexed of [false, true]) {
 const t=setup(),parent=new t.Panel('stats_container',t.root),stat=new t.Panel('Damage',parent),number=new t.Panel('DamageLabel',stat),label=new t.Panel('Overlay',parent);
 const point=(x,y)=>indexed?[x,y,0]:{x,y};
 parent.GetPositionWithinWindow=()=>point(100,200);parent.actualuiscale_x=scale;parent.actualuiscale_y=scale;
 stat.GetPositionWithinWindow=()=>point(120,240);stat.actuallayoutheight=20;stat.actuallayoutwidth=16;
 number.GetPositionWithinWindow=()=>point(120,260);number.actuallayoutheight=20;
 assert(t.api.positionNumber(stat,parent,label,['DamageLabel']));assert.equal(label.values.position,`0px ${60/scale}px 0px`);
 assert(t.api.positionRow(stat,parent,label));assert.equal(label.values.position,`0px ${40/scale}px 0px`);
 for(const bad of [{},null,[0],{x:0,y:NaN},{x:0,y:Infinity}]) {
  number.GetPositionWithinWindow=()=>bad;stat.GetPositionWithinWindow=()=>bad;
  const before=JSON.stringify(label.values);
  assert.equal(t.api.positionNumber(stat,parent,label,['DamageLabel']),false);
  assert.equal(t.api.positionRow(stat,parent,label),false);
  assert.doesNotThrow(()=>t.api.positionAttributes(parent,label));
  assert.equal(JSON.stringify(label.values),before);
  assert.equal(t.api.positionPortrait(label,stat,t.scene),false);
 }
 stat.GetPositionWithinWindow=()=>point(120,240);number.GetPositionWithinWindow=()=>point(120,260);
 for(const badScale of [0,-1,NaN,Infinity,'invalid']) {
  parent.actualuiscale_y=badScale;
  assert.equal(t.api.positionNumber(stat,parent,label,['DamageLabel']),false);
  assert.equal(t.api.positionRow(stat,parent,label),false);
 }
 parent.actualuiscale_y=scale;assert(t.api.positionNumber(stat,parent,label,['DamageLabel']));
 const row=new t.Panel('SurvivalLogicalStrengthRow',label);
 t.api.positionAttributes(parent,label);assert.equal(row.values.position,`${20/scale-65}px ${40/scale+68}px 0px`);
}
for (const reason of ['shutdown','released','generation']) {
 const t=setup();let received=0;
 const id=t.api.subscribeTable('survival_combat_stats',(name,key,value)=>{assert.equal(name,'survival_combat_stats');assert.equal(key,'player_0');assert.equal(value.entindex,7);received++;});
 const event=t.api.subscribeEvent('ui_selected_unit_stats_snapshot',()=>received++);
 const listener=t.subscriptions.get(id).fn, eventListener=t.subscriptions.get(event).fn;
 listener('survival_combat_stats','player_0',{entindex:7});assert.equal(received,1);
 if(reason==='shutdown')t.api.shutdown('test');
 if(reason==='released')t.context.alive='throw';
 if(reason==='generation')t.cfg.SurvivalInputLifecycleGeneration=1;
 assert.doesNotThrow(()=>listener('survival_combat_stats','player_0',{entindex:7}));
 assert.doesNotThrow(()=>eventListener({entindex:7}));
 assert.equal(received,1);assert.equal(t.subscriptions.size,0);
 assert.equal(t.api.subscribeTable('late',()=>{}),null);
}
const f=setup(),eventError=Error('native event failure');
const eventId=f.api.subscribeEvent('stats_probe',()=>{throw eventError});
assert.throws(()=>f.subscriptions.get(eventId).fn(),x=>x===eventError);
assert(f.messages.some(s=>s.includes('[COMBAT_STATS_EVENT_ERROR] event=stats_probe')&&s.includes('native event failure')));
console.log('COMBAT_CALLBACK_TEST_PASS: timer/event lifecycle, stale queued snapshots, unsubscribe, native styles, coordinate vectors, scaling and recovery');
