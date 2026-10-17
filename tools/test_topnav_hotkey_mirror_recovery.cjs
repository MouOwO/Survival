"use strict";
const fs=require("fs"),path=require("path"),vm=require("vm"),assert=require("assert");
const checkpoint=JSON.parse(fs.readFileSync("output/ui_refresh_audit_20261013/hotkey_mirror_checkpoint.json","utf8"));
const current=fs.readFileSync("panorama/src/scripts/custom_game/topnav_remaining_5d5c1152eb.js","utf8");
const before=fs.readFileSync(checkpoint.checkpoint+"/topnav_remaining_5d5c1152eb.js","utf8");
const combat=fs.readFileSync("panorama/src/scripts/custom_game/combat_stats.js","utf8");
const tested=process.argv.includes("--negative-control")?before:current;
let fixtureText=fs.readFileSync(path.join(__dirname,"test_topnav_refresh_context.cjs"),"utf8");
fixtureText=fixtureText.slice(0,fixtureText.indexOf("function run(code) {"));
const ownedReturn="return {state,counters,cfg,map,ctx,Panel,skill,health,hpFill,mpFill,warnings,sent,originals,load,advance,emit,inspect,semantic,setAbilities};";
assert(fixtureText.includes(ownedReturn));fixtureText=fixtureText.replace(ownedReturn,ownedReturn.replace("return {","return {env,"));
const harness=Function("require","__dirname","process",fixtureText+"\nreturn {fixture};")(require,__dirname,{argv:["node","fixture"]});
function fixture(script,options={}){
    const f=harness.fixture(script),env=f.env;
    const originalDollar=env.$,dollar=id=>f.ctx.FindChildTraverse(String(id).slice(1));
    Object.assign(dollar,originalDollar);env.$=dollar;
    const netListeners=new Map();let serial=10000,writerCalls=0;
    env.Players.GetPlayerHeroEntityIndex=()=>f.state.unit;
    Object.assign(env.Entities,{GetLevel:()=>1,GetHealth:()=>100,GetMaxHealth:()=>100,GetMana:()=>50,GetMaxMana:()=>50});
    env.Abilities.GetBehavior=id=>f.state.runtime[id]?.passive?2:4;
    env.Abilities.IsPassive=id=>!!f.state.runtime[id]?.passive;
    env.Abilities.GetCooldownTimeRemaining=()=>0;
    env.Abilities.ExecuteAbility=()=>{throw Error("visual recovery must not cast");};
    const getTable=env.CustomNetTables.GetTableValue;
    env.CustomNetTables.GetTableValue=(table,key)=>{
        if(table==="survival_ability_runtime"){
            if(String(key).startsWith("unit:")){const unit=Number(String(key).slice(5));return {owner_entindex:unit,ability_count:f.state.counts[unit]||0};}
            return f.state.runtime[key]||null;
        }
        return getTable(table,key);
    };
    env.CustomNetTables.SubscribeNetTableListener=(table,fn)=>{const id=++serial;netListeners.set(id,{table,fn});return id;};
    env.CustomNetTables.UnsubscribeNetTableListener=id=>netListeners.delete(id);
    const subscribe=env.GameEvents.Subscribe,tokens=new Map();
    env.GameEvents.Subscribe=(name,fn)=>{const id=++serial;tokens.set(id,true);subscribe(name,...[data=>{if(tokens.get(id))fn(data);}]);return id;};
    env.GameEvents.Unsubscribe=id=>tokens.delete(id);
    f.Panel.prototype.RemoveAndDeleteChildren=function(){for(const p of this.children.slice())p.DeleteAsync();};
    // The entire actual combat IIFE runs, including its real callbacks and
    // periodic signature fast path. No function body/startup seam is replaced.
    vm.runInContext(combat,env,{filename:"complete_real_combat_stats.js"});
    function ownRuntime(unit){for(const ability of f.state.slots[unit]||[])Object.assign(f.state.runtime[ability],{owner_entindex:unit,ability_entindex:ability});}
    ownRuntime(7);ownRuntime(19);
    const writer=f.cfg.SurvivalAbilityHotkeys;
    assert(writer&&typeof writer.Refresh==="function");
    const originalRefresh=writer.Refresh;
    writer.Refresh=function(){writerCalls++;return originalRefresh.apply(this,arguments);};
    if(options.missingWriter)delete f.cfg.SurvivalAbilityHotkeys;
    if(options.passiveOnly){for(const id of f.state.slots[7])f.state.runtime[id].passive=true;}
    if(options.emptyStart){f.setAbilities(7,[]);}
    function keys(){return Array.from(f.cfg.SurvivalMainHUD.Inspect().keys);}
    function inspect(){return f.cfg.SurvivalMainHUD.HotkeyMirrorInspect?.()||null;}
    function notifyRuntime(id){for(const record of [...netListeners.values()])if(record.table==="survival_ability_runtime")record.fn(record.table,String(id),f.state.runtime[id]);}
    function installWriter(){f.cfg.SurvivalAbilityHotkeys=writer;}
    return {...f,keys,recovery:inspect,notifyRuntime,writer,installWriter,ownRuntime,writerCalls:()=>writerCalls,
        lateSkills(ids){f.setAbilities(7,ids);ids.forEach((id,i)=>{f.state.names[id]="test_spell_"+i;Object.assign(f.state.runtime[id],{owner_entindex:7,ability_entindex:id,passive:i===1});});},
        hideAnchors(){for(const panel of f.map.abilities.children)panel.FindChildTraverse("AbilityButton").actuallayoutwidth=0;},
        showAnchors(){for(const panel of f.map.abilities.children)panel.FindChildTraverse("AbilityButton").actuallayoutwidth=116;}};
}
const f=fixture(tested);f.advance(1500);
assert.deepEqual(f.keys(),["Q","","W","E"],"real combat decides active/passive initial keys");
const beforeKeys=f.keys(),nativeLabels=f.map.abilities.children.slice(0,4).map(p=>p.FindChildTraverse("SurvivalAbilityHotkey"));
const baselineCasts=f.sent.filter(p=>/cast|ability_request/.test(p.name)).length;
f.load();f.advance(500);
assert.deepEqual(f.keys(),beforeKeys,"same-unit topnav hot reload restores the new visible mirror without changing real native labels/signature");
assert.equal(f.writerCalls(),1,"same-unit reload needs one authoritative replay");
assert(f.recovery().finished);assert.equal(f.recovery().attempts,1);
assert.strictEqual(f.map.abilities.children[0].FindChildTraverse("SurvivalAbilityHotkey"),nativeLabels[0],"native label is reused instead of deleted/rebuilt");
assert.equal(f.map.abilities.children[1].FindChildTraverse("HotkeyContainer").style.opacity,"0","passive native shortcut remains suppressed");
assert(!f.map.abilities.children[1].FindChildTraverse("SurvivalAbilityHotkey")?.text,"passive ability never receives a made-up key");
const steady=f.writerCalls();f.advance(10000);assert.equal(f.writerCalls(),steady,"stable10Hz HUD and quarter-second combat callbacks never force repeat writer refresh");
assert.equal(f.sent.filter(p=>/cast|ability_request/.test(p.name)).length,baselineCasts,"mirror recovery cannot cast or create a business request");
f.state.unit=19;f.emit("dota_player_update_selected_unit",{PlayerID:0});f.advance(1500);assert.deepEqual(f.keys(),["Q","W"]);
f.state.unit=7;f.emit("dota_player_update_selected_unit",{PlayerID:0});f.advance(1500);assert.deepEqual(f.keys(),["Q","","W","E"]);
assert.equal(f.writerCalls(),steady,"ordinary selection changes remain owned by existing combat events");
// Real runtime conversion active->passive->active uses the existing combat
// subscription; the renderer never decides key assignment itself.
f.state.runtime[101].passive=true;f.notifyRuntime(101);f.advance(1500);assert.deepEqual(f.keys(),["","","Q","W"]);
f.state.runtime[101].passive=false;f.notifyRuntime(101);f.advance(1500);assert.deepEqual(f.keys(),["Q","","W","E"]);
const primaryRecovery={...f.recovery()},primaryKeys=f.keys();

