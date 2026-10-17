"use strict";
const fs=require("fs"), vm=require("vm"), assert=require("assert");
const production="panorama/src/scripts/custom_game/hero_world_health_bar.js";
const manifest=JSON.parse(fs.readFileSync("output/ui_refresh_audit_20261013/world_health_idle_checkpoint.json","utf8"));
const before=fs.readFileSync(manifest.checkpoint+"/hero_world_health_bar.js","utf8");
const candidate=fs.readFileSync(production,"utf8");
const source=process.argv.includes("--negative-control")?before:candidate;
const anchorSource=fs.readFileSync("panorama/src/scripts/custom_game/world_health_bar_anchor.js","utf8");

function fixture(script, options={}) {
    const config={}, nodes={}, table={}, jobs=new Map(), listeners=new Map();
    const native=new Map(), counts={callbacks:0,schedules:0,captures:0,geometry:0,
        projections:0,origin:0,validEntity:0,alive:0,dormant:0,unitName:0,
        style:0,position:0,visibility:0,create:0,hostLookups:0,logs:0};
    let now=0, serial=0, listenerSerial=0, hostReady=options.hostReady!==false;
    let blocked=false, screenX=100, failOrigin=false, clock=0;
    function panel(id,parent) {
        const p={id,parent,deleted:false,actualuiscale_x:1,actualuiscale_y:1,
            actuallayoutwidth:1920,actuallayoutheight:1080,
            style:new Proxy({}, {set(o,k,v){counts.style++;
                if(k==="position")counts.position++;if(k==="visibility")counts.visibility++;
                o[k]=v;return true;}}),
            IsValid(){return !this.deleted&&(!this.parent||this.parent.IsValid());},
            DeleteAsync(){this.deleted=true;},AddClass(){},SetHasClass(){},
            GetPositionWithinWindow(){counts.geometry++;return {x:0,y:0};}};
        if(id)nodes[id]=p;return p;
    }
    const context=panel("Context");let container=panel("SurvivalHeroWorldHealthBars",context);
    const $=()=>{counts.hostLookups++;return hostReady?container:null;};
    $.GetContextPanel=()=>context;
    $.CreatePanel=(_,parent,id)=>{assert(parent&&parent.IsValid(),"never create under an invalid/missing host");counts.create++;return panel(id,parent);};
    $.Schedule=(delay,fn)=>{counts.schedules++;const id=++serial;
        jobs.set(id,{at:now+(delay===0?1/60:Number(delay)),fn});return id;};
    if(!options.noCancellation)$.CancelScheduled=id=>jobs.delete(id);
    $.Msg=()=>{counts.logs++;throw Error("no periodic console output");};
    config.SurvivalWorldOverlayVisibility={Capture(){counts.captures++;return {blocked};},Overlaps:()=>false};
    const env={$,GameUI:{CustomUIConfig:()=>config},Players:{GetTeam:()=>2},
        Game:{GetGameTime:()=>clock,GetLocalPlayerID:()=>0,IsInToolsMode:()=>false,
            WorldToScreenX:()=>screenX,WorldToScreenY:()=>100},
        Entities:{IsValidEntity(id){counts.validEntity++;return native.has(id)&&native.get(id).valid!==false;},
            IsAlive(id){counts.alive++;return native.get(id).alive!==false;},
            IsDormant(id){counts.dormant++;return native.get(id).dormant===true;},
            GetUnitName(id){counts.unitName++;return native.get(id).name||"hero";},
            GetAbsOrigin(){counts.origin++;if(failOrigin)throw Error("native origin unavailable");return [0,0,0];},
            GetHealthBarOffset:()=>190},
        CustomNetTables:{GetAllTableValues:()=>table,
            SubscribeNetTableListener(_,fn){const id=++listenerSerial;listeners.set(id,fn);return id;},
            UnsubscribeNetTableListener:id=>listeners.delete(id)}};
    vm.runInNewContext(anchorSource,env);
    const actualProject=config.SurvivalWorldHealthBarAnchor.Project;
    config.SurvivalWorldHealthBarAnchor.Project=function(...args){counts.projections++;return actualProject.apply(this,args);};
    function load(){vm.runInNewContext(script,env);}
    function advance(seconds,gameClock=true){const end=now+seconds;let guard=0;
        while(true){let selected=null;for(const pair of jobs)
            if(pair[1].at<=end+1e-9&&(!selected||pair[1].at<selected[1].at))selected=pair;
            if(!selected)break;assert(++guard<100000,"bounded scheduler");
            jobs.delete(selected[0]);now=selected[1].at;if(gameClock)clock=now;
            counts.callbacks++;selected[1].fn();}
        now=end;if(gameClock)clock=now;
    }
    function send(id,extra={}){const value={entindex:id,health:50,max_health:100,alive:1,team:2,unit_name:"hero",...extra};
        table["unit_"+id]=value;for(const fn of [...listeners.values()])fn("survival_hero_health_bar","unit_"+id,value);}
    function remove(id){delete table["unit_"+id];for(const fn of [...listeners.values()])fn("survival_hero_health_bar","unit_"+id,{removed:1});}
    function semantic(){return Object.keys(nodes).filter(key=>key.startsWith("SurvivalHeroWorldHealth_unit_")).sort()
        .map(key=>{const p=nodes[key];return {key,deleted:!p.IsValid(),visibility:p.style.visibility,
            width:p.__fill.style.width,position:p.style.position,barWidth:p.style.width};});}
    load();
    return {config,context,jobs,listeners,nodes,table,native,counts,advance,send,remove,load,semantic,
        api:()=>config.SurvivalWorldHealthBars,
        resetCounts(){for(const k of Object.keys(counts))counts[k]=0;},
        ready(v){hostReady=v;},blocked(v){blocked=v;},x(v){screenX=v;},clock(v){clock=v;},originFailure(v){failOrigin=v;},
        replaceHost(){container.deleted=true;container=panel("SurvivalHeroWorldHealthBars",context);hostReady=true;},
        invalidateHost(){container.deleted=true;hostReady=false;},
        bar(id){return nodes["SurvivalHeroWorldHealth_unit_"+id];}};
}

