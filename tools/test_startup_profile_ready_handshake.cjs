"use strict";
// Real Lua startup module publishes into the real JS compact runtime. Engine,
// authentication and transport seams remain synthetic; this is not native FPS.
const assert=require("node:assert/strict"),fs=require("node:fs"),vm=require("node:vm");
const cp=require("node:child_process"),path=require("node:path");
const root=path.resolve(__dirname,".."),read=p=>fs.readFileSync(path.join(root,p),"utf8");
const fixture=read("scripts/vscripts/tests/test_startup_loading_service.lua");
const boundary=fixture.indexOf("-- Browser approval remains");
assert(boundary>0,"real startup fixture boundary required");
const exercise=`
local traces={}
for world=1,2 do
    local service=fixture(1)
    success(requests[1],{n5=1,n6=1})
    assets_done() ui(service,0) service.tick()
    assert_admitted(service)
    select_mode(service,"standard")
    profile_success(profile_requests[1])
    -- No thinker or manual tick after async completion, including new worlds.
    assert(service.snapshot().profiles_ready and service.is_player_ready(0))
    for _,state in ipairs(history) do
        traces[#traces+1]={session_id=state.session_id,
            admission_complete=state.admission_complete,profiles_ready=state.profiles_ready}
    end
end
print(require("core/json_encoder").encode(traces))
`;
const trace=JSON.parse(cp.execFileSync(process.env.LUA51||"C:/Program Files/lua/bin/lua5.1.exe",["-"],{
    cwd:root,encoding:"utf8",input:fixture.slice(0,boundary)+exercise}));
const cfg={};vm.runInNewContext(read("panorama/src/scripts/custom_game/common/ui_static_catalog.js"),{
    GameUI:{CustomUIConfig:()=>cfg}});
const API=require("../panorama/src/scripts/custom_game/common/compact_ui_runtime.js");
const W=require("../panorama/src/scripts/custom_game/common/compact_wire.js");
let state=null,changed;const sent=[];
const runtime=API.CreateRuntime({wire:W,catalogue:cfg.SurvivalUICatalog,
    send:(event,packet)=>{sent.push({event,packet});return true;},
    subscribe:()=>1,unsubscribe:()=>{},getLoading:()=>state,
    subscribeLoading:fn=>{changed=fn;return 2;},unsubscribeLoading:()=>{}});
for(const row of trace){state=row;changed();}
for(let n=0;n<100;n++)changed();
assert.equal(runtime.Inspect().counters.hello_requests,2);
assert.equal(sent.length,2);
assert(sent.every(x=>x.event==="cw"&&Object.keys(x.packet).length===1&&x.packet.d.length<=24));
console.log("STARTUP_REAL_LUA_JS_HANDSHAKE_PASS: worlds=2 Hello=2 repeated_state100_extra=0 thinker_advances_after_completion=0");
