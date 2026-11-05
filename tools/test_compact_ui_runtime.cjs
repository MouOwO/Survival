"use strict";
// Shared Lua server transport + JS runtime integration. Native API/scheduler
// doubles do not constitute a fresh engine byte-count or FPS measurement.
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm"),cp=require("node:child_process");
const W=require("../panorama/src/scripts/custom_game/common/compact_wire.js"),API=require("../panorama/src/scripts/custom_game/common/compact_ui_runtime.js");
const cfg={};vm.runInNewContext(fs.readFileSync("panorama/src/scripts/custom_game/common/ui_static_catalog.js","utf8"),{GameUI:{CustomUIConfig:()=>cfg}});
const C=cfg.SurvivalUICatalog.Data,schema=W.CompileLookup(C,1),F=Object.fromEntries(C.fields.map(f=>[f.name,f.id])),R=Object.fromEntries(C.records.filter(r=>!r.tombstone).map(r=>[r.key,r.id]));
let tests=0;function test(name,fn){fn();tests++;console.log("ok",name);}
function setup({memo,admitted=false,bulk}={}){
 let loading=admitted?{admission_complete:1,profiles_ready:1,session_id:"survival_test_world_A"}:null,listener,bulkListener,loadListener,now=0,disposed=false;
 const sent=[],timers=[],rt=API.CreateRuntime({wire:W,bulk,catalogue:C,memo,send(name,p){assert.equal(name,"cw");assert.deepEqual(Object.keys(p),["d"]);assert.ok(p.d.length<=24);sent.push(p);return true;},
  subscribe(name,fn){if(name==='gb'){assert.ok(bulk);bulkListener=fn;return 3;}assert.equal(name,"cw");listener=fn;return 1;},unsubscribe(){disposed=true;},getLoading:()=>loading,subscribeLoading(fn){loadListener=fn;return 2;},unsubscribeLoading(){},
  now:()=>now,schedule(ms,fn){const t={ms,fn,canceled:false};timers.push(t);return t;},cancel(t){t.canceled=true;}});
 return {rt,sent,timers,admit(value={admission_complete:1,profiles_ready:1,session_id:"survival_test_world_A"}){loading=value;loadListener();},receive(p){listener(p);},receiveBulk(p){assert.ok(bulkListener);bulkListener(p);},feed(ps){ps.forEach(listener);},advance(ms){now+=ms;for(const t of timers.splice(0))if(!t.canceled)t.fn();},isDisposed:()=>disposed};
}
function binding(session=900,view=3,epoch=1){return {schema:1,schema_sha256:C.sha256,session,epoch,view};}
function encode(ops,{session=900,view=3,epoch=1,revision=1,full=true}={}){return W.Encode(schema,binding(session,view,epoch),revision,ops,{full}).packets;}
function hello(session=900,hash=C.sha256){return encode(Array.from({length:8},(_,i)=>({record:R["wire:hello:"+(i+1)],field:F.count,value:parseInt(hash.slice(i*8,i*8+8),16)})),{session,view:1});}
function dailyOps(count=1){return [{record:R["daily:state"],field:F.known,value:1},{record:R["daily:state"],field:F.count,value:count}];}
function luaReplay(packets){
 const source=`package.path="scripts/vscripts/?.lua;"..package.path
local transport=require("ui/compact_ui_transport")
local json=require("core/json_encoder")
local lookup=dofile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua")
local budget=dofile("scripts/vscripts/config/generated/ui_compact_wire_budget.lua")
local tasks,out,received,cpu={}, {},0,0
local handle={}
local rt=transport.new({lookup=lookup,budget=budget,player=function()return handle end,authorize=function()return true end,
session_token=function()return 900 end,cpu_ms=function()return cpu end,
after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end,
emit=function(_,name,packet)assert(name=="cw");out[#out+1]=packet;return true end})
local F=lookup.field_by_name
local function snapshot()return {{record=lookup.by_key["daily:state"],field=F.known,value=1},{record=lookup.by_key["daily:state"],field=F.count,value=7}}end
rt.register_view(3,{snapshot=snapshot,open=snapshot,probe=function()end,close=function()end,
intent=function(_,action,args)assert(action=="daily_claim" and args.arg_a==25004 and args.request_token==1);received=received+1;return true end})
local packets={${packets.map(p=>`{d="${p.d}"}`).join(",")}}
for _,p in ipairs(packets)do assert(rt.receive(0,p));for n=1,10000 do local fn=tasks.compact_ui_dispatch;if not fn then break end;tasks.compact_ui_dispatch=nil;cpu=cpu+16;fn()end end
print(json.encode({packets=out,intents=received}))`;
 return JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["-"],{input:source,encoding:"utf8"}));
}
test("profile-ready admission sends one bootstrap and exact Lua server accepts JS controls/intents",()=>{
 const t=setup();let commits=0,value;const v=t.rt.CreateView("daily",{onCommit(tx,ids,read){commits++;value=read(R["daily:state"],F.count);}});
 v.Open();assert.equal(t.sent.length,0);t.admit();assert.equal(t.sent.length,1);for(let i=0;i<100;i++)t.admit();assert.equal(t.sent.length,1);
 let result=luaReplay(t.sent);t.feed(result.packets);assert.equal(t.rt.Inspect().ready,true);assert.ok(t.sent.length>1);
 result=luaReplay(t.sent);t.feed(result.packets);assert.equal(commits,1);assert.equal(value,7);
 const intent=v.SendIntent("daily_claim",{target_day:25004});assert.equal(intent.sent,true);assert.equal(intent.request_token,1);
 result=luaReplay(t.sent);assert.equal(result.intents,1);assert.ok(t.sent.every(p=>p.d.length<=24));
});
test("admission-only waits for the actual profile-ready event with zero Hello or polling",()=>{
 const t=setup(),view=t.rt.CreateView("daily",{});view.Open();
 const state={admission_complete:1,session_id:"survival_test_world_A"};
 for(let i=0;i<100;i++){t.admit(state);t.admit({...state,profiles_ready:0});}
 assert.equal(t.sent.length,0);assert.equal(t.timers.length,0);assert.equal(t.rt.Inspect().admitted,false);
 t.admit({...state,profiles_ready:1});assert.equal(t.sent.length,1);assert.equal(t.rt.Inspect().admitted,true);
 for(let i=0;i<100;i++)t.admit({...state,profiles_ready:1});
 assert.equal(t.sent.length,1);assert.equal(t.timers.length,0);
});
test("SHA mismatch rejects all business, shows local upgrade text and never loops",()=>{
 const t=setup({admitted:true}),errors=[];let commits=0;const v=t.rt.CreateView("daily",{onCommit:()=>commits++,onError:code=>errors.push(code)});v.Open();const sent=t.sent.length;
 t.feed(hello(900,(C.sha256[0]==="a"?"b":"a")+C.sha256.slice(1)));assert.equal(t.rt.Inspect().upgrade_required,true);assert.equal(t.rt.Inspect().ready,false);assert.ok(t.rt.Inspect().error_text.includes("更新游戏"));
 for(let i=0;i<100;i++)t.feed(encode(dailyOps()));assert.equal(commits,0);assert.equal(t.sent.length,sent);assert.equal(v.SendIntent("daily_claim",{target_day:25004}).sent,false);assert.deepEqual(errors,["schema_mismatch"]);
});
test("hello is exactly eight registered words with count field",()=>{
 const t=setup({admitted:true});t.rt.CreateView("daily",{}).Open();const ops=Array.from({length:8},(_,i)=>({record:R["wire:hello:"+(i+1)],field:F.count,value:parseInt(C.sha256.slice(i*8,i*8+8),16)}));ops.push({record:R["daily:state"],field:F.known,value:1});t.feed(encode(ops,{view:1}));assert.equal(t.rt.Inspect().upgrade_required,true);
});
test("higher epoch requires full, old epoch/session are retired and missing base resync is once",()=>{
 const t=setup({admitted:true});let commits=0;const v=t.rt.CreateView("daily",{onCommit:()=>commits++});v.Open();t.feed(hello());t.feed(encode(dailyOps(1)));assert.equal(v.Read(R["daily:state"],F.count),1);
 t.feed(encode(dailyOps(2),{epoch:2}));assert.equal(v.Read(R["daily:state"],F.count),2);const before=t.sent.length;
 t.feed(encode(dailyOps(99),{epoch:1,full:false,revision:2}));assert.equal(v.Read(R["daily:state"],F.count),2);
 for(let i=0;i<10;i++)t.feed(encode(dailyOps(3),{epoch:3,full:false,revision:2}));assert.equal(t.sent.length,before+1);assert.equal(v.Inspect().resync_pending,true);
 t.feed(encode(dailyOps(4),{epoch:4}));assert.equal(v.Inspect().resync_pending,false);
 t.feed(hello(901));t.feed(encode(dailyOps(5),{session:901}));const kept=commits;t.feed(encode(dailyOps(99),{session:900,epoch:5}));t.feed(hello(900));assert.equal(commits,kept);assert.equal(v.Read(R["daily:state"],F.count),5);
 assert.deepEqual(t.rt.Inspect().retired_sessions,[900]);
});
test("Close aborts assemblies and only dispatches small daily hints",()=>{
 const t=setup({admitted:true}),hints=[];let commits=0;const v=t.rt.CreateView("daily",{onCommit:()=>commits++,onHint:x=>hints.push(x)});v.Open();t.feed(hello());t.feed(encode(dailyOps()));v.Close();const before=commits;
 t.feed(encode(dailyOps(99),{full:false,revision:2}));assert.equal(commits,before);
 t.feed(encode([{record:R["daily:state"],field:F.known,value:1},{record:R["daily:state"],field:F.can_claim,value:1}],{epoch:2}));assert.equal(commits,before);assert.deepEqual(hints,[{known:1,claimable:1}]);
 const sent=t.sent.length;t.feed(encode(dailyOps(99),{epoch:3}));assert.equal(commits,before);assert.equal(t.sent.length,sent,"Closed view corruption cannot reopen a full subscription via resync");
 v.Probe();assert.equal(v.Inspect().desired,"probe");
});
test("business rejection requests one resync until a valid applied full",()=>{
 const t=setup({admitted:true});let bad=true;const v=t.rt.CreateView("daily",{onCommit(){if(bad)throw new Error("application_rejected");}});v.Open();t.feed(hello());const sent=t.sent.length;
 t.feed(encode(dailyOps()));t.feed(encode(dailyOps(),{epoch:2}));assert.equal(t.sent.length,sent+1);assert.equal(v.Inspect().resync_pending,true);
 bad=false;t.feed(encode(dailyOps(),{epoch:3}));assert.equal(v.Inspect().resync_pending,false);v.Resync(5);v.Resync(5);assert.equal(t.sent.length,sent+2);
});
test("1000 unchanged deltas create no bridge writes, timers or callbacks",()=>{
 const t=setup({admitted:true});let commits=0;const v=t.rt.CreateView("daily",{onCommit:()=>commits++});v.Open();t.feed(hello());t.feed(encode(dailyOps()));const sent=t.sent.length,timers=t.timers.length;
 for(let revision=2;revision<=1001;revision++)t.feed(encode(dailyOps(),{revision,full:false}));assert.equal(commits,1);assert.equal(t.sent.length,sent);assert.equal(t.timers.length,timers);
});
test("tokens/revisions survive view disposal and local runtime reload without reuse",()=>{
 const memo={intent_token:0,sessions:{},retired:[]},t=setup({memo,admitted:true});let v=t.rt.CreateView("daily",{});v.Open();t.feed(hello());assert.equal(v.SendIntent("daily_claim",{target_day:1}).request_token,1);v.Dispose();v=t.rt.CreateView("daily",{});v.Open();assert.equal(v.SendIntent("daily_claim",{target_day:1}).request_token,2);
 const prior=W.PeekHeader(t.sent.at(-1)).revision;t.rt.Dispose();const next=setup({memo,admitted:true});const fresh=next.rt.CreateView("daily",{});fresh.Open();next.feed(hello());assert.equal(fresh.SendIntent("daily_claim",{target_day:1}).request_token,3);assert.ok(W.PeekHeader(next.sent.at(-1)).revision>prior);
 memo.intent_token=16383;assert.equal(fresh.SendIntent("daily_claim",{target_day:1}).error,"token_exhausted");
});
test("actual loading identity namespaces aliases; missing identity cannot bootstrap",()=>{
 const t=setup();t.admit({admission_complete:1,profiles_ready:1});assert.equal(t.sent.length,0,"No guessed world identity");
 const v=t.rt.CreateView("daily",{});v.Open();t.admit();t.feed(hello(900));t.feed(hello(901));assert.deepEqual(t.rt.Inspect().retired_sessions,[900]);
 t.admit({admission_complete:1,profiles_ready:1,session_id:"survival_test_world_B"});assert.deepEqual(t.rt.Inspect().retired_sessions,[]);t.feed(hello(900));assert.equal(t.rt.Inspect().ready,true);assert.equal(v.Inspect().session,900);
 t.feed(encode(dailyOps(12)));assert.equal(v.Read(R["daily:state"],F.count),12);
});
test("view ids follow immutable archive/category and pool catalogue order",()=>{
 const t=setup();C.auxiliary.archive_projection.categories.forEach((r,i)=>assert.equal(t.rt.CreateView("archive:"+r.id,{}).Inspect().id,101+i));C.auxiliary.lottery_public.snapshots.forEach((r,i)=>assert.equal(t.rt.CreateView("lottery:"+r.selected_pool.id,{}).Inspect().id,201+i));assert.throws(()=>t.rt.CreateView("archive:invented",{}),/compact_view_key_unknown/);
});
test("lottery read action 7 is typed and allowed only in its pool view",()=>{
 const t=setup({admitted:true}),lottery=t.rt.CreateView("lottery:map",{}),daily=t.rt.CreateView("daily",{});lottery.Open();daily.Open();t.feed(hello());
 const result=lottery.SendIntent("lottery_read",{pool_record:R["lottery:pool:map"],read_action:1});assert.equal(result.sent,true);assert.equal(daily.SendIntent("lottery_read",{pool_record:R["lottery:pool:map"],read_action:1}).error,"action_view_mismatch");assert.equal(lottery.SendIntent("lottery_read",{pool_record:R["lottery:pool:map"],read_action:4}).error,"intent_argument_invalid");
});
test("disposed callbacks and malformed frames are bounded and inactive",()=>{
 const t=setup({admitted:true}),v=t.rt.CreateView("daily",{});v.Open();t.feed(hello());const frame=encode(dailyOps())[0];v.Dispose();t.receive(frame);t.rt.Dispose();const sent=t.sent.length;for(let i=0;i<100;i++){t.receive({d:"A".repeat(9999)});t.receive(frame);}assert.equal(t.sent.length,sent);assert.equal(t.isDisposed(),true);
});
test("independent full C2S inputs recover after partial loss without replay or business nonces",()=>{
 const t=setup({admitted:true}),grid=t.rt.CreateView("grid",{});t.feed(hello());grid.Open();
 const args={grid_session:88,grid_request:1,grid_profile:R["grid:profile:ability_build_arrow_tower"],grid_actor:11,grid_ability:12,grid_x_hi:0,grid_x_lo:0,grid_y_hi:0,grid_y_lo:0,grid_z_hi:0,grid_z_lo:0};
 assert.equal(grid.SendInput(2,args).sent,true);grid.SendInput(2,{...args,grid_request:2});grid.Close();grid.Open();grid.SendInput(2,{...args,grid_request:3});
 assert.equal(t.rt.Inspect().intent_token,0);
 const groups=new Map();for(const packet of t.sent){const h=W.PeekHeader(packet);if(h.view!==4)continue;assert.equal(h.full,true);if(!groups.has(h.revision))groups.set(h.revision,[]);groups.get(h.revision).push(packet);}
 assert.ok(groups.get(2).length>1);
 const forged=W.Encode(schema,binding(900,4,1),5,[{record:R["grid:input"],field:F.grid_action,value:2},{record:R["grid:input"],field:F.grid_request,value:99}],{full:true}).packets;
 const packets=[t.sent[0],...groups.get(1),groups.get(2)[0],...groups.get(3),...groups.get(3),...groups.get(4),...groups.get(2).slice(1),...forged,...groups.get(5),...groups.get(6)];
 const source=`package.path='scripts/vscripts/?.lua;'..package.path
local W=require('ui/compact_wire');local L=require('config/generated/ui_static_catalog_lookup');local T=require('ui/compact_ui_transport');local cpu,tasks,accepted=0,{},{}
local handle={};local rt=T.new({lookup=L,budget=require('config/generated/ui_compact_wire_budget'),player=function()return handle end,authorize=function()return true end,session_token=function()return 900 end,cpu_ms=function()return cpu end,after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end,emit=function()return true end})
rt.register_view(4,{snapshot=function()return{}end,input_record='grid:input',input_action_field='grid_action',input_actions={[2]=true},input_fields={grid_session=true,grid_request=true,grid_profile=true,grid_actor=true,grid_ability=true,grid_x_hi=true,grid_x_lo=true,grid_y_hi=true,grid_y_lo=true,grid_z_hi=true,grid_z_lo=true},input=function(_,action,args)accepted[#accepted+1]=args.grid_request;return true end})
for _,p in ipairs({${packets.map(p=>`{d='${p.d}'}`).join(",")}})do rt.receive(0,p);for n=1,1000 do local fn=tasks.compact_ui_dispatch;if not fn then break end;tasks.compact_ui_dispatch=nil;cpu=cpu+16;fn()end end
assert(#accepted==2 and accepted[1]==2 and accepted[2]==3,'loss/replay/closed input reached business handler');print('C2S_FULL_RECOVERY_PASS')`;
 assert.match(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["-"],{input:source,encoding:"utf8"}),/C2S_FULL_RECOVERY_PASS/);
});
test("two independent HUD XML roots reuse one same-build same-schema runtime in either order",()=>{
 const source=fs.readFileSync("panorama/src/scripts/custom_game/common/compact_ui_runtime.js","utf8");
 for(const order of [["hud","archive"],["archive","hud"]]){
  const cfg={SurvivalCompactWire:W,SurvivalUICatalog:{Data:C}},events=new Map();let subscriptions=0,unsubscribed=0;
  function load(name){const env={GameUI:{CustomUIConfig:()=>cfg},GameEvents:{Subscribe(event,fn){subscriptions++;events.set(subscriptions,fn);return subscriptions;},Unsubscribe(id){unsubscribed++;events.delete(id);},SendCustomGameEventToServer(){}},CustomNetTables:{GetTableValue(){return null;},SubscribeNetTableListener(){return 1;},UnsubscribeNetTableListener(){}},$:{GetContextPanel(){return {IsValid:()=>true};},CreatePanel(){return {IsValid:()=>true,DeleteAsync(){}};},RegisterEventHandler(){throw Error("native_invalid_event_type");},Schedule(){return 1;},CancelScheduled(){}},Game:{GetLocalPlayerID:()=>0}};vm.runInNewContext(source,env,{filename:name});}
  load(order[0]);const first=cfg.SurvivalCompactRuntime,view=first.CreateView("daily",{});view.Open();load(order[1]);assert.equal(cfg.SurvivalCompactRuntime,first);assert.equal(subscriptions,1);assert.equal(unsubscribed,0);assert.equal(view.Inspect().active,true);
  first.Dispose();load(order[0]);assert.notEqual(cfg.SurvivalCompactRuntime,first);assert.equal(subscriptions,2);
 }
});
test("production consumes separate monotonic tokens and cannot use another view",()=>{
 const t=setup({admitted:true}),p=t.rt.CreateView("production",{}),daily=t.rt.CreateView("daily",{});
 p.Open();daily.Open();t.feed(hello());
 assert.equal(p.Inspect().id,7);
 const args={entity:122,definition_record:1,selection:3};
 assert.equal(daily.SendIntent("production_train",args).error,"action_view_mismatch");
 assert.equal(p.SendIntent("daily_claim",{target_day:3}).error,"action_view_mismatch");
 assert.equal(p.SendIntent("production_cancel",{entity:122,job_handle:0,selection:3}).error,"intent_argument_invalid");
 for(const [index,action] of ["production_train","production_research","production_auto","production_cancel"].entries()){
  const value=p.SendIntent(action,action==="production_cancel"?{entity:122,job_handle:4000000000,selection:3}:args);
  assert.equal(value.sent,true);assert.equal(value.request_token,index+1);
 }
 const rx=W.NewReceiver(schema,binding(900,7,1));let operations=0;
 for(const packet of t.sent){const h=W.PeekHeader(packet);if(h.view!==7)continue;assert.equal(h.full,true);const tx=rx.Accept(packet);if(tx.pending)continue;rx.Commit(tx);const token=tx.changes.find(c=>c.field===F.request_token);if(token){operations++;assert.equal(token.value,operations);}}
 assert.equal(operations,4);assert.ok(t.sent.every(packet=>packet.d.length<=24));
 p.Close();assert.equal(p.SendIntent("production_train",args).error,"not_ready");
});
test("capability and beta claims use separate typed views with no client reward/account arguments",()=>{
 const t=setup({admitted:true}),p=t.rt.CreateView("payment",{}),b=t.rt.CreateView("public_beta",{});
 p.Open();b.Open();assert.equal(t.rt.ScopeIdentity().loading_identity,"survival_test_world_A");
 assert.equal(t.rt.ScopeIdentity().ready,false);t.feed(hello());
 assert.equal(t.rt.ScopeIdentity().session,900);assert.equal(t.rt.ScopeIdentity().ready,true);
 assert.equal(p.SendIntent("payment_capability",{}).request_token,1);
 assert.equal(b.SendIntent("public_beta_claim",{}).request_token,2);
 assert.equal(p.SendIntent("public_beta_claim",{}).error,"action_view_mismatch");
 assert.equal(b.SendIntent("payment_capability",{}).error,"action_view_mismatch");
 for(const args of [{quantity:2},{day:1},{account_id:3},{arg_a:1}])assert.equal(b.SendIntent("public_beta_claim",args).error,"intent_arguments_forbidden");
 assert.equal(t.rt.Inspect().intent_token,2,"invalid inputs never reserve business tokens");
 t.admit({admission_complete:0,profiles_ready:0,session_id:"survival_world_B"});assert.equal(t.rt.ScopeIdentity().ready,false);
 assert.equal(p.SendIntent('payment_capability',{}).error,'not_ready','a prior alias cannot authorize requests during an unready transition');
 t.admit({admission_complete:1,profiles_ready:1,session_id:"survival_world_B"});
 assert.equal(t.rt.ScopeIdentity().loading_identity,"survival_world_B");assert.equal(t.rt.ScopeIdentity().ready,false,'new namespace still requires a fresh Hello');
});
test("destroying the actual owner retires shared runtime without a fabricated native deletion event",()=>{
 const source=fs.readFileSync('panorama/src/scripts/custom_game/common/compact_ui_runtime.js','utf8');
 const cfg={SurvivalCompactWire:W,SurvivalUICatalog:{Data:C}},owners=[],callbacks=[];let subscriptions=0,unsubscribed=0;
 function load(){const owner={valid:true,IsValid(){return this.valid;}};owners.push(owner);vm.runInNewContext(source,{GameUI:{CustomUIConfig:()=>cfg},
  GameEvents:{Subscribe(name,fn){subscriptions++;callbacks.push(fn);return subscriptions;},Unsubscribe(){unsubscribed++;},SendCustomGameEventToServer(){}},
  CustomNetTables:{GetTableValue:()=>null,SubscribeNetTableListener:()=>1,UnsubscribeNetTableListener(){}},
  $:{GetContextPanel:()=>owner,CreatePanel(){const marker={valid:true,IsValid(){return this.valid&&owner.valid;},DeleteAsync(){this.valid=false;}};return marker;},RegisterEventHandler(){throw Error("native_invalid_event_type");},Schedule:()=>1,CancelScheduled(){}},Game:{}});}
 load();const old=cfg.SurvivalCompactRuntime,view=old.CreateView('daily',{});load();assert.equal(cfg.SurvivalCompactRuntime,old);
 assert.equal(subscriptions,1);owners[0].valid=false;callbacks[0]({d:'late'});assert.equal(old.Inspect().active,false);assert.equal(view.Inspect().active,false);assert.equal(unsubscribed,1);
 load();assert.notEqual(cfg.SurvivalCompactRuntime,old);assert.equal(subscriptions,2);callbacks[0]({d:'late'});assert.equal(cfg.SurvivalCompactRuntime.Inspect().active,true,'old native callback cannot dispose replacement');
});
test("infrequent grid bulk is negotiated, bound to metadata and cancelled independently of short cw",()=>{
 const B=require('../panorama/src/scripts/custom_game/common/compact_grid_bulk_wire.js');
 const t=setup({admitted:true,bulk:B}),completed=[];
 const view=t.rt.CreateView('grid_static',{acceptBulk:h=>h.scope===7&&h.base_revision===1,onBulk:(h,raw)=>completed.push({h,raw})});
 view.Open();t.feed(hello());
 const meta=[{record:R['grid:static:meta'],field:F.known,value:1},{record:R['grid:static:meta'],field:F.grid_scope,value:7}];
 t.feed(encode(meta,{view:6}));
 const raw=String.fromCharCode(0x55).repeat(2304),make=(epoch=1,scope=7,session=900)=>B.Encode({...binding(session,6,epoch),base_revision:1},scope,raw).packets;
 const packets=make();assert.equal(packets.length,4);assert.ok(packets.every(p=>p.d.length<=896));
 make(1,8).forEach(t.receiveBulk);make(1,7,901).forEach(t.receiveBulk);assert.equal(completed.length,0);
 t.receiveBulk(packets[0]);assert.ok(t.timers.some(timer=>timer.ms===5000&&!timer.canceled));
 view.Close();const sent=t.sent.length;t.advance(6000);packets.slice(1).forEach(t.receiveBulk);
 assert.equal(completed.length,0);assert.equal(t.sent.length,sent,'closed assembly cannot send a resync or apply late bulk');
 view.Open();t.feed(encode(meta,{view:6,epoch:2}));packets.forEach(t.receiveBulk);assert.equal(completed.length,0);
 const current=make(2);current.forEach(t.receiveBulk);assert.equal(completed.length,1);assert.equal(completed[0].raw,raw);
 current.forEach(t.receiveBulk);assert.equal(completed.length,1,'replayed bulk cannot reapply a bitmap');
 assert.ok(t.sent.every(p=>p.d.length<=24),'rare large S2C never loosens the cw/C2S guard');
 view.Dispose();t.rt.Dispose();current.forEach(t.receiveBulk);assert.equal(completed.length,1);
});
console.log(JSON.stringify({status:"PASS_COMPACT_UI_RUNTIME_JS_LUA_SYNTHETIC_NOT_NATIVE",tests,native_calls:0,network_calls:0,sdk_calls:0,stable_sends:0,stable_timers:0}));
