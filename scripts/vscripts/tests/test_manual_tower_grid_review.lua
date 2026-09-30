package.path="scripts/vscripts/?.lua;"..package.path
local clock,tools,ready,wood,requests,checks=0,true,true,10,0,0
local completed,pending={},{}
GameRules={GetGameTime=function() return clock end}
IsInToolsMode=function() return tools end
Vector=function(x,y,z) return {x=x,y=y,z=z} end
local builder={IsNull=function() return false end,IsAlive=function() return true end,
    GetTeamNumber=function() return 2 end,GetAbsOrigin=function() return Vector(320,5460,384) end}
Entities={FindAllByClassname=function(_,class_name)
    local result={}
    for _,unit in pairs(pending) do if unit.class_name==class_name then result[#result+1]=unit end end
    return result
end}
local bus,events=require("core/event_bus"),require("core/events")
local scheduler=require("core/scheduler");bus.reset();scheduler.clear()
package.loaded["systems/startup_loading_service"]={is_player_ready=function() return ready end}
local definitions=require("config/buildings_config")
local training=require("config/generated/training_definitions").by_id.train_lumberjack_01
wood=require("config/generated/player_gameplay_stats").by_id.initial_wood.default_value
assert(wood==10 and definitions.arrow_tower.build_cost.wood==50 and training.wood_cost==10,
    "Use actual CSV-generated prices: opening 10, LV1 worker 10, arrow tower 50")
assert(definitions.wall.build_cost.wood==0 and definitions.main_city.build_cost.wood==0)
local workers,trained,spent,harvested,queue_count={},0,0,0,0
bus.handle_request(events.RESOURCE_GET_REQUEST,function() return {wood=wood} end)
bus.handle_request(events.WORKER_LIST_REQUEST,function() return workers end)
bus.handle_request(events.WORKER_TRAINING_GET_REQUEST,function() return {queue_count=queue_count} end)
bus.handle_request(events.WORKER_TRAIN_REQUEST,function(p)
    assert(p.training_id=="train_lumberjack_auto" and p.player_id==0 and p.city)
    assert(p.prepaid==nil and p.wood_cost_override==nil and p.allow_extra_slot==nil)
    if wood<training.wood_cost then return {ok=false,error="wood_not_enough"} end
    trained=trained+1;spent=spent+training.wood_cost;wood=wood-training.wood_cost;queue_count=1
    scheduler.after(training.training_duration_seconds,function()
        workers={{player_id=0,worker_type="lumberjack",unit={
            entindex=function() return 60 end,IsNull=function() return false end,IsAlive=function() return true end}}}
        queue_count=0
        scheduler.every(1/training.attack_rate,function()
            if #workers==0 then return false end
            wood=wood+training.wood_per_hit;harvested=harvested+training.wood_per_hit
            return true
        end,"fixture_native_harvest")
    end)
    return {ok=true,queued=true}
end)
bus.handle_request(events.BUILDER_GET_REQUEST,function(p) assert(p.player_id==0);return {ok=true,builder=builder} end)
bus.handle_request(events.BUILDING_LIST_REQUEST,function() return {buildings=completed} end)
bus.handle_request(events.RESOURCE_CAN_SPEND_REQUEST,function(p)
    return {ok=wood>=p.wood,error="wood_not_enough"}
end)
bus.handle_request(events.BUILD_CAN_PLACE_REQUEST,function(p)
    checks=checks+1
    assert(p.caster==builder and p.player_id==0)
    local margin=p.building_id=="wall" and 128 or 64
    local q=p.position
    assert(q.x+margin < -512 or q.x-margin > 1152 or q.y+margin <5000 or q.y-margin >6000,
        "never overlap the presentation fixture")
    return {ok=true,grid={world_position=p.position}}
end)
bus.handle_request(events.BUILD_REQUEST,function(p)
    requests=requests+1
    assert(p.caster==builder and p.player_id==0 and p.source_ability==nil)
    local price=definitions[p.building_id].build_cost.wood
    assert(wood>=price);wood=wood-price;spent=spent+price
    builder.survival_build_task={building_id=p.building_id}
    local index=requests+20
    scheduler.after(3,function()
        local unit={IsNull=function() return false end,IsAlive=function() return true end,
            entindex=function() return index end,GetAbsOrigin=function() return p.position end,
            survival_player_id=0,survival_building_id=p.building_id,
            class_name=p.building_id=="wall" and "npc_dota_building" or "npc_dota_creature",
            HasModifier=function() return pending[index]~=nil end,
            FindAbilityByName=function()return {entindex=function() return 100+index end}end}
        pending[index]=unit
        builder.survival_build_task=nil
        scheduler.after(definitions[p.building_id].build_time,function()
            completed[#completed+1]={player_id=0,building_id=p.building_id,unit=unit,entindex=index}
            pending[index]=nil
        end)
    end)
    return {ok=true,pending=true}
end)
local helper=require("tests/manual_tower_grid_review")
assert(requests==0 and checks==0 and scheduler.task_count()==0,"require is inert")
tools=false;assert(not pcall(helper.run,0));tools=true
ready=false;assert(not pcall(helper.run,0));ready=true
assert(requests==0,"cannot bypass Tools mode or normal admission")
helper.run(0)
local function advance(seconds)
    local finish=clock+seconds
    while clock<finish do clock=clock+0.1;scheduler.think() end
end
advance(110)
assert(helper.status().status=="ready" and requests==3 and trained==1 and spent==60)
assert(wood==10-spent+harvested,"No helper grants; all extra wood came from mocked native harvest events")
assert(helper.status().completed.wall and helper.status().completed.main_city and helper.status().completed.arrow_tower)
helper.run(0)
advance(1)
assert(helper.status().status=="ready" and requests==3,"reuse completed buildings without spending twice")
completed[3]=nil;wood=0;helper.run(0);advance(95)
assert(helper.status().status=="ready" and requests==4 and trained==1,"reuse real worker without another training debit")
completed[3]=nil;wood=0;workers={};helper.run(0);advance(1)
assert(helper.status().status=="stopped" and helper.status().reason=="lumberjack_train:wood_not_enough" and requests==4)
completed={};builder.survival_build_task={building_id="wall"};helper.run(0)
advance(241)
assert(helper.status().status=="stopped" and helper.status().reason:find("timeout_240s",1,true))
assert(requests==4 and builder.survival_build_task,"timeout never cancels existing real orders")
print("MANUAL_TOWER_GRID_REVIEW_PASS actual CSV 10/10/50, native queue/harvest, wall construction handoff, worker/building reuse, 240s timeout")
