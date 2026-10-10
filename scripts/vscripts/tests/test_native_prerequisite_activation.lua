-- Real runtime builder, service, definitions and event bus; engine transport
-- and authoritative lookup responses are the only substitutes.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local tasks, runtime, roster, registry_reads = {}, {}, {}, 0
local rogue_snapshots = {}
local city_level = 1
package.loaded["core/scheduler"] = {
    after = function(_, callback, id) tasks[id] = callback end,
    cancel = function(id) tasks[id] = nil end,
    every = function() error("activation must not poll") end,
}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    if name == "survival_ability_runtime" then runtime[key] = value end
end, GetTableValue = function(_, name, key)
    if name == "survival_rogue_reward" then return rogue_snapshots[key] end
end}
local errors, original_print = {}, print
print = function(message)
    if tostring(message):find("handler error", 1, true) then errors[#errors + 1] = tostring(message) end
end
local function unit(id, ability_names)
    if type(ability_names) == "string" then ability_names = {ability_names} end
    local abilities = {}
    for index, ability_name in ipairs(ability_names) do
        local ability = {active = true, level = 1, writes = 0}
        function ability:IsNull() return false end
        function ability:entindex() return id + 1000 + index - 1 end
        function ability:GetAbilityName() return ability_name end
        function ability:GetLevel() return self.level end
        function ability:SetLevel(value) self.level = value end
        function ability:IsActivated() return self.active end
        function ability:SetActivated(value) self.active = value; self.writes = self.writes + 1 end
        function ability:IsPassive() return false end
        abilities[index] = ability
    end
    local result = {ability = abilities[1], abilities = abilities}
    function result:IsNull() return false end
    function result:IsAlive() return true end
    function result:entindex() return id end
    function result:GetTeamNumber() return 2 end
    function result:GetPlayerOwnerID() return 0 end
    function result:GetAbilityCount() return #abilities end
    function result:GetAbilityByIndex(index) return abilities[index + 1] end
    function result:FindAbilityByName(name)
        for _, ability in ipairs(abilities) do
            if ability:GetAbilityName() == name then return ability end
        end
    end
    return result
end
local function value(entity) return assert(runtime[tostring(entity.ability:entindex())]) end
local function publish(entity, building_id, level, extra)
    local payload = {unit = entity, player_id = 0, team = 2, building_id = building_id, level = level}
    for key, v in pairs(extra or {}) do payload[key] = v end
    bus.emit(events.BUILDING_CHANGED, payload)
    assert(#errors == 0, table.concat(errors, "\n"))
end
bus.reset()
bus.handle_request(events.RESOURCE_GET_REQUEST, function() return {gold = 0, wood = 0} end)
bus.handle_request(events.BUILDING_UPGRADE_QUOTE_REQUEST, function(payload)
    if payload.building.requires_city and city_level < payload.building.requires_city then
        return {ok = false, prerequisite_met = 0, error = "city prerequisite"}
    end
    if payload.building.survival_upgrade_in_progress then return {ok = false, error = "busy"} end
    return {ok = true, prerequisite_met = 1}
end)
bus.handle_request(events.BUILDING_LIST_REQUEST, function()
    return {buildings = {{building_id = "main_city", level = city_level}}}
end)
bus.handle_request(events.WORKER_LIST_REQUEST, function()
    registry_reads = registry_reads + 1
    return roster
end)
local repairer_counts = {train_repairer_01 = 4, train_repairer_02 = 1}
local repairer_bonuses = {train_repairer_01 = 0, train_repairer_02 = 0}
bus.handle_request(events.WORKER_TRAINING_GET_REQUEST, function(payload)
    if payload.training_type ~= "repairer" then return nil end
    local definition = require("config/generated/training_definitions").by_id[payload.training_id]
    local progress = {}
    for key, item in pairs(assert(definition)) do progress[key] = item end
    progress.count = repairer_counts[payload.training_id]
    progress.max_count = progress.max_count + repairer_bonuses[payload.training_id]
    progress.completed = progress.count >= progress.max_count and 1 or 0
    return progress
end)
local service = require("ui/ability_runtime_service")
service.init()

local career = unit(1, "ability_tower_class_1")
publish(career, "arrow_tower", 5, {tower_class_counts = {class_1 = {count = 5, maximum = 5}}})
assert(value(career).available == 0 and value(career).prerequisite_met == 1 and career.ability.active,
    "route capacity must allow a native cast to reach the authoritative error response")
publish(career, "arrow_tower", 4)
assert(value(career).prerequisite_met == 0 and not career.ability.active,
    "the real level prerequisite still deactivates the native button")
publish(career, "arrow_tower", 5)
assert(career.ability.active, "level completion activates without any resource event")

local tower = unit(2, "ability_upgrade_tower")
tower.survival_upgrade_in_progress = true
publish(tower, "arrow_tower", 1, {upgrade_in_progress = 1})
assert(value(tower).available == 0 and value(tower).prerequisite_met == 1 and tower.ability.active
    and value(tower).engine_activated == 1,
    "the tower-specific activation pass must not disable a busy but unlocked cast")

local farm = unit(3, "ability_upgrade_farm")
farm.requires_city = 2
publish(farm, "building_farm", 1)
assert(not farm.ability.active and value(farm).prerequisite_met == 0)
local wall = unit(4, "ability_upgrade_wall")
wall.requires_city = 2
publish(wall, "wall", 1)
assert(not wall.ability.active and value(wall).prerequisite_met == 0)
local city = unit(5, "ability_upgrade_city")
city_level = 2
publish(city, "main_city", city_level)
assert(farm.ability.active and wall.ability.active,
    "a city level event immediately refreshes dependent farm and wall prerequisites")
farm.survival_upgrade_in_progress = true
publish(farm, "building_farm", 1, {upgrade_in_progress = 1})
assert(value(farm).available == 0 and value(farm).prerequisite_met == 1 and farm.ability.active,
    "the general upgrade path also permits server-side busy feedback")
local maximum = 0
for level in pairs(require("config/buildings_config").main_city.levels) do maximum = math.max(maximum, level) end
publish(city, "main_city", maximum)
assert(value(city).completed == 1 and not city.ability.active,
    "completed metadata remains available for HUD hiding and the native action stays inactive")

local repair_city = unit(20, {"ability_train_repairer", "ability_train_advanced_repairer"})
local ordinary, advanced = repair_city.abilities[1], repair_city.abilities[2]
local function repair_value(ability) return assert(runtime[tostring(ability:entindex())]) end
local function assert_repair_button(ability, active, reason)
    local projection = repair_value(ability)
    assert(ability.active == active and projection.engine_activated == (active and 1 or 0), reason)
    assert(projection.prerequisite_met == (active and 1 or 0), reason .. ": HUD gate matches native activation")
    assert(projection.completed ~= 1 and projection.removed ~= 1,
        reason .. ": repairer capacity keeps the button visible for its tooltip")
    assert(runtime["unit:20"].ability_count == 2, reason .. ": both training entrances remain present")
end
local function repairer_changed()
    -- The authoritative worker registry has already changed when this event
    -- arrives. The city refresh must happen synchronously, without a timer.
    bus.emit(events.WORKER_CHANGED, {player_id = 0, team = 2,
        worker_type = "repairer", entindex = 500, removed = true})
    assert(#errors == 0, table.concat(errors, "\n"))
end
publish(repair_city, "main_city", 1)
assert_repair_button(ordinary, true, "ordinary repairer below its five-unit cap")
assert_repair_button(advanced, true, "advanced repairer below its two-unit cap")
assert(repair_value(ordinary).resource_check_on_cast == 1
    and repair_value(advanced).resource_check_on_cast == 1,
    "an empty wallet must still admit below-cap repairer casts for server validation")
repairer_counts.train_repairer_01 = 5
repairer_changed()
assert_repair_button(ordinary, false, "five ordinary repairers disable ordinary training")
assert_repair_button(advanced, true, "ordinary cap does not disable advanced training")
assert(repair_value(ordinary).status_text == "修理工数量已达上限")
repairer_counts.train_repairer_02 = 2
repairer_changed()
assert_repair_button(ordinary, false, "ordinary training stays disabled while still full")
assert_repair_button(advanced, false, "two advanced repairers disable advanced training")
repairer_counts.train_repairer_01 = 4
repairer_changed()
assert_repair_button(ordinary, true, "ordinary removal reactivates its native training button immediately")
assert_repair_button(advanced, false, "ordinary removal leaves full advanced training disabled")
repairer_counts.train_repairer_02 = 1
repairer_changed()
assert_repair_button(advanced, true, "advanced removal reactivates its native training button immediately")
repairer_counts.train_repairer_01 = 5
repairer_changed()
assert_repair_button(ordinary, false, "ordinary cap can disable the restored button again")
repairer_bonuses.train_repairer_01 = 2
bus.emit(events.HERO_PROGRESSION_CHANGED, {player_id = 0, reason = "repairer_capacity_bonus"})
assert(#errors == 0, table.concat(errors, "\n"))
assert_repair_button(ordinary, true, "capacity bonus reactivates training without a resource or polling tick")
assert_repair_button(advanced, true, "ordinary capacity bonus keeps advanced availability independent")
assert(repair_value(ordinary).fields[1].value == "5/7",
    "the repairer tooltip uses the larger authoritative capacity")
original_print("REPAIRER_CAPACITY_ACTIVATION_PASS: independent five/two caps, visible buttons, empty wallet, worker-event restoration and capacity bonus")

local building_config = require("config/buildings_config")
local builder_buttons = {
    {name = "ability_build_arrow_tower", id = "arrow_tower"},
    {name = "ability_build_wall", id = "wall"},
    {name = "ability_build_main_city", id = "main_city"},
    {name = "ability_build_farm", id = "building_farm"},
    {name = "ability_build_research_lab", id = "building_research_lab"},
    {name = "ability_build_advanced_research_lab", id = "building_advanced_research_lab"},
    {name = "ability_build_challenge", id = "building_challenge"},
    {name = "ability_build_gold_mine", id = "gold_mine"},
    {name = "ability_build_hero_altar", id = "hero_altar"},
}
local builder_names, full_buildings = {}, {}
for index, button in ipairs(builder_buttons) do
    builder_names[index] = button.name
    full_buildings[button.id] = building_config[button.id].max_count
end
assert(full_buildings.arrow_tower == 7, "tower construction uses the configured seven-slot cap")
local builder = unit(30, builder_names)
local build_tower = builder.abilities[1]
local function builder_changed(event, tower_count)
    local counts = {}
    for id, maximum_count in pairs(full_buildings) do counts[id] = maximum_count end
    counts.arrow_tower = tower_count
    bus.emit(event, {unit = builder, building_id = "builder", player_id = 0, team = 2,
        city_level = 4, building_counts = counts})
    assert(#errors == 0, table.concat(errors, "\n"))
end
local function assert_tower_button(active, reason)
    local projection = value(builder)
    assert(build_tower.active == active and projection.engine_activated == (active and 1 or 0), reason)
    assert(projection.prerequisite_met == (active and 1 or 0), reason .. ": HUD gate matches native activation")
    assert(projection.completed ~= 1 and projection.removed ~= 1,
        reason .. ": capacity keeps construction visible for its tooltip")
    assert(runtime["unit:30"].ability_count == #builder_buttons,
        reason .. ": the native construction button remains in its slot")
    assert(projection.resource_check_on_cast == 1 and projection.can_afford == 1,
        reason .. ": an empty wallet is checked by the cast transaction")
end
builder_changed(events.BUILDER_STAGE_CHANGED, 6)
assert_tower_button(true, "six occupied towers allow native construction despite an empty wallet")
builder_changed(events.BUILDER_UNLOCK_CHANGED, 7)
assert_tower_button(false, "seven occupied towers synchronously gray and deactivate native construction")
assert(value(builder).available == 0)
for index = 2, #builder_buttons do
    local button, ability = builder_buttons[index], builder.abilities[index]
    local projection = assert(runtime[tostring(ability:entindex())])
    assert(projection.available == 0 and projection.prerequisite_met == 1 and ability.active,
        button.name .. ": other full building capacities retain their existing native cast semantics")
end
builder_changed(events.BUILDER_UNLOCK_CHANGED, 6)
assert_tower_button(true, "releasing a tower slot immediately restores native construction without a resource tick")
assert(value(builder).available == 1)
builder_changed(events.BUILDER_UNLOCK_CHANGED, 8)
assert_tower_button(false, "a count above seven cannot bypass the construction cap")
builder_changed(events.BUILDER_UNLOCK_CHANGED, 6)
assert_tower_button(true, "restoration remains repeatable after an over-cap snapshot")
original_print("TOWER_BUILD_CAPACITY_ACTIVATION_PASS: 6/7/6 synchronous native-HUD gate, visible button, empty wallet and unchanged other building caps")

-- The replicated talent state must remain authoritative while an engine
-- ability handle still reports its previous active behavior.
local talent_builder = unit(130, "ability_survival_rogue_reward")
local other_talent_builder = unit(131, "ability_survival_rogue_reward")
function other_talent_builder:GetPlayerOwnerID() return 1 end
bus.emit(events.BUILDER_READY, {builder = talent_builder, team = 2})
bus.emit(events.BUILDER_READY, {builder = other_talent_builder, team = 2})
assert(#errors == 0, table.concat(errors, "\n"))
assert(value(talent_builder).passive == 0 and value(talent_builder).talent_pending == 1)
assert(value(talent_builder).fields[1].label == "快捷键"
    and value(talent_builder).fields[1].value == "G", "pending talent retains its opening shortcut")
local other_pending = value(other_talent_builder)
rogue_snapshots["0"] = {talent_pending = 0, builder_talent = {
    card_id = "wall_recovery", name = "Wall Recovery", description = "Passive recovery",
    icon_name = "survival/native/talent_wall_recovery",
}}
bus.emit(events.ROGUE_REWARD_CHANGED, {player_id = 0, effects_changed = true})
assert(#errors == 0, table.concat(errors, "\n"))
local chosen_talent = value(talent_builder)
assert(not talent_builder.ability:IsPassive() and chosen_talent.passive == 1,
    "runtime service preserves the real builder's passive projection despite stale engine behavior")
assert(chosen_talent.talent_pending == 0 and #chosen_talent.fields == 0,
    "successful selection synchronously removes the reminder and tooltip shortcut")
assert(chosen_talent.available == 1 and chosen_talent.can_afford == 1
    and chosen_talent.completed ~= 1 and chosen_talent.removed ~= 1,
    "the selected passive remains visible, colored and hoverable")
assert(chosen_talent.icon_name == rogue_snapshots["0"].builder_talent.icon_name
    and chosen_talent.upgrade_description == rogue_snapshots["0"].builder_talent.description)
assert(value(other_talent_builder) == other_pending and other_pending.passive == 0,
    "selection republishes only the choosing player's talent")
bus.emit(events.BUILDER_STAGE_CHANGED, {unit = talent_builder, building_id = "builder",
    player_id = 0, team = 2, city_level = 1})
assert(value(talent_builder).passive == 1 and #value(talent_builder).fields == 0,
    "later builder stage refreshes cannot restore an active talent or its shortcut")
original_print("BUILDER_TALENT_RUNTIME_PASS: immediate selection, stale engine passive state, no chosen shortcut, retained hover/icon and player isolation")

for id = 11, 13 do
    local worker = unit(id, "ability_fuse_lumberjack_03")
    worker.survival_worker_type, worker.survival_player_id, worker.survival_lumberjack_level = "lumberjack", 0, 3
    roster[#roster + 1] = {unit = worker, player_id = 0, team = 2, worker_type = "lumberjack"}
    bus.emit(events.WORKER_CHANGED, roster[#roster])
end
local task_id = "ability_fusion_refresh_0:2"
local function flush()
    local callback = assert(tasks[task_id]); tasks[task_id] = nil; callback()
    assert(#errors == 0, table.concat(errors, "\n"))
end
flush()
assert(not roster[1].unit.ability.active)
city_level = 5
publish(city, "main_city", city_level)
flush()
assert(roster[1].unit.ability.active, "city level completion also unlocks fusion without a wallet tick")
registry_reads = 0
for _ = 1, 100 do publish(city, "main_city", city_level, {stats_only = true}) end
assert(tasks[task_id] == nil and registry_reads == 0,
    "stat-only city updates must not bypass the prerequisite event filter through a duplicate subscriber")
assert(#errors == 0, table.concat(errors, "\n"))
original_print("NATIVE_PREREQUISITE_ACTIVATION_PASS: capacity, real level gates, busy tower/general upgrades, completion, city dependencies and stat-only event filtering")