const idleOld=fixture(before),idleNew=fixture(source);
idleOld.resetCounts();idleNew.resetCounts();idleOld.advance(10);idleNew.advance(10);
const emptyOld={...idleOld.counts},emptyNew={...idleNew.counts};
assert.equal(emptyOld.captures,600,"negative control reproduces per-frame empty visibility capture");
assert.equal(emptyOld.geometry,600,"negative control reproduces per-frame empty geometry read");
assert.equal(emptyNew.captures,0,"empty states never capture overlay visibility");
assert.equal(emptyNew.geometry,0,"empty states never read geometry");
assert.equal(emptyNew.projections,0);assert.equal(emptyNew.validEntity,0);
assert.equal(emptyNew.callbacks,10,"only one bounded one-second idle recovery job remains");
assert.equal(idleNew.jobs.size,1);assert.equal(idleNew.listeners.size,1);
assert.equal(idleNew.api().SchedulerInspect().mode,"idle");

function activeTrace(script){const f=fixture(script),trace=[];
    f.native.set(1,{});f.native.set(2,{dormant:true});f.native.set(3,{});
    f.send(1,{health:80,bar_width:120,laser_forecast:[{start:0,due:1,fraction:.2}]});
    f.send(2,{});f.send(3,{alive:0});f.resetCounts();
    const mark=name=>trace.push({name,units:f.semantic()});
    f.advance(.5);mark("half_hit");
    const width=f.bar(1).__fill.style.width;f.advance(.1,false);
    assert.equal(f.bar(1).__fill.style.width,width,"paused game clock freezes the exact forecast");mark("paused");
    f.advance(.4);mark("hit_due");f.x(200);f.advance(1/60);mark("camera_same_frame");
    f.blocked(true);f.advance(.1);mark("modal");f.blocked(false);f.advance(1/60);mark("modal_closed");
    f.native.get(2).dormant=false;f.advance(1/60);mark("dormant_restored");
    f.x(-1);f.advance(.1);mark("offscreen");f.x(100);f.advance(1/60);mark("camera_restored");
    f.originFailure(true);f.advance(1/60);mark("origin_failed");f.originFailure(false);f.advance(1/60);mark("origin_restored");
    f.send(1,{health:75,bar_width:156});f.advance(1/60);mark("health_and_boss_width");
    return {trace,counts:f.counts};
}
const activeOld=activeTrace(before),activeNew=activeTrace(source);
assert.deepEqual(activeNew.trace,activeOld.trace,"full IIFE active render/forecast/occlusion output is unchanged");
for(const field of ["captures","geometry","projections","origin","validEntity","alive","dormant","unitName","position","visibility"])
    assert.equal(activeNew.counts[field],activeOld.counts[field],"active native/DOM call cadence unchanged: "+field);

// A real NetTable event wakes the next frame after a long empty interval.
const waking=fixture(source);waking.advance(3);waking.native.set(8,{});waking.send(8,{});
assert.equal(waking.api().SchedulerInspect().mode,"frame");assert.equal(waking.jobs.size,1);
waking.advance(1/60);assert.equal(waking.bar(8).style.visibility,"visible");
// Dead/removal packets go idle immediately and preserve correct panel lifecycle.
waking.send(8,{alive:0});assert.equal(waking.bar(8).style.visibility,"collapse");
const deadBefore={...waking.counts};waking.advance(3);
for(const field of ["captures","geometry","origin","validEntity"])
    assert.equal(waking.counts[field],deadBefore[field],"dead-only states do not perform native/layout work: "+field);
