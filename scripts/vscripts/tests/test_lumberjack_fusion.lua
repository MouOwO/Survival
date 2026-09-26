package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local definitions = require("config/generated/lumberjack_fusion_definitions")
local committed, commit_ok
package.loaded["systems/worker_system"] = {commit_lumberjack_fusion = function(materials, target, data)
    committed = {materials = materials, target = target, data = data}
    if not commit_ok then return {ok = false, error = "fusion_commit_failed"} end
    target.survival_super_lumberjack = true
    target.survival_lumberjack_fusion_pending = nil
    return {ok = true}
end}
RandomInt = function() return 1 end
local service = require("systems/lumberjack_fusion_service")
local workers, caster, ability, city_level, resources, charges, refunds, notifications
local function unit(index, level, player_id)
    local u = {survival_player_id = player_id or 0, survival_worker_type = "lumberjack",
        survival_lumberjack_level = level, survival_attack_min = 100, survival_base_wood_per_hit = level}
    function u:IsNull() return false end
    function u:IsAlive() return self.dead ~= true end
    function u:entindex() return index end
    function u:GetTeamNumber() return 2 end
    function u:FindAbilityByName() return self.ability end
    return u
end
local function reset(level)
    bus.reset(); service.init()
    workers, charges, refunds, notifications = {}, {}, {}, {}
    resources = {wood = 1000000, gold = 1000000}
    city_level, commit_ok, committed = 5, true, nil
    local row = definitions.by_id[string.format("lumberjack_fusion_%02d",level)]
    for i = 1,row.required_count do
        local u = unit(i,level)
        workers[#workers+1] = {unit=u, team=2, player_id=0, worker_type="lumberjack"}
    end
    caster = workers[1].unit
    ability = {GetAbilityName = function() return row.ability_id end, GetCaster = function() return caster end}
    caster.ability = ability
    bus.handle_request(events.WORKER_LIST_REQUEST,function() return workers end)
    bus.handle_request(events.BUILDING_LIST_REQUEST,function() return {buildings={{building_id="main_city",level=city_level}}} end)
    bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST,function(p)
        if resources.wood < p.wood then return {ok=false,error="wood_not_enough"} end
        if resources.gold < p.gold then return {ok=false,error="gold_not_enough"} end
        resources.wood=resources.wood-p.wood;resources.gold=resources.gold-p.gold
        charges[#charges+1]=p;return {ok=true}
    end)
    bus.handle_request(events.RESOURCE_ADD_REQUEST,function(p)
        refunds[#refunds+1]=p
        resources.wood=resources.wood+p.wood;resources.gold=resources.gold+p.gold
        return {ok=true}
    end)
    bus.subscribe(events.UI_NOTIFICATION,function(p) notifications[#notifications+1]=p end)
    return row
end
local function fuse(player_id)
    local result, err = bus.request(events.LUMBERJACK_FUSION_REQUEST,{caster=caster,ability=ability,player_id=player_id or 0})
    assert(not err,err)
    return result
end
for level=1,8 do
    local row=reset(level)
    assert(fuse().ok,"configured level must fuse: "..level)
    assert(#charges==1 and charges[1].wood==row.wood_cost and charges[1].gold==row.gold_cost)
    assert(#committed.materials==row.required_count and committed.data.level==level)
    assert(committed.data.base_attack==100*row.required_count)
    assert(committed.data.wood_per_hit==level*row.required_count)
    assert(#committed.data.ability_names==(level==8 and 0 or 1))
    assert(not fuse().ok and #charges==1,"fused caster must not grant or spend twice")
end
reset(2);city_level=4;assert(fuse().ok)
reset(3);city_level=4;assert(fuse().error=="fusion_city_level_not_enough")
assert(#charges==0 and notifications[1].message:find("LV5",1,true))
reset(3);resources.gold=4999;assert(fuse().error=="gold_not_enough")
assert(#charges==0 and notifications[1].message:find("5000",1,true))
resources.gold=5000;assert(fuse().ok,"failed attempt must clear pending flags for retry")
reset(8);resources.wood=79999;assert(fuse().error=="wood_not_enough")
reset(3);workers[3].player_id=1;workers[3].unit.survival_player_id=1
assert(fuse().error=="fusion_material_not_enough" and #charges==0)
reset(3);workers[3].unit.survival_super_lumberjack=true
assert(fuse().error=="fusion_material_not_enough")
reset(3);assert(fuse(1).error=="fusion_not_owned" and #charges==0)
reset(3);caster.ability={};assert(fuse().error=="fusion_ability_not_owned")
reset(3);commit_ok=false;assert(fuse().error=="fusion_commit_failed")
assert(#charges==1 and #refunds==1 and resources.wood==1000000 and resources.gold==1000000)
for _,state in ipairs(workers) do assert(not state.unit.survival_lumberjack_fusion_pending) end
commit_ok=true;assert(fuse().ok)
print("PASS lumberjack fusion: 8 configured tiers, gates, retry/refund, ownership and duplicate prevention")
