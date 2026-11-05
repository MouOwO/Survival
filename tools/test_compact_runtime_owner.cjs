"use strict";
// Actual owner lifecycle with unknown native event types rejected. Pure Node
// VM/native doubles only, never a Panorama/native/FPS acceptance claim.
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const ROOT = path.resolve(__dirname, "..");
const sourcePath = path.resolve(process.argv[2] || path.join(ROOT, "panorama/src/scripts/custom_game/common/compact_ui_runtime.js"));
const source = fs.readFileSync(sourcePath, "utf8");
const W = require(path.join(ROOT, "panorama/src/scripts/custom_game/common/compact_wire.js"));
const B = require(path.join(ROOT, "panorama/src/scripts/custom_game/common/compact_grid_bulk_wire.js"));
const catalogueConfig = {};
vm.runInNewContext(fs.readFileSync(path.join(ROOT, "panorama/src/scripts/custom_game/common/ui_static_catalog.js"), "utf8"), {GameUI:{CustomUIConfig:()=>catalogueConfig}});
const C = catalogueConfig.SurvivalUICatalog.Data, schema = W.CompileLookup(C, 1);
const F = Object.fromEntries(C.fields.map(f=>[f.name,f.id]));
const R = Object.fromEntries(C.records.filter(r=>!r.tombstone).map(r=>[r.key,r.id]));
function hello(session=900) {
    return W.Encode(schema, {schema:1,schema_sha256:C.sha256,session,epoch:1,view:1}, 1,
        Array.from({length:8},(_,i)=>({record:R["wire:hello:"+(i+1)],field:F.count,value:parseInt(C.sha256.slice(i*8,i*8+8),16)})), {full:true}).packets;
}
function fixture(options={}) {
    let serial=0, loading=null;
    const cfg={SurvivalCompactWire:W,SurvivalCompactGridBulkWire:B,SurvivalUICatalog:{Data:C}};
    const events=new Map(), tables=new Map(), timers=new Map(), markers=[], sent=[], removed=[];
    const counts={panelChecks:0,invalidEventRegistrations:0,treeQueries:0,scheduled:0};
    function panel(parent=null) {
        const p={alive:true,deleteRequests:0,IsValid(){counts.panelChecks++;return p.alive&&(!parent||parent.alive);},
            DeleteAsync(){p.deleteRequests++;if(!options.asyncDelete)p.alive=false;},FindChildTraverse(){counts.treeQueries++;throw Error("recursive_query_forbidden");}};
        return p;
    }
    function load(owner) {
        vm.runInNewContext(source, {
            GameUI:{CustomUIConfig:()=>cfg},
            GameEvents:{Subscribe(name,fn){if(options.failSubscription===name)throw Error("native_subscription_failed");const id=++serial;events.set(id,{name,fn});if(options.onSubscribe)options.onSubscribe(owner,name,fn);return id;},
                Unsubscribe(id){removed.push(id);events.delete(id);if(options.onUnsubscribe)options.onUnsubscribe(id);},SendCustomGameEventToServer(name,packet){sent.push({name,packet});if(options.onSend)options.onSend(name,packet);}},
            CustomNetTables:{GetTableValue(){return loading;},SubscribeNetTableListener(name,fn){const id=++serial;tables.set(id,fn);return id;},
                UnsubscribeNetTableListener(id){removed.push(id);tables.delete(id);if(options.onUnsubscribe)options.onUnsubscribe(id);}},
            $:{GetContextPanel:()=>owner,CreatePanel(type,parent,id){assert.equal(type,"Panel");const p=panel(parent);markers.push(p);return p;},
                RegisterEventHandler(){counts.invalidEventRegistrations++;throw Error("native_invalid_event_type");},
                Schedule(delay,fn){counts.scheduled++;const id=++serial;timers.set(id,{delay,fn,canceled:false});return id;},
                CancelScheduled(id){if(timers.has(id))timers.get(id).canceled=true;if(options.onCancel)options.onCancel(id);}}, Game:{}
        }, {filename:sourcePath});
        return cfg.SurvivalCompactRuntime;
    }
    function deliver(packet) { for (const row of [...events.values()]) if(row.name==="cw")row.fn(packet); }
    function deliverBulk(packet) { for (const row of [...events.values()]) if(row.name==="gb")row.fn(packet); }
    function admit(identity="survival_test_world_A") {
        loading={admission_complete:1,profiles_ready:1,session_id:identity};
        for(const fn of [...tables.values()])fn("survival_loading","state",loading);
    }
    return {cfg,events,tables,timers,markers,sent,removed,counts,panel,load,deliver,deliverBulk,admit};
}
const results=[],costCounts={};
function test(name,fn) { try { fn();results.push({name,passed:true}); } catch(error) {results.push({name,passed:false,error:error.message});} }

