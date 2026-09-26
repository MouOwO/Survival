package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local names = require("research/research_event_names")
local sync = require("systems/research_lab_ability_sync")
local builder = require("ui/ability_runtime_builder")
local config = require("config/research_technology_config")
PlayerResource = { GetTeam = function() return 2 end }
local function unit(id)
    local abilities = {}
    local u = { abilities = abilities }
    function u:IsNull() return false end
    function u:entindex() return id end
    function u:FindAbilityByName(name) return abilities[name] end
    function u:RemoveAbility(name) abilities[name] = nil end
    function u:AddAbility(name)
        local a = { active = true }
        function a:SetLevel(value) self.level = value end
        function a:SetHidden(value) self.hidden = value end
        function a:SetActivated(value) self.active = value end
        function a:SetAbilityIndex(value) self.index = value end
        abilities[name] = a
        return a
    end
    return u
end
local buildings = {
    { entindex = 10, player_id = 0, team = 2, building_id = "building_research_lab", unit = unit(10) },
    { entindex = 11, player_id = 1, team = 2, building_id = "building_research_lab", unit = unit(11) },
    { entindex = 12, player_id = 0, team = 2, building_id = "building_advanced_research_lab", unit = unit(12) },
}
local transactions, levels = {}, { [0] = {}, [1] = {} }
bus.reset()
bus.handle_request(events.BUILDING_LIST_REQUEST, function() return { buildings = buildings } end)
bus.handle_request(names.STATE_GET_REQUESTED, function(p)
    return { ok = true, legacy_levels = levels[p.player_id] }
end)
bus.handle_request(events.TECHNOLOGY_STATE_GET_REQUEST, function(p)
    return { ok = true, research = transactions[p.source_entindex] or { researching = 0 } }
end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function()
    return { snapshot = { rebirth_level = 10 } }
end)
sync.init()
for _, b in ipairs(buildings) do bus.emit(events.BUILDING_CREATED, b) end
local name = "ability_research_lumberjack_speed"
assert(buildings[1].unit.abilities[name].active)
assert(buildings[2].unit.abilities[name].active)
transactions[10] = { player_id = 0, source_entindex = 10, researching = 1,
    research_group = "lumberjack_speed", display_name = "伐木工速度", target_level = 1,
    started_at = 5, finish_at = 7, duration = 2, next_start_at = 0,
    auto_research = { lumberjack_speed = 1 }, queue_count = 1, capacity = 7,
    reserved_levels = { lumberjack_speed = 1 } }
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, transactions[10])
assert(buildings[1].unit.abilities[name].active, "busy research still accepts queue clicks")
assert(buildings[2].unit.abilities[name].active, "another player's lab stays active")
assert(buildings[3].unit.abilities.ability_research_ars_01.active,
    "advanced lab stays independent from busy normal lab")
levels[0].researcher_lumberjack_attack_growth = 1
bus.emit(names.LEVEL_CHANGED, { player_id = 0 })
assert(buildings[1].unit.abilities[name].active,
    "another completion does not disturb this building's queue availability")
local runtime = builder.build(name, {
    player_id = 0, building_id = "building_research_lab", unit = buildings[1].unit,
    research_levels = levels[0], research_transaction = transactions[10],
    reincarnation_level = 10,
}, { gold = 1000000, wood = 1000000 })
assert(runtime.available == 1 and runtime.research_status_code == "queue_available")
assert(runtime.next_level == 2, "same research next click reserves following level")
assert(runtime.auto_research_available == 1 and runtime.auto_research_enabled == 1,
    "right-click cancel remains exposed while research is running")
assert(runtime.research_started_at == 5 and runtime.research_until == 7 and runtime.research_total == 2)
local waiting = builder.build("ability_research_lumberjack_efficiency", {
    player_id = 0, building_id = "building_research_lab", unit = buildings[1].unit,
    research_levels = levels[0], research_transaction = transactions[10],
    reincarnation_level = 10,
}, { gold = 1000000, wood = 1000000 })
assert(waiting.auto_research_enabled == 0 and waiting.research_status_code == "queue_available")
transactions[10].queue_count = 6
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, transactions[10])
assert(buildings[1].unit.abilities[name].active, "seventh task remains available")
local function queue_runtime()
    return builder.build(name, {
        player_id = 0, building_id = "building_research_lab", unit = buildings[1].unit,
        research_levels = levels[0], research_transaction = transactions[10],
        reincarnation_level = 10,
    }, { gold = 1000000, wood = 1000000 })
end
assert(queue_runtime().available == 1, "runtime allows seventh task")
transactions[10].queue_count = 7
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, transactions[10])
assert(not buildings[1].unit.abilities[name].active, "eighth task rejected when queue full")
assert(queue_runtime().available == 0 and queue_runtime().research_status_code == "research_queue_full")
transactions[10].capacity = nil
assert(queue_runtime().research_queue_capacity == 7, "default runtime capacity matches seven slots")
transactions[10].capacity = 7
assert(buildings[2].unit.abilities[name].active, "another player's queue remains available")
transactions[10] = { player_id = 0, source_entindex = 10, researching = 0,
    auto_research = { lumberjack_speed = 1 }, next_start_at = 8 }
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, transactions[10])
assert(buildings[1].unit.abilities[name].active, "completion activates manual research")
print("RESEARCH_RUNTIME_PROJECTION_PASS: source-specific activation, unrelated completion, right-click state, absolute timing")
