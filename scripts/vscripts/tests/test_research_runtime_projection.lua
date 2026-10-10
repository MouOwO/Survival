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
        function a:SetLevel(value) self.level = value; self.writes=(self.writes or 0)+1 end
        function a:SetHidden(value) self.hidden = value; self.writes=(self.writes or 0)+1 end
        function a:SetActivated(value) self.active = value; self.writes=(self.writes or 0)+1 end
        function a:SetAbilityIndex(value) self.index = value; self.writes=(self.writes or 0)+1 end
        function a:GetLevel() return self.level end
        function a:IsHidden() return self.hidden end
        function a:IsActivated() return self.active end
        function a:GetAbilityIndex() return self.index end
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
assert(buildings[1].unit.abilities[name].active, "queue full keeps the unlocked action clickable for its error response")
assert(queue_runtime().available == 0 and queue_runtime().research_status_code == "research_queue_full")
assert(queue_runtime().prerequisite_met == 1, "queue occupancy is not a learning prerequisite")
transactions[10].capacity = nil
assert(queue_runtime().research_queue_capacity == 7, "default runtime capacity matches seven slots")
transactions[10].capacity = 7
assert(buildings[2].unit.abilities[name].active, "another player's queue remains available")
transactions[10] = { player_id = 0, source_entindex = 10, researching = 0,
    auto_research = { lumberjack_speed = 1 }, next_start_at = 8 }
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, transactions[10])
assert(buildings[1].unit.abilities[name].active, "completion activates manual research")
local locked_name = "ability_research_ars_03"
local definition = config.by_legacy_group.researcher_super_wall_health
local prerequisite = assert(config.by_id[definition.prerequisite.tech_id])
local function locked_runtime(rebirth)
    return builder.build(locked_name, {
        player_id = 0, building_id = "building_advanced_research_lab",
        research_levels = levels[0], research_transaction = {}, reincarnation_level = rebirth,
    }, {gold = 1000000, wood = 1000000})
end
assert(locked_runtime(10).available == 0 and locked_runtime(10).prerequisite_met == 0)
assert(locked_runtime(10).research_status_code == "prerequisite_not_met")
assert(locked_runtime(10).auto_research_available == 0)
sync.sync(buildings[3].unit, "building_advanced_research_lab", levels[0], {}, 10)
assert(buildings[3].unit.abilities[locked_name].active,"shared native action cannot use only the owner's prerequisites")
levels[0][prerequisite.legacy_group] = definition.prerequisite.required_level
assert(builder.build("ability_research_ars_08", {
    player_id = 0, building_id = "building_advanced_research_lab",
    research_levels = levels[0], research_transaction = {}, reincarnation_level = 0,
}, {gold = 1000000, wood = 1000000}).available == 0,
    "rebirth requirement also locks the research entrance")
assert(locked_runtime(10).available == 1)
assert(locked_runtime(10).prerequisite_met == 1)
sync.sync(buildings[3].unit, "building_advanced_research_lab", levels[0], {}, 10)
assert(buildings[3].unit.abilities[locked_name].active)
print("RESEARCH_RUNTIME_PROJECTION_PASS: source-specific activation, unrelated completion, right-click state, absolute timing")

-- Every research prerequisite is checked consistently by runtime and native activation.
local mappings = require("config/generated/research_lab_abilities")
local checked = 0
for _, row in ipairs(mappings.rows) do
    local definition = config.by_legacy_group[row.technology_group]
    local required = definition and definition.prerequisite or {}
    if row.enabled ~= false and required.tech_id then
        local owner = unit(90)
        local result = builder.build(row.ability_name, { player_id = 0, building_id = row.building_id,
            unit = owner, research_levels = {}, research_transaction = {}, reincarnation_level = 10 }, {})
        assert(result.available == 0 and result.research_status_code == "prerequisite_not_met", row.ability_name)
        if row.building_id == "building_advanced_research_lab" then
            sync.sync(owner, row.building_id, {}, {}, 10)
            assert(owner.abilities[row.ability_name].active, "shared action keeps teammate access; personal runtime remains gray")
        end
        checked = checked + 1
    end
end
assert(checked > 0)
print("RESEARCH_PREREQUISITE_GREY_PASS " .. checked .. " dependent technologies")
-- Equal state must not rewrite every native ability on each research event.
local stable=unit(999)
sync.sync(stable,"building_research_lab",{},nil,10)
local writes=0
for _,a in pairs(stable.abilities) do writes=writes+(a.writes or 0) end
for index=1,1000 do sync.sync(stable,"building_research_lab",{},nil,10) end
local after=0
for _,a in pairs(stable.abilities) do after=after+(a.writes or 0) end
assert(after==writes,"unchanged research state must not repeatedly reset native skills")
local all_max={}
for _,definition in ipairs(config.technologies) do all_max[definition.legacy_group]=definition.max_level end
sync.sync(stable,"building_research_lab",all_max,nil,10)
assert(next(stable.abilities)==nil,"terminal max-level research removes its action")
local shared=unit(998)
sync.sync(shared,"building_advanced_research_lab",all_max,nil,10)
assert(next(shared.abilities),"shared lab keeps action slots for unfinished teammates")
for _,a in pairs(shared.abilities) do assert(a.active,"owner max must not deactivate shared native actions") end
local runtime=builder.build("ability_research_lumberjack_speed",{player_id=0,
    research_levels={},research_transaction={},reincarnation_level=10},{wood=0,gold=0})
assert(runtime.available==1 and runtime.can_afford==1,"resource shortage cannot change research prerequisite shading")
assert(runtime.prerequisite_met==1 and runtime.resource_check_on_cast==1)
local reserved_to_max = {queue_count=1,capacity=7,reserved_levels={lumberjack_speed=config.by_legacy_group.lumberjack_speed.max_level}}
local reserved_runtime = builder.build(name,{player_id=0,building_id="building_research_lab",
    research_levels={},research_transaction=reserved_to_max,reincarnation_level=10},{wood=0,gold=0})
assert(reserved_runtime.available==0 and reserved_runtime.prerequisite_met==1
    and reserved_runtime.completed==0,"a reserved last level must not look prerequisite-locked or completed")
sync.sync(stable,"building_research_lab",{},reserved_to_max,10)
assert(stable.abilities[name].active,"reserved levels are rejected on click, not by disabling the native action")
print("RESEARCH_STATE_STABILITY_PASS: 1000 unchanged syncs, terminal removal, shared slots, resource-independent prerequisites")
