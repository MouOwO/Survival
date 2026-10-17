const fs=require('fs'),vm=require('vm'),assert=require('assert');
const file=process.argv[2]||'panorama/src/scripts/custom_game/hero_world_health_bar.js';
const source=fs.readFileSync(file,'utf8');
const helper=fs.readFileSync('panorama/src/scripts/custom_game/world_health_bar_anchor.js','utf8');
function fixture(tools,script=source){
    const config={},tasks=new Map(),listeners=new Map(),bars={},created=[],cost={projected:0,position:0,logs:0,visibilityReads:0,visibilityWrites:0};
    let serial=0,ready=true,blocked=false,nextTask=0,nextListener=0,screenX=100,clock=0,originFailure=false;
    function panel(id){const nativeStyle={};return {id,nativeStyle,style:new Proxy(nativeStyle, {
        get:(target,key)=>{if(key==='visibility')cost.visibilityReads++;return key==='position'&&target[key]
            ?target[key].replace(/(-?\d+(?:\.\d+)?)px/g,(_,n)=>Number(n).toFixed(1)+'px'):target[key];},
        set:(target,key,value)=>{if(key==='visibility'&&target.rejectVisibility===value){delete target.rejectVisibility;throw Error('native visibility write failed');}if(key==='position')cost.position++;if(key==='visibility')cost.visibilityWrites++;target[key]=value;return true;}}),
        IsValid(){return !this.deleted;},DeleteAsync(){this.deleted=true;},AddClass(){},SetHasClass(){},
        actualuiscale_x:1,actualuiscale_y:1,actuallayoutwidth:1920,actuallayoutheight:1080,
        GetPositionWithinWindow:()=>({x:0,y:0})};}
    const container=panel('container'),context=panel('context');
    container.parent=context;
    const $=()=>ready?container:null;
    $.GetContextPanel=()=>context;
    $.CreatePanel=(_,parent,id)=>{const value=panel(id);value.parent=parent;created.push(value);if(id)bars[id]=value;return value;};
    $.Schedule=(_,fn)=>{const id=++nextTask;tasks.set(id,fn);return id;};
    $.CancelScheduled=id=>tasks.delete(id);
    $.Msg=()=>{cost.logs++;throw Error('no per-frame logs');};
    const state=id=>({entindex:id,health:50,max_health:100,alive:id===2?0:1,team:2,unit_name:'hero'});
    const table=Object.fromEntries([1,2,3,4].map(id=>['unit_'+id,state(id)]));
    config.SurvivalWorldOverlayVisibility={Capture:()=>({blocked}),Overlaps:()=>false};
    const sandbox={$,GameUI:{CustomUIConfig:()=>config},Players:{GetTeam:()=>2},
        Game:{IsInToolsMode:()=>tools,GetLocalPlayerID:()=>0,GetGameTime:()=>clock,
            WorldToScreenX:x=>{cost.projected++;return x;},WorldToScreenY:()=>{cost.projected++;return 100;}},
        Entities:{IsValidEntity:()=>true,IsAlive:()=>true,IsDormant:id=>id===3,
            GetUnitName:()=> 'hero',GetAbsOrigin:id=>{if(originFailure)throw Error('unit removed during frame');return [id===4?2500:screenX,0,0];},GetHealthBarOffset:()=>190},
        CustomNetTables:{GetAllTableValues:()=>table,
            SubscribeNetTableListener:(_,fn)=>{const id=++nextListener;listeners.set(id,fn);return id;},
            UnsubscribeNetTableListener:id=>listeners.delete(id)}};
    vm.runInNewContext(helper,sandbox);vm.runInNewContext(script,sandbox);
    const api={CaptureToken:()=>serial};config.SurvivalClientCallbackProbe=api;
    return {config,api,cost,tasks,listeners,container,context,bars,created,
        tick(){const due=[...tasks.values()];tasks.clear();due.forEach(fn=>fn());},
        start(token){serial=token;},stop(){serial=0;},blocked(value){blocked=value;},
        x(value){screenX=value;},clock(value){clock=value;},ready(value){ready=value;},originFailure(value){originFailure=value;},
        send(id,extra){table['unit_'+id]={...state(id),...extra};for(const fn of listeners.values())fn('survival_hero_health_bar','unit_'+id,table['unit_'+id]);},
        remove(id){delete table['unit_'+id];for(const fn of listeners.values())fn('survival_hero_health_bar','unit_'+id,{removed:1});},
        reload(){vm.runInNewContext(script,sandbox);},
        report(){return config.SurvivalWorldHealthBars.ProbeInspect();}};
}
const normal=fixture(false);normal.start(1);for(let i=0;i<10;i++)normal.tick();
assert.equal(normal.report().observed,false,'non-Tools cannot enable instrumentation through config');
const f=fixture(true);
for(let i=0;i<10;i++)f.tick();
assert.equal(f.report().observed,false,'Tools instrumentation defaults off');
const positionsBefore=f.cost.position,projectionsBefore=f.cost.projected;
f.start(1);assert.equal(f.report().frames,0,'Start reports a fresh unobserved capture');
f.tick();let r=f.report();
assert.equal(r.frames,1);assert.equal(r.observed,true);assert.equal(r.statesVisited,4);assert.equal(r.peakStates,4);
assert.equal(r.activeSnapshots,3);assert.equal(r.deadSnapshots,1);assert.equal(r.unrenderableEntities,1);
assert.equal(r.activeEntities,2);assert.equal(r.projected,2);assert.equal(r.offScreen,1);assert.equal(r.displayed,1);
assert.equal(f.cost.projected-projectionsBefore,4,'each attempted Project performs the original two native screen APIs');
assert.equal(r.positionReads,0);assert.equal(r.positionWrites,0);assert.equal(r.equivalentPositionWrites,0);
assert.equal(r.positionUnchanged,1);
assert.equal(f.cost.position-positionsBefore,0,'normalized native getters no longer dirty stationary bars');
assert.equal(r.getterSamples.length,0,'unchanged positions need no native style read');
for(let i=0;i<30;i++){f.x(110+i);f.tick();}
r=f.report();assert.equal(r.positionWrites,30,'each camera change is applied in its original frame');
assert.equal(r.getterSamples.length,12,'getter samples remain bounded across changing camera positions');
assert(r.getterSamples.every(sample=>sample.expected.length<=160&&sample.actual.length<=160));
const movingWrites=f.cost.position,stationaryProjections=f.cost.projected;
for(let i=0;i<30;i++)f.tick();
assert.equal(f.cost.position,movingWrites,'stationary camera produces no extra style writes');
assert.equal(f.cost.projected-stationaryProjections,120,'projection still runs every frame for unit/camera movement');
f.blocked(true);const skipped=f.cost.projected;f.tick();
assert.equal(f.report().modalBlockedFrames,1);assert.equal(f.cost.projected,skipped);
assert.equal(f.report().visibilityWrites,1,'modal hides count existing frame visibility writes');
f.blocked(false);f.tick();assert.equal(f.report().visibilityWrites,2);
const widthWrites=f.report().healthWidthWrites;
f.clock(0);f.send(1,{laser_forecast:[{start:0,due:1,fraction:0.2}]});
assert.equal(f.report().healthWidthWrites,widthWrites,'NetTable writes are explicitly outside frame counters');
f.clock(0.5);f.tick();assert.equal(f.report().healthWidthWrites,widthWrites+1);
f.stop();const frozen=JSON.stringify(f.report());f.tick();assert.equal(JSON.stringify(f.report()),frozen,'Stop freezes counters while the original loop continues');
assert.equal(f.tasks.size,1);assert.equal(f.listeners.size,1);assert.equal(f.cost.logs,0);
f.start(2);r=f.report();assert.equal(r.captureSerial,2);assert.equal(r.frames,0);assert.equal(r.getterSamples.length,0);
f.container.deleted=true;f.ready(false);f.tick();assert.equal(f.report().missingContainerFrames,1);
f.container.deleted=false;f.ready(true);f.tick();assert.equal(f.report().displayed,1);
f.config.SurvivalClientCallbackProbe={CaptureToken:()=>2};
assert.equal(f.report().frames,0,'a replacement API with the same serial starts a distinct capture');
f.tick();const prior=f.config.SurvivalWorldHealthBars;
f.context.deleted=true;f.tick();assert.equal(f.tasks.size,0);assert.equal(f.listeners.size,0);
const ended=JSON.stringify(prior.ProbeInspect());prior.Refresh();assert.equal(JSON.stringify(prior.ProbeInspect()),ended);
prior.Stop();assert.equal(f.tasks.size,0);
console.log('WORLD_BAR_PROBE_PASS: opt-in Tools capture, active/dead/dormant/offscreen counts, normalized getter evidence, bounded storage, Stop/reset/disposal, unchanged frame loop');

