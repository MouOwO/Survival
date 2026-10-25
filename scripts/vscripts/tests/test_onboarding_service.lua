package.path = "./scripts/vscripts/?.lua;" .. package.path
-- Behaviour tests: a real event bus, synthetic engine entities, and manually
-- completed authoritative persistence requests. No client can finish a step.
package.loaded["core/test_access_policy"] = {enabled=function() return false end,allowed=function() return true end,enforce=function() return true end}
local bus = require("core/event_bus")
local events = require("core/events")
local passed = 0
local failures = {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result={};for key,child in pairs(value) do result[key]=copy(child) end;return result
end
local function active(value) return value.active==true or value.active==1 end
local function step(value)
    local key=value.step_id or value.step or value.stage
    if type(key)=="table" then key=key.id or key.kind end
    if type(key)=="number" then return ({"wall","main_city","worker","tower"})[key] end
    return key
end
local function check(value,message) assert(value,message) end

local function fixture()
    bus.reset()
    package.loaded["systems/onboarding_service"]=nil
    _G.SURVIVAL_ONBOARDING_RUNTIME=nil
    local f={listeners={},packets={},tasks={},reads={},finishes={},metadata={},connected={},defeated={},builders={},players={},entities={},buildings={}}
    local now,next_entity=0,1000
    function Vector(x,y,z) return {x=x,y=y,z=z or 0} end
    function IsServer() return true end
    function IsInToolsMode() return false end
    function GetMapName() return "template_map" end
    function Time() return now end
    DOTA_TEAM_GOODGUYS=2
    DOTA_CONNECTION_STATE_CONNECTED=2
    DOTA_CONNECTION_STATE_DISCONNECTED=3
    PATTACH_WORLDORIGIN=0
    GameRules={GetGameTime=function() return now end,GetDOTATime=function() return now end,
        GetGameModeEntity=function() return GameRules end}
    local function unit(owner,position,name)
        next_entity=next_entity+1
        local value={owner=owner,position=position or Vector(0,0,0),alive=true,id=next_entity,name=name or "npc_survival_builder",survival_player_id=owner}
        function value:IsNull() return false end
        function value:IsAlive() return self.alive end
        function value:entindex() return self.id end
        function value:GetEntityIndex() return self.id end
        function value:GetAbsOrigin() return self.position end
        function value:GetPlayerOwnerID() return self.engine_owner==nil and self.owner or self.engine_owner end
        function value:GetUnitName() return self.name end
        function value:GetTeamNumber() return 2 end
        function value:HasModifier(name) return name=="modifier_building_under_construction" and self.constructing==true end
        f.entities[value.id]=value
        return value
    end
    f.unit=unit
    for pid=0,1 do
        local id=pid
        f.players[pid]={GetPlayerID=function() return id end,IsNull=function() return false end}
        f.entities[100+pid]=f.players[pid]
        f.builders[pid]=unit(pid,Vector(pid*2048,0,0))
        f.connected[pid]=true
        f.metadata[pid]={loaded=false,required=false,status="pending",version=1}
    end
    PlayerResource={
        GetPlayer=function(_,pid) return f.connected[pid] and f.players[pid] or nil end,
        IsValidPlayerID=function(_,pid) return f.players[pid]~=nil end,
        GetConnectionState=function(_,pid) return f.connected[pid] and 2 or 3 end,
        GetSteamAccountID=function(_,pid) return 100+pid end,
        GetTeam=function() return 2 end,
    }
    EntIndexToHScript=function(index) return f.entities[index] end
    CustomGameEventManager={
        RegisterListener=function(_,name,callback) f.listeners[name]=callback;return name end,
        Send_ServerToPlayer=function(_,player,name,payload) f.packets[#f.packets+1]={pid=player:GetPlayerID(),name=name,payload=copy(payload)} end,
        UnregisterListener=function(_,name) f.listeners[name]=nil end,
    }
    ParticleManager={
        CreateParticleForPlayer=function() next_entity=next_entity+1;return next_entity end,
        CreateParticle=function() next_entity=next_entity+1;return next_entity end,
        SetParticleControl=function() end,SetParticleAlwaysSimulate=function() end,
        SetParticleShouldCheckFoW=function() end,DestroyParticle=function() end,ReleaseParticleIndex=function() end,
    }
    local scheduler={}
    function scheduler.after(delay,callback,key)
        local id=key or tostring({})
        f.tasks[id]={at=now+delay,callback=callback};return id
    end
    function scheduler.every(delay,callback,key)
        return scheduler.after(delay,function() local value=callback();if value~=false then return delay end end,key)
    end
    function scheduler.cancel(key) f.tasks[key]=nil end
    function f.advance(seconds)
        now=now+seconds
        local due={}
        for key,task in pairs(f.tasks) do if task.at<=now then due[#due+1]={key=key,task=task} end end
        for _,entry in ipairs(due) do
            if f.tasks[entry.key]==entry.task then
                f.tasks[entry.key]=nil
                local interval=entry.task.callback()
                if type(interval)=="number" and interval>0 and not f.tasks[entry.key] then
                    f.tasks[entry.key]={at=now+interval,callback=entry.task.callback}
                end
            end
        end
    end
    package.loaded["core/scheduler"]=scheduler
    package.loaded["systems/match_setup_service"]={
        get_mode=function() return "standard" end,get_profile_mode=function() return "standard" end,
        is_mode_selected=function() return true end,get_session_id=function() return "onboarding_service_fixture" end,
    }
    package.loaded["systems/player_profile_service"]={
        get_profile=function(pid) return f.players[pid] and {account_id=tostring(100+pid),save={archive={}},revision=1} end,
        get_account_profile=function(pid) return f.players[pid] and {account_id=tostring(100+pid),save={archive={}},revision=1} end,
        is_loaded_for_account=function(pid) return f.players[pid]~=nil end,
    }
    package.loaded["systems/player_context_service"]={
        active_player_ids=function() return {0,1} end,is_defeated=function(pid) return f.defeated[pid]==true end,
        owner_player_id=function(value) return value and value.survival_player_id end,
        is_owned_by=function(pid,value) return value and value.survival_player_id==pid end,
        slot=function(pid) return {slot_id=pid,builder_spawn_marker="player_"..pid.."_builder_spawn"} end,
    }
    package.loaded["systems/onboarding_persistence"]={
        init=function() end,
        get=function(pid) return copy(f.metadata[pid] or {loaded=false,required=false,status="pending",version=1}) end,
        ensure=function(pid,callback)
            if f.metadata[pid].loaded then callback(copy(f.metadata[pid]));return {ok=true} end
            f.reads[#f.reads+1]={pid=pid,callback=callback};return {ok=true,pending=true}
        end,
        finish=function(pid,outcome,callback)
            f.finishes[#f.finishes+1]={pid=pid,outcome=outcome,callback=callback};return {ok=true,pending=true}
        end,
    }
    function f.metadata_reply(pid,status)
        f.metadata[pid]={ok=true,loaded=true,required=status=="required",status=status,version=1}
        local callbacks={}
        for index=#f.reads,1,-1 do if f.reads[index].pid==pid then callbacks[#callbacks+1]=table.remove(f.reads,index).callback end end
        for _,callback in ipairs(callbacks) do callback(copy(f.metadata[pid])) end
    end
    function f.finish_reply(index,ok)
        local entry=f.finishes[index]
        check(entry~=nil,"expected a durable finish request")
        if ok then f.metadata[entry.pid]={ok=true,loaded=true,required=false,status=entry.outcome,version=1} end
        entry.callback(ok and copy(f.metadata[entry.pid]) or {ok=false,error="network_timeout",loaded=true,required=true,status="required",version=1})
    end
    function f.targets(pid)
        local offset=pid*2048
        return {wall={x=offset+256,y=256,z=0,width=64,height=64,footprint_x=4,footprint_y=4},
            main_city={x=offset+512,y=512,z=0,width=64,height=64,footprint_x=4,footprint_y=4},
            tower={x=offset+768,y=768,z=0,width=64,height=64,footprint_x=2,footprint_y=2},
            existing={},center={x=offset+512,y=512,z=0}}
    end
    package.loaded["systems/onboarding_targets"]={get=function(pid) return f.targets(pid) end}
    bus.handle_request(events.BUILDER_GET_REQUEST,function(payload)
        return {ok=f.builders[payload.player_id]~=nil,builder=f.builders[payload.player_id]}
    end)
    bus.handle_request(events.BUILDING_LIST_REQUEST,function(payload)
        local rows={};for _,row in pairs(f.buildings) do if row.player_id==payload.player_id then rows[#rows+1]=row end end
        return {ok=true,buildings=rows}
    end)
    bus.handle_request(events.BUILDING_QUERY_REQUEST,function(payload) return f.buildings[payload.entindex] end)
    local service=require("systems/onboarding_service")
    f.service=service
    function f.start(pid)
        service.refresh(pid)
        f.metadata_reply(pid,"required")
        service.refresh(pid)
        check(active(service.snapshot(pid)),"required account with its own valid builder must start onboarding")
    end
    function f.build(pid,kind,options)
        options=options or {}
        local target=f.targets(pid)[kind]
        local building_id=kind=="tower" and "arrow_tower" or kind
        local value=unit(options.owner or pid,Vector(target.x+(options.dx or 0),target.y+(options.dy or 0),target.z),building_id)
        value.survival_building_id=building_id
        value.constructing=options.constructing==true
        local data={player_id=options.player_id or pid,building_id=building_id,unit=value,entindex=value:entindex(),
            constructing=options.constructing==true,position=value:GetAbsOrigin(),team=2,level=1}
        if not options.no_record then f.buildings[value:entindex()]=data end
        bus.emit(events.BUILDING_CREATED,data)
        return value,data
    end
    service.init()
    f.advance(0)
    return f
end

local function test(name,callback)
    local ok,error_code=pcall(callback)
    if ok then passed=passed+1
    else failures[#failures+1]=name..": "..tostring(error_code) end
end

test("authoritative metadata and live own builder gate activation",function()
    local f=fixture()
    check(not active(f.service.snapshot(0)),"pending metadata must not lock or classify a player as old")
    f.metadata_reply(0,"legacy");f.service.refresh(0)
    check(not active(f.service.snapshot(0)),"legacy accounts must not enter a first-login guide")
    f.builders[1]=nil
    f.metadata_reply(1,"required");f.service.refresh(1)
    check(not active(f.service.snapshot(1)),"no builder means no input lock")
    f.builders[1]=f.unit(0)
    f.service.refresh(1)
    check(not active(f.service.snapshot(1)),"another player's builder cannot activate this guide")
    f.builders[1]=f.unit(1)
    bus.emit(events.BUILDER_READY,{player_id=1,builder=f.builders[1]})
    f.service.refresh(1)
    check(active(f.service.snapshot(1)) and step(f.service.snapshot(1))=="wall","builder readiness starts at the stair wall")
end)

test("build gate follows the current type and snapped legal center",function()
    local f=fixture();f.start(0)
    local at=f.targets(0).wall
    local function allowed(id,x,y)
        return f.service.can_build({player_id=0,building_id=id,position=Vector(x,y,0),builder=f.builders[0],footprint={x=4,y=4}})
    end
    check(allowed("wall",at.x,at.y).ok,"current stair wall center must be usable")
    check(allowed("wall",at.x+15,at.y-15).ok,"clicks snapping to the marked center must be usable")
    check(not allowed("wall",at.x+64,at.y).ok,"another grid center must be denied")
    check(not allowed("main_city",at.x,at.y).ok,"future building types must be denied")
    local unguided=f.service.can_build({player_id=1,building_id="wall",position=Vector(0,0,0)})
    check(unguided==nil or unguided.ok~=false,"an unguided player must remain independent")
end)

test("an existing misplaced unique wall explains skipping without completing or mutating buildings",function()
    local f=fixture()
    f.targets=function() return nil,"misplaced_wall" end
    f.start(0)
    local snapshot=f.service.snapshot(0)
    check(active(snapshot) and snapshot.waiting and step(snapshot)=="wall",
        "a misplaced wall stays incomplete and retains the guide's skip affordance")
    check(snapshot.error=="已有城墙不在引导位置，请跳过本次引导继续游戏。",
        "the unique wall conflict needs a clear actionable explanation")
    check(#f.finishes==0,"a misplaced wall must not falsely persist completion")
    check(f.service.skip(0)==true and not active(f.service.snapshot(0)),
        "skipping the blocked guide immediately returns normal gameplay")
    check(#f.finishes==1 and f.finishes[1].outcome=="skipped")
    local other=fixture()
    other.targets=function() return nil,"onboarding_wall_position_unavailable:occupied" end
    other.start(0)
    check(other.service.snapshot(0).error=="引导区域暂不可用，请稍候或选择跳过。",
        "temporary ordinary target occupancy keeps its existing retry explanation")
end)

test("only complete owned buildings at the marked position advance",function()
    local f=fixture();f.start(0)
    f.build(0,"wall",{player_id=1})
    f.build(0,"wall",{owner=1})
    f.build(0,"wall",{constructing=true})
    f.build(0,"wall",{dx=33})
    f.build(0,"main_city")
    check(step(f.service.snapshot(0))=="wall","foreign, incomplete, misplaced or future buildings cannot complete the wall step")
    f.build(0,"wall",{dx=31})
    check(step(f.service.snapshot(0))=="main_city")
    f.build(0,"wall")
    check(step(f.service.snapshot(0))=="main_city","duplicate previous-step events cannot advance")
    f.build(0,"main_city")
    check(step(f.service.snapshot(0))=="worker")
end)

test("training needs one ordinary lumberjack from the guided city",function()
    local f=fixture();f.start(0);f.build(0,"wall")
    local city=f.build(0,"main_city")
    local function worker(patch)
        local value={player_id=0,count_delta=1,worker_type="lumberjack",source_entindex=city:entindex(),unit=f.unit(0)}
        for key,child in pairs(patch or {}) do value[key]=child end
        bus.emit(events.WORKER_CHANGED,value)
    end
    for _,bad in ipairs({{player_id=1},{count_delta=-1},{count_delta=0},{count_delta=2},{worker_type="repairer"},
        {super_lumberjack=true},{source_entindex=city:entindex()+999}}) do
        worker(bad)
        check(step(f.service.snapshot(0))=="worker","unrelated training packets must not complete the worker step")
    end
    worker()
    check(step(f.service.snapshot(0))=="tower")
    check(f.service.snapshot(0).description:find("农民会自动采集木材，木材足够后",1,true),
        "the tower step explains the normal resource wait instead of granting free materials")
    f.build(0,"tower")
    check(not active(f.service.snapshot(0)),"the fourth server-observed action must release the input mask immediately")
    check(#f.finishes==1 and f.finishes[1].outcome=="completed","completion is persisted once")
    f.finish_reply(1,false)
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
    check(not active(f.service.snapshot(0)),"failed persistence must not revive a locally completed guide")
    f.advance(60)
    check(#f.finishes>=2 and f.finishes[#f.finishes].outcome=="completed","failed completion persistence must retry in the background")
end)

test("authoritative ownership survives native cache lag and rejects unknown owners",function()
    local f=fixture();f.start(0)
    f.builders[0].engine_owner=-1
    f.service.refresh(0)
    check(active(f.service.snapshot(0)),"registered builder remains owned despite an uninitialized native owner cache")
    local target=f.targets(0).wall
    local unknown=f.unit(0,Vector(target.x,target.y,target.z),"building_wall")
    unknown.survival_player_id=nil
    bus.emit(events.BUILDING_CREATED,{player_id=0,building_id="wall",unit=unknown,entindex=unknown:entindex()})
    check(step(f.service.snapshot(0))=="wall","an unknown authoritative owner cannot inherit the native player-zero default")
    unknown.survival_player_id=0;unknown.engine_owner=-1
    bus.emit(events.BUILDING_CREATED,{player_id=0,building_id="wall",unit=unknown,entindex=unknown:entindex()})
    check(step(f.service.snapshot(0))=="main_city","a registered completed building is accepted despite stale native owner cache")
    f.builders[0].survival_player_id=nil
    f.service.refresh(0)
    check(not active(f.service.snapshot(0)),"missing builder ownership cannot retain an active click lock")
end)

test("skip releases input immediately and retries without resurrection",function()
    local f=fixture();f.start(0)
    f.service.skip(0)
    check(not active(f.service.snapshot(0)),"skip must release input before HTTP finishes")
    check(#f.finishes==1 and f.finishes[1].outcome=="skipped")
    f.finish_reply(1,false)
    f.service.refresh(0)
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
    f.build(0,"wall")
    check(not active(f.service.snapshot(0)),"refresh and delayed packets cannot reactivate a skipped guide")
    f.advance(60)
    check(#f.finishes>=2,"a failed skip save must retry without locking the player")
    f.finish_reply(#f.finishes,true)
    f.service.refresh(0)
    check(not active(f.service.snapshot(0)))
end)

test("UI sender identity prevents cross-player skip and has no completion event",function()
    local f=fixture();f.start(0);f.start(1)
    local skip_listener
    for name,callback in pairs(f.listeners) do
        if name:match("onboarding") and name:match("skip") then skip_listener=callback end
        check(not (name:match("onboarding") and name:match("complete")),"client completion events must not exist")
    end
    check(type(skip_listener)=="function","the always available skip button needs a server listener")
    skip_listener(100,{PlayerID=1,player_id=1})
    check(active(f.service.snapshot(1)),"spoofed PlayerID must not skip another player's guide")
    for _,entry in ipairs(f.finishes) do check(entry.pid~=1,"spoofed UI request must never persist for another account") end
    skip_listener(999,{PlayerID=1,player_id=1})
    check(active(f.service.snapshot(1)),"a missing sender entity must not fall back to the payload PlayerID")
    skip_listener(101,{PlayerID=1,player_id=1})
    check(not active(f.service.snapshot(1)),"the authenticated actor can skip its own guide")
end)

test("disconnect or builder death clears locking and blocks stale callbacks",function()
    local f=fixture();f.start(0)
    f.connected[0]=false
    bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
    f.service.refresh(0)
    check(not active(f.service.snapshot(0)),"disconnected player must not retain an active click mask")
    f.connected[0]=true;f.service.refresh(0)
    check(active(f.service.snapshot(0)),"same-match reconnect resumes the current step")
    f.builders[0].alive=false;f.service.refresh(0)
    check(not active(f.service.snapshot(0)),"dead builders cannot keep an interactive lock")
end)

test("callbacks from before reinitialization cannot reactivate a guide",function()
    local f=fixture();f.service.refresh(0)
    local old={}
    for _,entry in ipairs(f.reads) do if entry.pid==0 then old[#old+1]=entry.callback end end
    check(#old>0,"fixture must retain an asynchronous initial account read")
    f.service.init()
    for _,callback in ipairs(old) do callback({ok=true,loaded=true,required=true,status="required",version=1}) end
    check(not active(f.service.snapshot(0)),"pre-reload callbacks cannot write into a new guide generation")
    f.reads={}
    f.service.refresh(0)
    check(#f.reads>0,"reinitialization must clear the obsolete in-flight read so it can be retried")
    f.metadata_reply(0,"required")
    check(active(f.service.snapshot(0)),"a fresh-generation account receipt must restore the guide")
    f.service.skip(0)
    local old_finish=f.finishes[1].callback
    f.service.init()
    old_finish({ok=true,loaded=true,required=false,status="skipped",version=1})
    f.advance(60)
    check(not active(f.service.snapshot(0)),"a skipped guide remains released across hot reload")
    check(#f.finishes>=2,"hot reload must restart a terminal save whose old callback was invalidated")
end)

test("visible state changes advance the snapshot revision",function()
    local f=fixture();f.start(0)
    local initial=f.service.snapshot(0)
    check(type(initial.generation)=="number" and type(initial.revision)=="number","the UI needs ordered private snapshots")
    f.build(0,"wall")
    local next_step=f.service.snapshot(0)
    check(next_step.generation==initial.generation and next_step.revision>initial.revision,"new steps must not be dropped as duplicate UI packets")
    f.service.skip(0)
    local skipped=f.service.snapshot(0)
    check(skipped.revision>next_step.revision,"the release-mask snapshot must have a new revision")
end)

assert(#failures==0,table.concat(failures,"\n"))
print("test_onboarding_service: PASS ("..passed.." behaviour groups)")
