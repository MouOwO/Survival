const fs=require('fs'),vm=require('vm'),assert=require('assert');
const file=process.argv[2]||'panorama/src/scripts/custom_game/hero_world_health_bar.js';
const source=fs.readFileSync(file,'utf8');
const helper=fs.readFileSync('panorama/src/scripts/custom_game/world_health_bar_anchor.js','utf8');
function fixture(tools){
    const config={},tasks=new Map(),listeners=new Map(),bars={},cost={projected:0,position:0,logs:0};
    let serial=0,ready=true,blocked=false,nextTask=0,nextListener=0,screenX=100,clock=0;
    function panel(id){return {id,style:new Proxy({}, {
        get:(target,key)=>key==='position'&&target[key]
            ?target[key].replace(/(-?\d+(?:\.\d+)?)px/g,(_,n)=>Number(n).toFixed(1)+'px'):target[key],
        set:(target,key,value)=>{if(key==='position')cost.position++;target[key]=value;return true;}}),
        IsValid(){return !this.deleted;},DeleteAsync(){this.deleted=true;},AddClass(){},SetHasClass(){},
        actualuiscale_x:1,actualuiscale_y:1,actuallayoutwidth:1920,actuallayoutheight:1080,
        GetPositionWithinWindow:()=>({x:0,y:0})};}
    const container=panel('container'),context=panel('context');
    const $=()=>ready?container:null;
    $.GetContextPanel=()=>context;
    $.CreatePanel=(_,parent,id)=>{const value=panel(id);if(id)bars[id]=value;return value;};
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
            GetUnitName:()=> 'hero',GetAbsOrigin:id=>[id===4?2500:screenX,0,0],GetHealthBarOffset:()=>190},
        CustomNetTables:{GetAllTableValues:()=>table,
            SubscribeNetTableListener:(_,fn)=>{const id=++nextListener;listeners.set(id,fn);return id;},
            UnsubscribeNetTableListener:id=>listeners.delete(id)}};
    vm.runInNewContext(helper,sandbox);vm.runInNewContext(source,sandbox);
    const api={CaptureToken:()=>serial};config.SurvivalClientCallbackProbe=api;
    return {config,api,cost,tasks,listeners,container,context,bars,
        tick(){const due=[...tasks.values()];tasks.clear();due.forEach(fn=>fn());},
        start(token){serial=token;},stop(){serial=0;},blocked(value){blocked=value;},
        x(value){screenX=value;},clock(value){clock=value;},ready(value){ready=value;},
        send(id,extra){table['unit_'+id]={...state(id),...extra};for(const fn of listeners.values())fn('survival_hero_health_bar','unit_'+id,table['unit_'+id]);},
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
