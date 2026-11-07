'use strict';
// Complete real topnav + existing real combat enumeration helpers. Only the
// established native Panel/entity/timer boundary is simulated; counts are not FPS.
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const ROOT=process.cwd(),fixturePath=path.join(ROOT,'tools/test_topnav_refresh_context.cjs');
const input=process.argv[2]&&!process.argv[2].startsWith('--')?process.argv[2]:'panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js';
const baseline=process.argv.includes('--baseline'),source=fs.readFileSync(path.resolve(ROOT,input),'utf8');
let prefix=fs.readFileSync(fixturePath,'utf8').split('\nfunction run(code) {')[0];
function replaceOnce(a,b){assert.equal(prefix.split(a).length,2,a);prefix=prefix.replace(a,b);}
replaceOnce("const before = fs.readFileSync(path.join(root, process.argv[3] || baseline), 'utf8');","const before = '';");
replaceOnce('return {state,counters,cfg,map,ctx,Panel,skill,health','return {env,timers,loadCode: text => vm.runInContext(text,env),state,counters,cfg,map,ctx,Panel,skill,health');
// The extracted combat helpers now refer to their real module initializer.
// Preserve its normal null value; do not replace helpers or swallow warnings.
assert(prefix.includes('abilityRefreshLookup: null'), 'shared fixture retains real combat cache initializer');
const holder={exports:{}};
new Function('require','__dirname','process','module',prefix+'\nmodule.exports={fixture};')(require,path.dirname(fixturePath),{argv:['node',__filename],env:{}},holder);
let checks=0;const ok=(v,label)=>{assert(v,label);checks++;};
function fixture(){const f=holder.exports.fixture(source);f.advance(2000);assert.deepEqual(f.warnings,[]);return f;}
function burst(){
 const f=fixture(),before={...f.counters};let refreshSelections=0;
 f.cfg.HandoffCombat.RefreshSelection=()=>refreshSelections++;
 // 101 actual changes + a duplicate query notification for every change.
 for(let i=0;i<101;i++){f.state.unit=i%2===0?19:7;f.emit('dota_player_update_selected_unit',{PlayerID:0});f.emit('dota_player_update_query_unit',{PlayerID:0});}
 const immediate=f.counters.production-before.production,queued=f.timers.filter(t=>t.at===f.state.now).length;
 ok(f.inspect().unit===19,'current selection resolver sees latest identity before any queued presentation');
 if(!baseline){ok(immediate===0,'no full refresh on synchronous selection notification');ok(refreshSelections===0,'combat refresh is coalesced with presentation');}
 ok(queued===1,'burst queues one next-frame task');
 f.advance(0);
 const total=f.counters.production-before.production;
 if(!baseline){ok(total===1,'one complete refresh for all same-frame changes');ok(refreshSelections===1,'latest changed unit gets one combat refresh');}
 ok(f.inspect().unit===19,'latest identity remains current');
 assert.deepEqual(f.inspect().abilities,['ability_201','ability_202']);checks++;
 assert.deepEqual(f.warnings,[]);checks++;
 return {notifications:202,actual_identity_changes:101,immediate_refreshes:immediate,queued_tasks:queued,
  refreshes_after_one_next_frame:total,combat_selection_refreshes:refreshSelections,
  native_enumerations:f.counters.enumerations-before.enumerations,native_get_ability:f.counters.getAbility-before.getAbility};
}
const counts=burst();
if(!baseline){
 const same=fixture(),start=same.counters.production;
 for(let i=0;i<1000;i++)same.emit('dota_ability_changed',{player_id:0});
 ok(same.counters.production===start,'same identity events do not synchronously redraw');
 ok(same.timers.filter(t=>t.at===same.state.now).length===1,'1000 same-unit updates share one task');same.advance(0);
 ok(same.counters.production===start+1,'same-unit state gets one fresh refresh');
 const foreign=fixture(),foreignStart=foreign.counters.production,schedules=foreign.counters.schedules;
 for(let i=0;i<100;i++)foreign.emit('dota_player_update_selected_unit',{PlayerID:1});
 ok(foreign.counters.production===foreignStart&&foreign.counters.schedules===schedules,'foreign player creates zero refreshes/tasks');
 const late=fixture();late.state.unit=19;late.emit('dota_player_update_selected_unit',{PlayerID:0});
 const slot=late.map.abilities.children[0],old=slot.FindChildTraverse('AbilityImage');old.DeleteAsync();
 const fresh=new late.Panel('Image','AbilityImage',slot);late.advance(0);
 ok(Object.keys(fresh.style).length>0,'native child born before queued frame receives real style on that frame');
 ok(late.inspect().unit===19&&late.inspect().abilities[0]==='ability_201','late child keeps latest ability identity');
 const rebuild=fixture();rebuild.state.unit=19;rebuild.emit('dota_player_update_query_unit',{playerid:0});
 const previous=rebuild.map.abilities;previous.DeleteAsync();rebuild.map.abilities=new rebuild.Panel('Panel','abilities',rebuild.map.AbilitiesAndStatBranch);
 for(let i=0;i<8;i++)rebuild.skill('Ability'+i);rebuild.advance(0);
 ok(rebuild.inspect().nativeReady,'whole native abilities container rebuilt before frame is reacquired');
 ok(rebuild.map.abilities.children[0].style.width!==undefined,'fresh slot gets real sizing');
 assert.deepEqual(rebuild.inspect().abilities,['ability_201','ability_202']);checks++;
 const reload=fixture();reload.state.unit=19;reload.emit('dota_player_update_selected_unit',{PlayerID:0});
 reload.load();const afterReload=reload.counters.production;reload.advance(0);
 ok(reload.counters.production===afterReload,'old-generation queued callback performs zero refresh after HUD reload');
 const hidden=fixture();hidden.emit('dota_ability_changed',{PlayerID:0});hidden.ctx.alive=false;
 const afterDestroyed=hidden.counters.production;hidden.advance(0);
 ok(hidden.counters.production===afterDestroyed,'destroyed HUD suppresses queued callback');
 const idle=fixture(),idleStart=idle.counters.production;idle.advance(1000);
 ok(idle.counters.production-idleStart===10,'existing 10Hz passive recovery cadence preserved');
 for(const f of [same,foreign,late,rebuild,reload,hidden,idle]){assert.deepEqual(f.warnings,[]);checks++;}
 // Use the real combat cache scope, not a replacement implementation. A second
 // HUD consumer asks for the same authoritative enumeration during refresh.
 const joined=fixture(),combat=fs.readFileSync(path.join(ROOT,'panorama/src/scripts/custom_game/combat_stats.js'),'utf8');
 const a=combat.indexOf('    function withAbilityLookup(callback) {'),b=combat.indexOf('    function abilitySlotIndex(',a);
 ok(a>=0&&b>a,'real combat snapshot scope remains available');
 joined.loadCode(combat.slice(a,b));
 let scopeCalls=0,joinedRefreshes=0;
 joined.cfg.HandoffCombat.WithAbilitySnapshot=callback=>{scopeCalls++;return joined.env.withAbilityLookup(callback);};
 const originalRefresh=joined.cfg.SurvivalProductionHUD.Refresh;
 joined.cfg.SurvivalProductionHUD.Refresh=function(){
  joinedRefreshes++;joined.cfg.HandoffCombat.NativeEntries(joined.state.unit);joined.cfg.HandoffCombat.NativeEntries(joined.state.unit);
  return originalRefresh.apply(this,arguments);
 };
 const enumerationBefore=joined.counters.enumerations;
 joined.state.unit=19;joined.emit('dota_player_update_selected_unit',{PlayerID:0});joined.advance(0);
 ok(scopeCalls===1&&joinedRefreshes===1,'one synchronous snapshot scope owns the entire topnav refresh');
 ok(joined.counters.enumerations-enumerationBefore===1,'layout plus production consumer use one real native enumeration');
 ok(joined.env.abilityRefreshLookup===null,'synchronous snapshot scope is released before event returns');
 joined.setAbilities(19,[801,802,803]);joined.emit('dota_ability_changed',{PlayerID:0});joined.advance(0);
 assert.deepEqual(joined.inspect().abilities,['ability_801','ability_802','ability_803']);checks++;
 ok(joined.counters.enumerations-enumerationBefore===2,'next event sees fresh changed handles, not a cross-frame cache');
 const outside=joined.counters.enumerations;
 joined.cfg.HandoffCombat.NativeEntries(19);joined.cfg.HandoffCombat.NativeEntries(19);
 ok(joined.counters.enumerations===outside+2,'external native entries contract remains fresh outside a scope');
 const stableScopes=scopeCalls;joined.advance(100);
 ok(scopeCalls===stableScopes+1,'periodic recovery also receives exactly one local scope');
 joined.cfg.SurvivalProductionHUD.Refresh=()=>{throw Error('synthetic_native_consumer_failure');};
 joined.emit('dota_ability_changed',{PlayerID:0});joined.advance(0);
 ok(joined.warnings.length===1&&joined.warnings[0].includes('synthetic_native_consumer_failure'),'existing bounded refresh error reporting is preserved');
 ok(joined.env.abilityRefreshLookup===null,'failure releases cache through actual finally');
 joined.warnings.length=0;joined.cfg.SurvivalProductionHUD.Refresh=originalRefresh;
 joined.setAbilities(19,[901]);joined.emit('dota_ability_changed',{PlayerID:0});joined.advance(0);
 assert.deepEqual(joined.inspect().abilities,['ability_901']);checks++;
 assert.deepEqual(joined.warnings,[]);checks++;
}
console.log(JSON.stringify({status:baseline?'BASELINE_MEASURED_NOT_CANDIDATE_PASS':'TOPNAV_NEXT_FRAME_COALESCING_PASS',source:input,checks,counts,native_fps_claim:false,
 bound:'One existing $.Schedule(0) turn in the simulated scheduler, not a promise that a stalled engine renders within a fixed millisecond deadline.'}));