const late=fixture(tested,{missingWriter:true});late.load();late.advance(3000);
assert.equal(late.writerCalls(),0,"missing writer consumes no retries");late.installWriter();late.advance(500);
assert.deepEqual(late.keys(),["Q","","W","E"],"writer installed after long HUD idle recovers new mirror");
assert.equal(late.writerCalls(),1);

const pending=fixture(tested,{emptyStart:true});pending.load();pending.advance(3000);
assert.equal(pending.writerCalls(),0,"no skills does not burn ready recovery attempts");
pending.lateSkills([501,502,503]);pending.advance(1500);
assert.deepEqual(pending.keys(),["Q","","W"],"late real ability list is freshly enumerated and mirrored");

const anchors=fixture(tested);anchors.advance(500);anchors.hideAnchors();anchors.load();anchors.advance(100);
assert.deepEqual(anchors.keys(),["","","",""],"incomplete native geometry does not invent a mapping");
anchors.showAnchors();anchors.advance(1600);assert.deepEqual(anchors.keys(),["Q","","W","E"]);
assert(anchors.writerCalls()<=4,"late native mapping has bounded startup recovery");

const passive=fixture(tested,{passiveOnly:true});passive.advance(1500);
const priorPassiveCalls=passive.writerCalls();passive.load();passive.advance(5000);
assert.deepEqual(passive.keys(),["","","",""],"all-passive cohort remains keyless");
assert.equal(passive.writerCalls()-priorPassiveCalls,4,"all-passive no-binding cohort caps replay at four attempts per HUD generation");
const capped=passive.writerCalls();passive.advance(10000);assert.equal(passive.writerCalls(),capped);