test("native rejects unknown event names; duplicate live XML roots still share one runtime",()=>{
    const t=fixture(),owner=t.panel(),rt=t.load(owner),view=rt.CreateView("daily",{});
    view.Open();assert.equal(t.load(t.panel()),rt);assert.equal(t.events.size,2);assert.equal(t.tables.size,1);
    assert.equal(t.counts.invalidEventRegistrations,0);assert.equal(t.counts.treeQueries,0);assert.equal(t.counts.scheduled,0);
    const before=t.counts.panelChecks;
    for(let i=0;i<100;i++){rt.Inspect();rt.ScopeIdentity();}
    assert.ok(t.counts.panelChecks-before<=800,"owner checks remain bounded per entry, independent of view count");
    assert.equal(t.counts.scheduled,0,"no lifecycle polling timer");
});
test("owner invalidation disposes once before receive, without close packets or stale commits",()=>{
    const t=fixture(),owner=t.panel(),rt=t.load(owner),view=rt.CreateView("daily",{});
    view.Open();t.admit();hello().forEach(t.deliver);
    const oldCallbacks=[...t.events.values()].map(v=>v.fn), sent=t.sent.length;
    owner.alive=false;oldCallbacks.forEach(fn=>fn({d:"late_packet"}));
    assert.equal(rt.Inspect().active,false);assert.equal(view.Inspect().active,false);
    assert.equal(view.Read(R["daily:state"],F.count),undefined);assert.equal(view.SendIntent("daily_claim",{target_day:1}).sent,false);
    assert.equal(t.events.size,0);assert.equal(t.tables.size,0);assert.equal(t.sent.length,sent);
    const removed=t.removed.length;rt.Dispose();oldCallbacks.forEach(fn=>fn({d:"late_packet"}));assert.equal(t.removed.length,removed);
    const fresh=t.load(t.panel());assert.notEqual(fresh,rt);assert.equal(fresh.Inspect().active,true);
    oldCallbacks.forEach(fn=>fn({d:"late_packet"}));rt.Dispose();assert.equal(t.cfg.SurvivalCompactRuntime,fresh);
});
test("root can survive layout reload while its child marker invalidates the runtime",()=>{
    const t=fixture(),owner=t.panel(),old=t.load(owner);
    assert.equal(t.markers.length,1,"one lifetime marker per actual runtime initialization");
    t.markers[0].alive=false;assert.equal(owner.IsValid(),true);
    const fresh=t.load(owner);assert.notEqual(fresh,old);assert.equal(old.Inspect().active,false);
    assert.equal(fresh.Inspect().active,true);assert.equal(t.events.size,2);assert.equal(t.tables.size,1);
    assert.equal(t.counts.treeQueries,0);assert.equal(t.counts.scheduled,0);
});
test("ordinary runtime Dispose is local teardown; live single-view Dispose retains its close semantics",()=>{
    const t=fixture(),rt=t.load(t.panel()),view=rt.CreateView("daily",{});
    view.Open();t.admit();hello().forEach(t.deliver);
    const beforeLive=t.sent.length;view.Dispose();assert.ok(t.sent.length>beforeLive);
    rt.CreateView("daily",{}).Open();const beforeRuntime=t.sent.length;
    rt.Dispose();assert.equal(t.sent.length,beforeRuntime);assert.equal(t.events.size,0);assert.equal(t.tables.size,0);
});
test("a queued existing hello timeout cannot run after owner death",()=>{
    const t=fixture(),owner=t.panel(),rt=t.load(owner);t.admit();t.deliver(hello()[0]);
    const callbacks=[...t.timers.values()].map(v=>v.fn);assert.ok(callbacks.length>0);
    const before=t.sent.length;owner.alive=false;callbacks.forEach(fn=>fn());
    assert.equal(rt.Inspect().active,false);assert.equal(t.sent.length,before);assert.equal(t.events.size,0);assert.equal(t.tables.size,0);
    callbacks.forEach(fn=>fn());assert.equal(t.sent.length,before);
});
test("same-world root recreation preserves intent/revision memo; new world still requires Hello",()=>{
    const t=fixture(),owner=t.panel(),old=t.load(owner);let view=old.CreateView("daily",{});
    view.Open();t.admit();hello().forEach(t.deliver);
    assert.equal(view.SendIntent("daily_claim",{target_day:1}).request_token,1);
    owner.alive=false;old.Inspect();const fresh=t.load(t.panel());view=fresh.CreateView("daily",{});view.Open();
    hello().forEach(t.deliver);assert.equal(view.SendIntent("daily_claim",{target_day:1}).request_token,2);
    t.admit("survival_test_world_B");assert.equal(fresh.ScopeIdentity().ready,false);
    assert.equal(view.SendIntent("daily_claim",{target_day:1}).sent,false);
});
test("owner IsValid exceptions retire rather than becoming a catch-and-ignore live instance",()=>{
    const t=fixture(),owner=t.panel(),rt=t.load(owner);owner.IsValid=()=>{throw Error("deleted_native_handle");};
    assert.equal(rt.Inspect().active,false);assert.equal(t.events.size,0);assert.equal(t.tables.size,0);
    assert.equal(rt.ScopeIdentity().ready,false);
});
test("late canceled prior-world hello timer cannot clear the new-world hello timer",()=>{
    const t=fixture(),rt=t.load(t.panel());t.admit();t.deliver(hello()[0]);
    const old=[...t.timers.values()].at(-1);assert.ok(old);
    t.admit("survival_test_world_B");const currentPackets=hello(901);t.deliver(currentPackets[0]);
    const fresh=[...t.timers.values()].at(-1);assert.notEqual(fresh,old);assert.equal(old.canceled,true);
    old.fn();currentPackets.slice(1).forEach(t.deliver);
    assert.equal(rt.ScopeIdentity().ready,true);assert.equal(fresh.canceled,true,"fresh completed assembly timeout must still be canceled");
});
test("owner invalidated reentrantly by onCommit receives no subsequent hint",()=>{
    const t=fixture(),owner=t.panel(),rt=t.load(owner);let hints=0;
    const view=rt.CreateView("daily",{onCommit(){owner.alive=false;return true;},onHint(){hints++;}});
    view.Open();t.admit();hello().forEach(t.deliver);
    W.Encode(schema,{schema:1,schema_sha256:C.sha256,session:900,epoch:1,view:3},1,
        [{record:R["daily:state"],field:F.known,value:1},{record:R["daily:state"],field:F.can_claim,value:1}],{full:true}).packets.forEach(t.deliver);
    assert.equal(hints,0);assert.equal(rt.Inspect().active,false);assert.equal(t.events.size,0);assert.equal(t.tables.size,0);
});
test("same-generation canceled client timer cannot touch a reopened view assembly",()=>{
    const t=fixture(),rt=t.load(t.panel()),view=rt.CreateView("daily",{});view.Open();t.admit();hello().forEach(t.deliver);
    function packets(count){return W.Encode(schema,{schema:1,schema_sha256:C.sha256,session:900,epoch:1,view:3},1,
        [{record:R["daily:state"],field:F.known,value:1},{record:R["daily:state"],field:F.count,value:count},
         {record:R["daily:state"],field:F.can_claim,value:1}],{full:true}).packets;}
    const first=packets(1),second=packets(2);assert.ok(first.length>1);t.deliver(first[0]);
    const old=[...t.timers.values()].at(-1);view.Close();view.Open();t.deliver(second[0]);
    const fresh=[...t.timers.values()].at(-1);assert.notEqual(fresh,old);assert.equal(old.canceled,true);
    old.fn();second.slice(1).forEach(t.deliver);assert.equal(fresh.canceled,true);assert.equal(view.Read(R["daily:state"],F.count),2);
});
test("partial initialization cleans saved subscriptions and asynchronously deletes its marker once",()=>{
    const t=fixture({failSubscription:"gb",asyncDelete:true});
    assert.throws(()=>t.load(t.panel()),/native_subscription_failed/);
    assert.equal(t.markers.length,1);assert.equal(t.markers[0].deleteRequests,1);assert.equal(t.events.size,0);assert.equal(t.tables.size,0);
    assert.equal(t.cfg.SurvivalCompactRuntimeOwner,null);assert.ok(!t.cfg.SurvivalCompactRuntime);
});
test("synchronous subscription callback retires and releases the ID returned afterward",()=>{
    const t=fixture({asyncDelete:true,onSubscribe(owner,name,fn){owner.alive=false;fn({d:"late"});}});
    t.load(t.panel());assert.equal(t.events.size,0);assert.equal(t.tables.size,0);assert.equal(t.removed.length,1);
    assert.equal(t.markers[0].deleteRequests,0,"an already dead native child needs no delete request");assert.ok(!t.cfg.SurvivalCompactRuntime);
});
test("runtime pointer replacement retires old callbacks without clearing another runtime",()=>{
    const t=fixture(),rt=t.load(t.panel()),other={sentinel:true};t.cfg.SurvivalCompactRuntime=other;
    assert.equal(rt.ScopeIdentity().active,false);assert.equal(t.cfg.SurvivalCompactRuntime,other);
    assert.equal(t.events.size,0);assert.equal(t.tables.size,0);
});
test("reentrant failing native cleanup still attempts every subscription exactly once",()=>{
    let rt,oldReceive,reentries=0;
    const t=fixture({onCancel(){rt.Dispose();throw Error("native_cancel_failed");},
        onUnsubscribe(){reentries++;rt.Dispose();oldReceive({d:"late_during_cleanup"});throw Error("native_unsubscribe_failed");}});
    rt=t.load(t.panel());oldReceive=[...t.events.values()].find(row=>row.name==="cw").fn;
    rt.CreateView("daily",{}).Open();t.admit();t.deliver(hello()[0]);const before=t.sent.length;
    rt.Dispose();assert.equal(rt.Inspect().active,false);assert.equal(rt.Inspect().counters.cleanup_failures,4);
    assert.equal(t.events.size,0);assert.equal(t.tables.size,0);assert.equal(t.removed.length,3);assert.equal(reentries,3);
    assert.equal(t.markers[0].deleteRequests,1);assert.equal(t.sent.length,before);assert.ok([...t.timers.values()].every(timer=>timer.canceled));
    rt.Dispose();assert.equal(reentries,3);assert.equal(t.markers[0].deleteRequests,1);
});
test("a reentrant replacement consumer receives no old commit hint or rejection",()=>{
    const t=fixture(),rt=t.load(t.panel());let hints=0,errors=0,afterReplacement=0;
    const view=rt.CreateView("daily",{onCommit(){rt.CreateView("daily",{onHint(){hints++;},onError(){errors++;}}).Open();afterReplacement=t.sent.length;throw Error("old_consumer_rejected");}});
    view.Open();t.admit();hello().forEach(t.deliver);
    W.Encode(schema,{schema:1,schema_sha256:C.sha256,session:900,epoch:1,view:3},1,
        [{record:R["daily:state"],field:F.known,value:1},{record:R["daily:state"],field:F.can_claim,value:1}],{full:true}).packets.forEach(t.deliver);
    assert.equal(hints,0);assert.equal(errors,0);assert.equal(t.sent.length,afterReplacement);assert.equal(rt.Inspect().active,true);
});
test("a replacement during a native send receives no old control or resync error",()=>{
    for(const operation of ["control","resync"]){
        let rt,armed=false,errors=0,afterReplacement=0;
        const t=fixture({onSend(){if(!armed)return;armed=false;
            rt.CreateView("daily",{onError(){errors++;}}).Open();afterReplacement=t.sent.length;
            if(operation==="resync")throw Error("old_native_send_failed");}});
        rt=t.load(t.panel());const view=rt.CreateView("daily",{});view.Open();t.admit();hello().forEach(t.deliver);
        W.Encode(schema,{schema:1,schema_sha256:C.sha256,session:900,epoch:1,view:3},1,
            [{record:R["daily:state"],field:F.known,value:1}],{full:true}).packets.forEach(t.deliver);
        armed=true;const result=operation==="control"?view.SendIntent("daily_claim",{target_day:1}):view.Resync(1);
        assert.equal(result.sent,false);assert.equal(errors,0);assert.equal(t.sent.length,afterReplacement);assert.equal(rt.Inspect().active,true);
    }
});
test("a reentrant world change during bootstrap receives no previous Hello error",()=>{
    let armed=true,errors=0;
    const t=fixture({onSend(){if(!armed)return;armed=false;t.admit("survival_test_world_B");throw Error("old_bootstrap_send_failed");}});
    const rt=t.load(t.panel());rt.CreateView("daily",{onError(){errors++;}}).Open();t.admit();
    assert.equal(errors,0);assert.equal(rt.ScopeIdentity().loading_identity,"survival_test_world_B");
    assert.equal(rt.Inspect().counters.hello_requests,1);assert.equal(t.sent.length,2);
});
test("bulk callbacks may dispose then throw without causing an old failure response",()=>{
    for(const phase of ["accept","complete"]){
        const t=fixture(),rt=t.load(t.panel());let completed=0;
        rt.CreateView("grid_static",{acceptBulk(){if(phase==="accept"){rt.Dispose();throw Error("retired_accept");}return true;},
            onBulk(){completed++;rt.Dispose();throw Error("retired_complete");}}).Open();t.admit();hello().forEach(t.deliver);
        W.Encode(schema,{schema:1,schema_sha256:C.sha256,session:900,epoch:1,view:6},1,
            [{record:R["grid:static:meta"],field:F.known,value:1},{record:R["grid:static:meta"],field:F.grid_scope,value:7}],{full:true}).packets.forEach(t.deliver);
        const before=t.sent.length;
        B.Encode({schema:1,schema_sha256:C.sha256,session:900,epoch:1,view:6,base_revision:1},7,String.fromCharCode(0x55).repeat(2304)).packets.forEach(t.deliverBulk);
        assert.equal(rt.Inspect().active,false);assert.equal(t.sent.length,before);assert.equal(t.events.size,0);assert.equal(t.tables.size,0);
        assert.equal(completed,phase==="complete"?1:0);
    }
});
test("stable owner checks are constant for one view versus the entire 33-view catalogue",()=>{
    const t=fixture(),rt=t.load(t.panel());rt.CreateView("daily",{});
    function measure(){const before=t.counts.panelChecks;for(let i=0;i<100;i++){rt.Inspect();rt.ScopeIdentity();}return t.counts.panelChecks-before;}
    const one=measure(),keys=["hud","daily","grid","selected","grid_static","production","vip","payment","public_beta",
        ...C.auxiliary.archive_projection.categories.map(row=>"archive:"+row.id),
        ...C.auxiliary.lottery_public.snapshots.map(row=>"lottery:"+row.selected_pool.id)];
    keys.forEach(key=>rt.CreateView(key,{}));const many=measure();
    assert.equal(one,400);assert.equal(many,one);assert.equal(t.counts.scheduled,0);assert.equal(t.counts.treeQueries,0);assert.equal(t.sent.length,0);
    Object.assign(costCounts,{views_small:1,views_large:rt.Inspect().views,entry_calls_per_sample:200,small_IsValid:one,large_IsValid:many,
        stable_created_timers:0,stable_sent_packets:0,tree_queries:0,native_measurement:false});
});

console.log(JSON.stringify({scope:"PURE_NODE_VM_REGRESSION_NOT_NATIVE_ACCEPTANCE",source:sourcePath,
    passed:results.filter(v=>v.passed).length,total:results.length,costCounts,results},null,2));
process.exitCode=results.every(v=>v.passed)?0:1;
