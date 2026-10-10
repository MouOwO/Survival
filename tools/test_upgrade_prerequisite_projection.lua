package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local builder = require("ui/ability_runtime_builder")
local research = require("config/research_technology_config")
local routes = require("config/tower_route_config")
PlayerResource = {GetTeam = function() return 2 end}
bus.reset()
local rebirth = 10
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function()
    return {snapshot = {rebirth_level = rebirth}}
end)
local quote = {ok = true, prerequisite_met = 1}
bus.handle_request(events.BUILDING_UPGRADE_QUOTE_REQUEST, function() return quote end)
local unit = {entindex = function() return 900 end}
local function state(extra)
    local result = {player_id=0,team=2,unit=unit,level=1,city_level=30,
        building_counts={},tower_class_counts={},research_levels={},research_transaction={},
        reincarnation_level=10,hero_summoned=1,mine_level=1,efficiency_level=0,crit_level=0}
    for key,value in pairs(extra or {}) do result[key]=value end
    return result
end
local poor={wood=0,gold=0,population=999,max_population=0}
local rich={wood=1e15,gold=1e15,population=0,max_population=1e6}
local cases={
    {"ability_tower_class_1",state({level=5})},
    {"ability_upgrade_tower",state({level=1})},
    {"ability_upgrade_tower",state({level=6,tower_class="class_1"})},
    {"ability_upgrade_city",state({building_id="main_city"})},
    {"ability_upgrade_wall",state({building_id="wall"})},
    {"ability_upgrade_wall_9_1",state({building_id="wall"})},
    {"ability_upgrade_farm",state({building_id="building_farm"})},
    {"ability_upgrade_gold_mine",state({building_id="gold_mine"})},
    {"ability_upgrade_gold_mine_efficiency",state({building_id="gold_mine"})},
    {"ability_upgrade_gold_mine_crit",state({building_id="gold_mine"})},
    {"ability_build_wall",state({building_id="builder"})},
    {"ability_build_arrow_tower",state({building_id="builder"})},
    {"ability_train_lumberjack",state({building_id="main_city",level=30})},
    {"ability_research_lumberjack_speed",state({building_id="building_research_lab"})},
    {"ability_enter_shadow_realm",state({building_id="hero_altar"})},
}
for _,case in ipairs(cases) do
    local empty=builder.build(case[1],case[2],poor)
    local funded=builder.build(case[1],case[2],rich)
    assert(empty.available==1 and funded.available==1,case[1].." should remain clickable")
    assert(empty.prerequisite_met==1 and funded.prerequisite_met==1,case[1].." incorrectly locked")
    assert(empty.can_afford==1 and empty.resource_check_on_cast==1,case[1].." must check resources on click")
    assert(empty.status_text==funded.status_text,case[1].." changes descriptions with the wallet")
    assert(empty.cost_wood==funded.cost_wood and empty.cost_gold==funded.cost_gold)
end
for class=1,7 do
    local s=state({level=5})
    local r=builder.build("ability_tower_class_"..class,s,poor)
    local expected=routes.class_change_cost(routes.get("class_"..class,1),s)
    assert(r.available==1 and r.prerequisite_met==1 and r.can_afford==1)
    assert(r.cost_wood==expected.wood and r.cost_gold==expected.gold and r.population==(expected.population or 0))
end
local full=builder.build("ability_tower_class_1",state({level=5,
    tower_class_counts={class_1={count=5,maximum=5}}}),rich)
assert(full.available==0 and full.prerequisite_met==1,"class capacity is not a learning prerequisite")
quote={ok=false,prerequisite_met=0,error="主城等级不足"}
for _,name in ipairs({"ability_upgrade_farm","ability_upgrade_wall","ability_upgrade_wall_9_1"}) do
    local r=builder.build(name,state(),rich)
    assert(r.available==0 and r.prerequisite_met==0,name.." must retain the true city prerequisite")
end
quote={ok=false,error="建筑正在升级中"}
local busy=builder.build("ability_upgrade_farm",state({upgrade_in_progress=1}),poor)
assert(busy.available==0 and busy.prerequisite_met==1,"temporary upgrade state is not a prerequisite")
quote={ok=true,prerequisite_met=1}
assert(builder.build("ability_upgrade_farm",state(),poor).prerequisite_met==1)
local locked=builder.build("ability_tower_class_1",state({level=4}),rich)
assert(locked.available==0 and locked.prerequisite_met==0)
rebirth=0
local travel=builder.build("ability_enter_shadow_realm",state(),rich)
assert(travel.available==0 and travel.prerequisite_met==0,"hero rebirth is a real prerequisite")
local max=research.by_legacy_group.lumberjack_speed.max_level
local pending=builder.build("ability_research_lumberjack_speed",state({building_id="building_research_lab",
    research_transaction={queue_count=7,capacity=7,reserved_levels={lumberjack_speed=max}}}),poor)
assert(pending.prerequisite_met==1 and pending.available==0 and pending.completed==0)
print("UPGRADE_PREREQUISITE_PROJECTION_PASS: 15 entrances, all seven careers, true city/rebirth gates, busy/queue/capacity, wallet-independent descriptions and prices")
