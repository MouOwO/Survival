package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["core/test_access_policy"]={enabled=function() return false end}
package.loaded["systems/player_context_service"]={is_owned_by=function(id) return id==0 end}
local bus,events=require("core/event_bus"),require("core/events")
local city={IsNull=function()return false end,IsAlive=function()return true end,
    entindex=function()return 10 end}
EntIndexToHScript=function(id) if id==10 then return city end end
GameRules={GetGameTime=function()return 0 end}
local listeners,requests={},{}
CustomGameEventManager={RegisterListener=function(_,name,fn)listeners[name]=fn end}
bus.handle_request(events.BUILDING_QUERY_REQUEST,function(payload)
    if payload.entindex==10 then return{building_id="main_city",player_id=0,team=2}end
end)
bus.handle_request(events.WORKER_TRAINING_GET_REQUEST,function()return{}end)
bus.handle_request(events.WORKER_TRAIN_REQUEST,function(payload)
    requests[#requests+1]=payload;return{ok=true,queued=true,job_id=#requests}
end)
local service=require("ui/production_ui_service")
service.init({source_player_id=function(p)return p.PlayerID end,
    valid_player_id=function(id)return id==0 end,selected=function()return nil end,
    push=function()end,send=function()end,compact_refresh=function()return true end})
local forged={adapter_generation=1,owner_serial=1,request_token=1,production_selection=1,action_code=8}
listeners.ui_worker_train_request(nil,{PlayerID=0,source_entindex=10,
    training_id="train_lumberjack_01",_training_trace=forged,count=999,free=true})
assert(#requests==1 and requests[1]._training_trace==nil)
assert(requests[1].count==nil and requests[1].free==nil,"legacy payload cannot escalate a real job or forge provenance")
local trusted={adapter_generation=2,owner_serial=3,request_token=4,production_selection=5,action_code=8}
assert(service.execute("production_train",{PlayerID=0,source_entindex=10,
    training_id="train_lumberjack_01",_training_trace=trusted}).success==1)
assert(#requests==2 and requests[2]._training_trace==trusted,
    "only internal compact capture preserves its server-created origin object")
print("production training trace provenance passed: client forgery discarded; internal origin preserved")