const throwing=fixture(tested);throwing.advance(500);throwing.writer.Refresh=()=>{throw Error("native writer temporarily unavailable");};
throwing.load();throwing.advance(5000);assert.equal(throwing.recovery().attempts,4);assert.equal(throwing.recovery().failures,4);
assert.equal(throwing.recovery().finished,true);const failures=throwing.recovery().failures;throwing.advance(10000);assert.equal(throwing.recovery().failures,failures);
// An old HUD generation must not invoke the current writer from its timers.
const previous=throwing.recovery();throwing.cfg.HandoffGeneration++;throwing.advance(1000);assert.deepEqual(throwing.recovery(),previous);

const evidence={scope:"Whole actual combat_stats and whole actual topnav IIFEs in the same VM; only native APIs mocked, no startup/function-body seam; code-executed key assignments, not actual screenshot/FPS",
    sameUnitReload:{keys:primaryKeys,recovery:primaryRecovery,writerReplays:steady},
    passiveNoFabricatedKeys:true,normalSelectionWriterOwnership:true,lateWriter:true,emptyToActualSkills:true,lateNativeGeometry:true,
    boundedAllPassiveReplayPerGeneration:capped-priorPassiveCalls,boundedErrors:failures,stableWriterCallsOver10s:0,originalNativeLabelReused:true,
    oldSourceNegativeControl:"Preserved actual topnav loses all visible key mirrors after same-unit reload while actual combat native labels/signature still match"};
if(process.argv.includes("--write-evidence"))fs.writeFileSync("output/ui_refresh_audit_20261013/hotkey_mirror_vm_evidence.json",JSON.stringify(evidence,null,2)+"\n");
console.log("TOPNAV_HOTKEY_MIRROR_RECOVERY_PASS: full real combat+topnav IIFEs; same-entity active/passive hot reload, actual selection/runtime changes, late writer/skills/native anchors, four-attempt failure cap, zero steady forced writer calls, no casts. VM only.");