// Exercise real callbacks and rendered inline states, not the private cache.
// Optional argv[3] compares the exact trace to the preserved dirty baseline.
function visibilityTrace(script){
    const f=fixture(false,script),trace=[];
    function displayed(p){for(let n=p;n;n=n.parent)if(n.deleted||n.visible===false||n.cssVisibility==='collapse'||n.nativeStyle.visibility==='collapse')return false;return true;}
    function capture(label){trace.push({label,tasks:f.tasks.size,listeners:f.listeners.size,
        bars:Object.keys(f.bars).sort().map(id=>{const p=f.bars[id];return {id,deleted:!!p.deleted,
            displayed:displayed(p),visibility:p.nativeStyle.visibility,position:p.nativeStyle.position,width:p.__fill.nativeStyle.width};})});}
    function frames(label,count=1){const reads=f.cost.visibilityReads;for(let i=0;i<count;i++)f.tick();
        capture(label);return f.cost.visibilityReads-reads;}
    capture('first_frame');
    const steadyReads=frames('stationary_60',60);
    for(let i=0;i<10;i++){f.x(110+i);f.tick();}capture('moving_camera');
    f.blocked(true);frames('modal_open');frames('modal_stable',20);
    f.blocked(false);frames('modal_close');
    const leaf=f.bars.SurvivalHeroWorldHealth_unit_1,ancestorWrites=f.cost.visibilityWrites;
    f.context.cssVisibility='collapse';frames('ancestor_css_hidden');assert(!displayed(leaf));
    assert.equal(leaf.nativeStyle.visibility,'visible','ancestor CSS does not change the owned inline state');
    f.context.cssVisibility='visible';frames('ancestor_css_restored');assert(displayed(leaf));
    f.container.visible=false;frames('ancestor_property_hidden');assert(!displayed(leaf));
    f.container.visible=true;frames('ancestor_property_restored');assert(displayed(leaf));
    assert.equal(f.cost.visibilityWrites,ancestorWrites,'ancestor changes require no child visibility rewrite');
    f.x(-1);frames('offscreen');frames('offscreen_stable',20);f.x(100);frames('camera_returns');
    f.send(1,{alive:0});frames('dead');frames('dead_stable',20);f.send(1,{alive:1});frames('revived');
    f.originFailure(true);frames('origin_error');f.originFailure(false);frames('origin_restored');
    const beforeRemove=f.bars.SurvivalHeroWorldHealth_unit_1;f.remove(1);capture('removed');
    assert(beforeRemove.deleted);f.send(1,{});capture('recreated_before_first_show');frames('recreated_visible');
    const next=f.bars.SurvivalHeroWorldHealth_unit_1;assert.notStrictEqual(next,beforeRemove);
    assert.equal(next.nativeStyle.visibility,'visible');
    next.nativeStyle.rejectVisibility='collapse';f.blocked(true);
    assert.throws(()=>f.tick(),/native visibility write failed/);capture('hide_setter_fails');
    frames('hide_retries');f.blocked(false);next.nativeStyle.rejectVisibility='visible';
    frames('show_setter_fails');frames('show_retries');
    const prior=f.bars.SurvivalHeroWorldHealth_unit_1;f.reload();assert(prior.deleted);capture('hot_reload');
    assert.equal(f.tasks.size,1);assert.equal(f.listeners.size,1);
    f.context.deleted=true;frames('context_deleted');
    f.config.SurvivalWorldHealthBars.Stop();capture('stop_idempotent');
    assert(f.created.filter(p=>p.id.startsWith('SurvivalHeroWorldHealth_')).every(p=>p.deleted));
    return {trace,steadyReads,cost:f.cost};
}
const current=visibilityTrace(source);
assert.equal(current.steadyReads,0,'owned visibility needs no native getters during stationary frames');
if(process.argv[3]){
    const before=visibilityTrace(fs.readFileSync(process.argv[3],'utf8'));
    assert.deepEqual(current.trace,before.trace,'camera/modal/offscreen/death/error/recreation/reload/disposal visible-state trace is unchanged');
    assert.equal(before.steadyReads,240,'baseline performs four visibility native reads per frame in this fixture');
    assert.equal(current.cost.visibilityWrites,before.cost.visibilityWrites,'native visibility write sequence is unchanged');
    assert.equal(current.cost.projected,before.cost.projected,'native projection frequency is unchanged');
    console.log('WORLD_BAR_VISIBILITY_COMPARE_PASS: identical real callback states, lifecycle and projection frequency; stationary native visibility getters 240 -> 0 over 60 frames (4 bars), no FPS claim');
}else console.log('WORLD_BAR_VISIBILITY_PASS: zero steady native getters, real camera/modal/offscreen/death/error/recreation/reload/disposal callbacks');
