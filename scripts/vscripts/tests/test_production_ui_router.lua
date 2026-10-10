package.path = "scripts/vscripts/?.lua;" .. package.path
local listeners, sent, pushes = {}, {}, {}
local admitted, defeated = { [0] = true, [1] = true }, {}
local handles = { [0] = {}, [1] = {} }
PlayerResource = {
    IsValidPlayerID = function(_, id) return handles[id] ~= nil end,
    GetPlayer = function(_, id) return handles[id] end,
    GetTeam = function(_, id) return 2 end,
}
GameRules = { GetGameTime = function() return 100 end }
CustomGameEventManager = {
    RegisterListener = function(_, name, handler) listeners[name] = handler end,
    Send_ServerToPlayer = function(_, player, name, payload)
        sent[#sent+1] = { player=player, name=name, payload=payload }
    end,
}
package.loaded["systems/startup_loading_service"] = {
    is_player_ready = function(id) return admitted[id] == true end,
}
package.loaded["systems/multiplayer_player_service"] = {
    is_defeated = function(id) return defeated[id] == true end,
}
for _, name in ipairs({ "systems/building_system", "ui/weapon_synthesis_snapshot_service",
    "ui/combat_stat_projection", "config/asset_catalog", "systems/hero_summon_projection",
    "systems/building_batch_upgrade_service", "systems/gold_mine_batch_upgrade_service" }) do
    package.loaded[name] = {}
end
package.loaded["systems/hero_summon_projection"] = {hero_id_for_summon_ability = function() return nil end}
local function entity(index,owner)
    return { survival_player_id=owner, entindex=function() return index end,
        IsNull=function() return false end, IsAlive=function(self) return not self.dead end }
end
local city0, city1, lab = entity(200,0), entity(201,1), entity(202,0)
local entities = { [200]=city0, [201]=city1, [202]=lab }
EntIndexToHScript = function(index) return entities[index] end
local states = {
    [200]={unit=city0,entindex=200,player_id=0,team=2,building_id="main_city"},
    [201]={unit=city1,entindex=201,player_id=1,team=2,building_id="main_city"},
    [202]={unit=lab,entindex=202,player_id=0,team=2,building_id="building_research_lab"},
}
local bus = require("core/event_bus")
local events = require("core/events")
bus.reset()
bus.handle_request(events.BUILDING_QUERY_REQUEST,function(payload) return states[payload.entindex] end)
local requests = {}
local forced_worker_error, forced_research_error
bus.handle_request(events.WORKER_TRAIN_REQUEST,function(payload)
    requests[#requests+1]=payload
    if forced_worker_error then return {ok=false,error=forced_worker_error} end
    return {ok=true,queued=true,job_id="job-1"}
end)
bus.handle_request(events.WORKER_TRAINING_GET_REQUEST,function(payload)
    assert(payload.player_id==0 and payload.source_entindex==200 and payload.team==2)
    return {active_job={finish_at=101},options={{training_id="train_lumberjack_01"}}}
end)
bus.handle_request(events.TECHNOLOGY_STATE_GET_REQUEST,function(payload)
    assert(payload.source_entindex==202 or payload.source_entindex==203)
    return {research={researching=1,research_until=102,auto_research={}}}
end)
local research_events = require("research/research_event_names")
local advanced_mapping
for _, mapping in ipairs(require("config/generated/research_lab_abilities").rows) do
    if mapping.building_id == "building_advanced_research_lab" then advanced_mapping=mapping; break end
end
assert(advanced_mapping)
bus.handle_request(research_events.STATE_GET_REQUESTED,function(payload)
    return {ok=true,legacy_levels={[advanced_mapping.technology_group]=payload.player_id==0 and 7 or 2}}
end)
require("ui/ui_request_router").init()
local send = assert(listeners.ui_worker_train_request)
local function train(player,source,extra)
    local p={PlayerID=player,player_id=1,source_entindex=source,
        training_id="train_lumberjack_02",count=99,free=true,source="rogue_reward",request_id="test"}
    for k,v in pairs(extra or {}) do p[k]=v end
    send(nil,p)
end
train(0,200)
assert(#requests==1 and requests[1].player_id==0 and requests[1].city==city0)
assert(requests[1].training_id=="train_lumberjack_02")
assert(requests[1].source=="main_city_training_ui" and requests[1].count==nil and requests[1].free==nil)
assert(sent[1].player==handles[0] and sent[1].payload.success==1)
-- Same team does not authorize another player's city; client owner fields cannot spoof PlayerID.
train(0,201)
train(1,200)
train(0,202)
train(0,-1)
train(0,200.5)
train(0,999)
city0.dead=true; train(0,200); city0.dead=nil
assert(#requests==1)
local packet_count=#sent
admitted[0]=false; train(0,200); admitted[0]=true
assert(#requests==1 and #sent==packet_count)
defeated[0]=true; train(0,200); defeated[0]=nil
assert(#requests==1 and #sent==packet_count)
send(nil,{player_id=0,source_entindex=200,training_id="train_lumberjack_01"})
assert(#requests==1 and #sent==packet_count)
-- State is private to the requesting owner and is tied to the selected source.
local service=require("ui/production_ui_service")
local snap=service.decorate(0,city0,{entindex=200})
assert(snap.training.active_job.finish_at==101 and snap.building_id=="main_city" and snap.server_time==100)
local foreign=service.decorate(1,city0,{entindex=200})
assert(foreign.training==nil and foreign.research==nil)
local rs=service.decorate(0,lab,{entindex=202})
assert(rs.research.research_until==102)
local shared=entity(203,0)
states[203]={unit=shared,entindex=203,player_id=0,team=2,building_id="building_advanced_research_lab"}
local viewer=service.decorate(1,shared,{entindex=203})
local owner=service.decorate(0,shared,{entindex=203})
local name=advanced_mapping.ability_name
assert(viewer.research.abilities_by_name[name].current_level==2)
assert(owner.research.abilities_by_name[name].current_level==7)
assert(viewer.research.abilities_by_name[name].next_level==3)
states[203].team=3
assert(service.decorate(1,shared,{entindex=203}).research==nil,"enemy research state is not published")
states[203].team=2
-- Research queue uses the same trusted sender and strips fabricated cost/level/source.
entities[203]=shared
local research_requests={}
bus.handle_request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST,function(payload)
    research_requests[#research_requests+1]=payload
    if forced_research_error then return {ok=false,error=forced_research_error} end
    return {ok=true,queued=true}
end)
local queue=assert(listeners.ui_research_queue_request)
local function research(player, source, extra)
    local p={PlayerID=player,player_id=0,source_entindex=source,
        technology_group=advanced_mapping.technology_group,request_id="queue-test",
        free=true,target_level=99,count=99,cost_gold=0,source="rogue_reward"}
    for key,value in pairs(extra or {}) do p[key]=value end
    queue(nil,p)
end
research(0,202)
research(1,203)
assert(#research_requests==2)
assert(research_requests[2].player_id==1 and research_requests[2].source_entindex==203)
assert(research_requests[2].source=="research_queue_ui" and research_requests[2].free==nil)
assert(research_requests[2].target_level==nil and research_requests[2].cost_gold==nil)
assert(research_requests[2].count==nil and research_requests[2].request_id=="queue-test")
assert(sent[#sent].payload.operation=="research_queue" and sent[#sent].payload.queued==1)
research(1,202) -- normal lab is private, advanced lab may be shared
research(0,200) -- city is not a research building
research(0,202.5)
research(0,999)
lab.dead=true; research(0,202); lab.dead=nil
states[203].team=3; research(1,203); states[203].team=2
assert(#research_requests==2)
local before_research_packets=#sent
admitted[0]=false; research(0,202); admitted[0]=true
defeated[0]=true; research(0,202); defeated[0]=nil
queue(nil,{player_id=0,source_entindex=202,technology_group="fake"})
assert(#research_requests==2 and #sent==before_research_packets)
local cancel_requests = {}
bus.handle_request(events.TECHNOLOGY_RESEARCH_CANCEL_REQUEST, function(payload)
    cancel_requests[#cancel_requests + 1] = payload
    return {ok = true, refunded = true}
end)
local cancel_listener = assert(listeners.ui_research_cancel_request)
cancel_listener(nil, {PlayerID = 1, player_id = 0, source_entindex = 203,
    job_id = "1:203:7", request_id = "cancel-test", refund_gold = 99999, target_level = 99})
assert(#cancel_requests == 1 and cancel_requests[1].player_id == 1)
assert(cancel_requests[1].job_id == "1:203:7" and cancel_requests[1].source_entindex == 203)
assert(cancel_requests[1].refund_gold == nil and cancel_requests[1].target_level == nil)
assert(sent[#sent].payload.operation == "research_cancel" and sent[#sent].payload.refunded == 1)
cancel_listener(nil, {PlayerID = 1, source_entindex = 202, job_id = "0:202:1"})
cancel_listener(nil, {PlayerID = 0, source_entindex = 200, job_id = "x"})
cancel_listener(nil, {PlayerID = 0, source_entindex = 202.5, job_id = "x"})
lab.dead = true;cancel_listener(nil, {PlayerID = 0, source_entindex = 202, job_id = "x"});lab.dead = nil
assert(#cancel_requests == 1, "cancel route retains source ownership/alive/integer validation")
-- Refresh only the affected player's currently selected building. The timing
-- fields are stable server timestamps, so the UI animates without polling.
bus.reset()
bus.handle_request(events.BUILDING_QUERY_REQUEST,function(payload) return states[payload.entindex] end)
local selected = {[0]=200,[1]=201}
service.init({source_player_id=function(p) return p.PlayerID end,
    valid_player_id=function() return true end,send=function() end,
    selected=function(id) return selected[id] end,
    push=function(payload) pushes[#pushes+1]=payload end})
bus.emit(events.WORKER_CHANGED,{player_id=0,source_entindex=200})
bus.emit(events.WORKER_CHANGED,{player_id=1,source_entindex=201})
bus.emit(events.WORKER_CHANGED,{player_id=0,source_entindex=999})
bus.emit(events.RESOURCE_CHANGED,{player_id=0})
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED,{player_id=0,source_entindex=202})
assert(#pushes==2 and pushes[1].entindex==200 and pushes[2].entindex==201,
    "wallet changes cannot rebuild training availability")
selected[0]=999 -- ordinary hero/tree selections must never receive building-stat projections
bus.emit(events.RESOURCE_CHANGED,{player_id=0})
assert(#pushes==2)
print("PRODUCTION_UI_ROUTER_PASS: trusted sender, ownership, startup/defeat, one paid unit per click, private source snapshots and targeted refresh")
local before_fusion = #sent
bus.emit(events.WORKER_CHANGED, { player_id = 1, super_lumberjack = true,
    entindex = 300, removed_entindexes = {301, 302} })
assert(#sent == before_fusion + 1)
local notice = sent[#sent]
assert(notice.player == handles[1] and notice.name == "survival_lumberjack_fused")
assert(notice.payload.target_entindex == 300)
assert(table.concat(notice.payload.consumed_entindexes, ",") == "300,301,302")
print("FUSION_PRIVATE_SELECTION_EVENT_PASS")
-- A resource burst must not rebuild the selected research description tree.
local runtime_builder=require("ui/ability_runtime_builder")
local original_build=runtime_builder.build
local builds=0
runtime_builder.build=function(...) builds=builds+1;return original_build(...) end
selected[0]=202
service.decorate(0,lab,{entindex=202})
local initial=builds
assert(initial>0)
local before_push=#pushes
for index=1,1000 do
    bus.emit(events.RESOURCE_CHANGED,{player_id=0,wood=index})
    service.decorate(0,lab,{entindex=202})
end
assert(builds==initial and #pushes==before_push,
    "resource packets cannot invalidate personal research descriptions or trigger selected-lab refresh")
bus.emit(research_events.LEVEL_CHANGED,{player_id=0})
service.decorate(0,lab,{entindex=202})
assert(builds>initial and #pushes==before_push+1,"completion invalidates exactly the affected player's research cache")
runtime_builder.build=original_build
print("RESEARCH_DESCRIPTION_CACHE_PASS: 1000 resource changes/decorations reuse rows; completion refreshes")

local resource_notices = {}
bus.handle_request(events.WORKER_TRAIN_REQUEST, function() return {ok=false,error=forced_worker_error} end)
bus.handle_request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, function() return {ok=false,error=forced_research_error} end)
bus.subscribe(events.UI_NOTIFICATION, function(payload) resource_notices[#resource_notices + 1] = payload end)
for _, case in ipairs({{"wood_not_enough", "木材不足"}, {"gold_not_enough", "金币不足"},
    {"population_not_enough", "人口不足"}}) do
    forced_worker_error=case[1]
    train(0,200)
    local response=sent[#sent]
    assert(response.name=="ui_operation_result" and response.payload.success==0)
    assert(response.payload.error==case[2] and resource_notices[#resource_notices].message==case[2],
        "rejected training must expose a specific Chinese resource error: "
            .. tostring(response.payload.error) .. "/" .. tostring(resource_notices[#resource_notices].message))
end
for _, case in ipairs({{"insufficient_wood", "木材不足"}, {"insufficient_gold", "金币不足"}}) do
    forced_research_error=case[1]
    queue(nil,{PlayerID=0,source_entindex=202,
        technology_group="lumberjack_speed",request_id="resource_reject"})
    local response=sent[#sent]
    assert(response.name=="ui_operation_result" and response.payload.success==0)
    assert(response.payload.error==case[2] and resource_notices[#resource_notices].message==case[2])
end
print("PRODUCTION_RESOURCE_ERROR_PASS: failed admissions return localized wood/gold/population feedback and notifications")