waking.remove(8);assert(waking.bar(8).deleted);waking.remove(8);
assert.equal(waking.api().SchedulerInspect().aliveSnapshots,0,"repeated removal cannot underflow the bounded alive counter");
waking.native.set(9,{});waking.send(9,{});waking.advance(1/60);
assert.equal(waking.bar(9).style.visibility,"visible","another unit restores after dead-only idle");

// XML and native first-spawn replication can recover without another packet.
const lateHost=fixture(source,{hostReady:false});lateHost.native.set(10,{});lateHost.send(10,{});
lateHost.advance(.1);assert(!lateHost.bar(10));lateHost.ready(true);lateHost.advance(1);
assert.equal(lateHost.bar(10).style.visibility,"visible");
const lateNative=fixture(source);lateNative.send(11,{});lateNative.advance(.1);
assert.equal(lateNative.api().SchedulerInspect().mode,"idle");
lateNative.native.set(11,{});lateNative.advance(1);
assert.equal(lateNative.bar(11).style.visibility,"visible","pending first-spawn row survives until bounded recovery");
lateNative.native.get(11).alive=false;lateNative.advance(1/60);
assert.equal(lateNative.api().SchedulerInspect().mode,"idle");
lateNative.native.get(11).alive=true;lateNative.advance(1);
assert.equal(lateNative.bar(11).style.visibility,"visible","native alive correction recovers without a second packet");
lateNative.invalidateHost();lateNative.advance(1/60);const oldBar=lateNative.bar(11);
lateNative.replaceHost();lateNative.advance(1);
assert.notStrictEqual(lateNative.bar(11),oldBar);assert.equal(lateNative.bar(11).style.visibility,"visible");
lateNative.native.get(11).valid=false;lateNative.advance(1/60);
assert.equal(lateNative.api().SchedulerInspect().aliveSnapshots,0,"seen-invalid state is pruned exactly once");
lateNative.send("bad",{entindex:NaN});lateNative.advance(1/60);
assert.equal(lateNative.api().SchedulerInspect().aliveSnapshots,0,"malformed alive row is pruned before empty scheduling");

// A new loaded context/table cohort, stale controller and explicit Stop dispose.
const reload=fixture(source);reload.native.set(12,{});reload.send(12,{});reload.advance(.1);
const oldApi=reload.api(), oldPanel=reload.bar(12);
delete reload.table.unit_12;reload.native.set(13,{});reload.table.unit_13={entindex:13,health:90,max_health:100,alive:1,team:2,unit_name:"hero"};
reload.load();assert(oldApi.SchedulerInspect().stopped);assert(oldPanel.deleted);
assert.equal(reload.jobs.size,1);assert.equal(reload.listeners.size,1);reload.advance(1/60);
assert.equal(reload.bar(13).style.visibility,"visible","new-world table cohort is restored on reload");
const currentApi=reload.api();reload.config.SurvivalWorldHealthBars={};reload.advance(1/60);
assert(currentApi.SchedulerInspect().stopped);assert.equal(reload.jobs.size,0);assert.equal(reload.listeners.size,0);
const disposed=fixture(source);disposed.context.deleted=true;disposed.advance(1);
assert.equal(disposed.jobs.size,0);assert.equal(disposed.listeners.size,0);disposed.api().Stop();
const stopped=fixture(source);stopped.api().Stop();stopped.api().Refresh();stopped.advance(2);
assert.equal(stopped.jobs.size,0);assert.equal(stopped.listeners.size,0);
const noCancel=fixture(source,{noCancellation:true});noCancel.native.set(14,{});noCancel.send(14,{});
assert.equal(noCancel.jobs.size,1,"minimal preview lacking cancellation reuses its pending callback");
noCancel.advance(1);assert.equal(noCancel.bar(14).style.visibility,"visible");assert.equal(noCancel.jobs.size,1);

const evidence={scope:"Actual complete old/new hero_world_health_bar IIFEs + actual anchor in VM; mocked native/DOM operation counts, not native elapsed time or FPS",
    source:production,baseline:manifest.checkpoint+"/hero_world_health_bar.js",empty_seconds:10,
    empty_before:emptyOld,empty_after:emptyNew,active_native_and_dom_cadence_equal:true,
    active_trace_equal:true,active_old:activeOld.counts,active_new:activeNew.counts,
    event_next_frame:true,bounded_recovery_seconds:1,late_xml_and_native_replication:true,
    native_alive_and_host_replacement:true,hot_reload_and_stale_controller_dispose:true,
    producer_session_field:"No health-table epoch exists; preserve real packets and context/controller replacement instead of inventing a protocol"};
if(process.argv.includes("--write-evidence"))fs.writeFileSync("output/ui_refresh_audit_20261013/world_health_idle_vm_evidence.json",JSON.stringify(evidence,null,2)+"\n");
console.log("WORLD_HEALTH_IDLE_PASS: empty 10s captures/geometry 600->0, callbacks 600->10; active native/DOM cadence and render trace unchanged; true event, late host/spawn/native-alive, removal, reload/dispose recovery. VM counts only; no FPS claim.");
