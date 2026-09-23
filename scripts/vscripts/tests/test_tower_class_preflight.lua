-- Real route limits, wallets, upgrade dispatch and UI router; mock only engine
-- entities, rendering and the asynchronous upgrade process. Failed requests
-- must not briefly publish a reservation, sync abilities or start a cooldown.
package.path = "scripts/vscripts/?.lua;" .. package.path
unpack = unpack or table.unpack
local bus = require("core/event_bus")
local events = require("core/events")
local routes = require("config/tower_route_config")
local config = require("config/buildings_config")
local noop = function() end
local calls, active, units, entities, listeners, packets = {}, {}, {}, {}, {}, {}
local frozen, next_index, unavailable_resources = false, 0, false
local function count(name) calls[name] = (calls[name] or 0) + 1 end
local function counted(name) return function() count(name) end end
for _, name in ipairs({"tower_skill_runtime", "building_population_service", "asset_preload_service",
    "building_sound_service", "tower_utility_ability_sync", "wall_destruction_visual",
    "building_construction_visual_service", "war3_armor_target", "wall_collision_barrier_service", "online_time_service"}) do
    package.loaded["systems/" .. name] = {reset = noop, apply = noop, sync = noop, grant_level = noop,
        construction_started = noop, construction_completed = noop, upgrade_completed = noop,
        queue_particle = noop, complete = noop, cancel = noop, start = function() return {} end}
end
package.loaded["systems/tower_ability_sync"] = {reset = noop, sync = counted("ability_sync")}
package.loaded["systems/building_visual_service"] = {apply = counted("visual")}
package.loaded["systems/building_relocation"] = {bind = noop}
package.loaded["debug/dev_wall_stats"] = {apply = noop, reset = noop}
package.loaded["core/team_alignment"] = {enforce = noop}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end, wall_health_flat = function() return 0 end}
package.loaded["systems/technology_stat_manager"] = {get = function() return {final = {tower = {}}} end}
package.loaded["systems/player_profile_service"] = {get_profile = function()
    return {save = {gameplay_stats = {initial_wood = 100000, initial_gold = 100000, initial_population_cap = 100}}}
end}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen = function() return frozen end}
package.loaded["core/scheduler"] = {cancel = noop, every = noop, after = noop}
package.loaded["systems/startup_loading_service"] = {is_player_ready = function() return true end}
package.loaded["systems/building_upgrade_process"] = {
    reset = function() active = {} end,
    is_active = function(unit) return active[unit:entindex()] ~= nil end,
    begin = function(unit, options)
        count("upgrade_start")
        assert(not active[unit:entindex()], "cannot start the same tower twice")
        active[unit:entindex()] = options
        options.on_start()
        return {ok = true, pending = true}
    end,
}
for _, name in ipairs({"ui/weapon_synthesis_snapshot_service", "systems/hero_summon_projection",
    "systems/building_batch_upgrade_service", "systems/gold_mine_batch_upgrade_service"}) do
    package.loaded[name] = {}
end
package.loaded["systems/hero_summon_projection"].hero_id_for_summon_ability = function() return nil end
package.loaded["ui/combat_stat_projection"] = {for_ui = function(value) return value end}

class = function(value) return value end
LinkLuaModifier, IsServer = noop, function() return true end
DOTA_UNIT_CAP_RANGED_ATTACK, DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_MOVE_NONE = 2, 1, 0
DOTA_TEAM_GOODGUYS, DOTA_ABILITY_BEHAVIOR_POINT = 2, 16
bit = {band = function(a, b) return a == b and b or 0 end}
local vector_mt = {}
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector_mt) end
vector_mt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_mt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_mt.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
vector_mt.__index = {Length2D = function(v) return math.sqrt(v.x * v.x + v.y * v.y) end}
GameRules = {GetGameTime = function() return 0 end}
GetGroundHeight = function() return 0 end
local player_handles = {[0] = {}, [1] = {}}
PlayerResource = {GetTeam = function() return 2 end,
    IsValidPlayerID = function(_, id) return player_handles[id] ~= nil end,
    GetPlayer = function(_, id) return player_handles[id] end}
Entities = {FindAllByClassname = function() return units end}
EntIndexToHScript = function(id) return entities[id] end
CustomGameEventManager = {
    RegisterListener = function(_, name, callback) listeners[name] = callback return name end,
    Send_ServerToPlayer = function(_, _, name, payload) packets[#packets + 1] = {name = name, payload = payload} end,
}

local function create_tower(level, owner)
    next_index = next_index + 1
    local u = {index = next_index, owner = owner or 0, position = Vector(next_index * 400, 0, 0),
        max_health = 100, health = 100, base_damage = 10, modifiers = {}, abilities = {},
        survival_is_building = true, survival_building_id = "arrow_tower", survival_player_id = owner or 0,
        survival_level = level or 5, survival_population_occupied = 0,
        survival_grid_x = next_index * 8, survival_grid_y = 0, survival_grid_footprint = config.arrow_tower.footprint}
    function u:IsNull() return false end
    function u:IsAlive() return true end
    function u:entindex() return self.index end
    function u:GetUnitName() return "building_arrow_tower" end
    function u:GetAbsOrigin() return self.position end
    function u:GetTeamNumber() return 2 end
    function u:GetPlayerOwnerID() return self.owner end
    function u:GetMaxHealth() return self.max_health end
    function u:GetHealth() return self.health end
    function u:GetBaseDamageMin() return self.base_damage end
    function u:GetPhysicalArmorBaseValue() return self.armor or 0 end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:AddNewModifier(_, _, name) count("entity_write"); self.modifiers[name] = {}; return self.modifiers[name] end
    function u:RemoveModifierByName(name) count("entity_write"); self.modifiers[name] = nil end
    function u:FindAbilityByName(name) return self.abilities[name] end
    for _, method in ipairs({"SetBaseMaxHealth", "SetMaxHealth", "SetHealth", "SetBaseDamageMin", "SetBaseDamageMax",
        "SetPhysicalArmorBaseValue", "SetBaseAttackTime", "SetRangedProjectileName", "SetProjectileSpeed",
        "SetAttackCapability", "SetMoveCapability", "SetHullRadius", "SetAbsOrigin", "SetModel", "SetOriginalModel",
        "SetModelScale", "SetAngles", "SetControllableByPlayer", "Script_SetAttackRange", "SetAcquisitionRange"}) do
        u[method] = counted("entity_write")
    end
    local a = {index = 10000 + u.index}
    function a:IsNull() return false end
    function a:entindex() return self.index end
    function a:GetAbilityName() return "ability_tower_class_1" end
    function a:GetCaster() return u end
    function a:IsPassive() return false end
    function a:GetBehaviorInt() return 0 end
    function a:GetLevel() return 1 end
    function a:GetCooldown() return 3 end
    function a:GetCooldownTimeRemaining() return 0 end
    function a:IsFullyCastable() return true end
    function a:IsActivated() return true end
    function a:IsHidden() return false end
    a.StartCooldown, a.EndCooldown = counted("cooldown_start"), counted("cooldown_end")
    a.SetHidden, a.SetActivated, a.SetLevel = counted("ability_write"), counted("ability_write"), counted("ability_write")
    u.abilities.ability_tower_class_1 = a
    units[#units + 1], entities[u.index], entities[a.index] = u, u, a
    return u
end

local real_request = bus.request
bus.request = function(event, payload)
    if event == events.RESOURCE_CAN_SPEND_REQUEST and unavailable_resources then return nil end
    if event == events.RESOURCE_TRY_SPEND_REQUEST then count("spend_request") end
    if event == events.TOWER_CLASS_SLOT_REQUEST and payload.operation == "reserve" then count("reserve_request") end
    return real_request(event, payload)
end
local resources = require("systems/resource_system")
local building = require("systems/building_system")
local upgrade = require("systems/building_upgrade_system")
local router = require("ui/ui_request_router")
local function wallet(id) return assert(bus.request(events.RESOURCE_GET_REQUEST, {player_id = id or 0})) end
local function slot() return assert(bus.request(events.TOWER_CLASS_SLOT_REQUEST, {operation = "snapshot", player_id = 0, class_id = "class_1"})) end
local function request(u, player)
    return bus.request(events.TOWER_CLASS_REQUEST, {tower = u, class_index = 1, player_id = player or 0})
end
local function fixture(settings)
    settings = settings or {}
    bus.reset(); units, entities, listeners, packets = {}, {}, {}, {}; frozen = false; next_index = 0; unavailable_resources = false
    local tower = create_tower(settings.level, settings.owner)
    for _ = 2, settings.towers or 1 do create_tower(5) end
    if settings.cold_building then Entities.FindAllByClassname = function() return {} end end
    resources.init(); building.init(); upgrade.init(); router.init()
    Entities.FindAllByClassname = function() return units end
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 1})
    if settings.cached then
        for _, unit in ipairs(units) do
            local snapshot = assert(bus.request(events.BUILDING_QUERY_REQUEST, {entindex = unit:entindex()}))
            bus.emit(events.BUILDING_CREATED, snapshot)
        end
    end
    for _, event in ipairs({events.RESOURCE_CHANGED, events.TOWER_CLASS_COUNTS_CHANGED, events.BUILDING_CHANGED, events.UI_NOTIFICATION}) do
        bus.subscribe(event, function() count(event) end)
    end
    calls, packets = {}, {}
    return tower
end
local function equal_balances(a, b, label)
    for _, field in ipairs({"wood", "gold", "population", "max_population", "version"}) do
        assert(a[field] == b[field], label .. " wallet changed: " .. field)
    end
end
local function assert_rejected(label, tower, player, invoke)
    local before, before_other, limits = wallet(), wallet(1), slot()
    local level, class_id, pop = tower.survival_level, tower.survival_tower_class, tower.survival_population_occupied
    calls, packets = {}, {}
    local result = invoke and invoke() or request(tower, player)
    assert(result and result.ok == false, label .. " must reject")
    equal_balances(before, wallet(), label); equal_balances(before_other, wallet(1), label)
    local after = slot()
    assert(after.count == limits.count and after.pending == limits.pending, label .. " mutated route slots")
    assert(tower.survival_level == level and tower.survival_tower_class == class_id
        and tower.survival_population_occupied == pop, label .. " changed tower state")
    for _, name in ipairs({events.RESOURCE_CHANGED, events.TOWER_CLASS_COUNTS_CHANGED, events.BUILDING_CHANGED,
        "ability_sync", "visual", "upgrade_start", "entity_write", "ability_write", "cooldown_start", "cooldown_end",
        "spend_request", "reserve_request"}) do
        assert((calls[name] or 0) == 0, label .. " unexpected side effect " .. name .. "=" .. tostring(calls[name]))
    end
end
local cost = routes.class_change_cost(routes.get("class_1", 1), {level = 5, population_occupied = 0})
assert(cost.wood > 0 and cost.gold > 0 and cost.population > 0, "fixture uses an actual paid population-increasing route")

-- Both previously registered towers and uncached upgrade-state recovery must
-- validate before any model/ability/stat synchronization or reservation event.
for _, cached in ipairs({false, true}) do
    local label = cached and "cached " or "uncached "
    local tower = fixture({level = 4, cached = cached}); assert_rejected(label .. "level", tower)
    tower = fixture({cached = cached}); assert_rejected(label .. "ownership", tower, 1)
    tower = fixture({cached = cached}); tower.modifiers.modifier_building_under_construction = {}
    assert_rejected(label .. "construction", tower)
    tower = fixture({cached = cached}); active[tower:entindex()] = {}
    assert_rejected(label .. "already upgrading", tower)
    tower = fixture({cached = cached})
    local limits = slot()
    for i = 1, limits.maximum do
        assert(bus.request(events.TOWER_CLASS_SLOT_REQUEST, {operation = "reserve", player_id = 0,
            class_id = "class_1", entindex = 9000 + i}).ok)
    end
    assert_rejected(label .. "full route", tower)
    for _, resource in ipairs({"wood", "gold", "population"}) do
        tower = fixture({cached = cached})
        local account = resources._test.accounts()[0]
        if resource == "population" then account.max_population = account.population + cost.population - 1
        else account[resource] = cost[resource] - 1 end
        assert_rejected(label .. resource .. " shortage", tower)
    end
    tower = fixture({cached = cached}); resources._test.accounts()[0].initialized = false
    assert_rejected(label .. "profile missing", tower)
    tower = fixture({cached = cached}); frozen = true
    assert_rejected(label .. "post-clear frozen", tower)
    tower = fixture({cached = cached}); unavailable_resources = true
    assert_rejected(label .. "resource service unavailable", tower)
end

-- Cold building-query recovery is also read-only: a rejected action must not
-- register a previously untracked tower or initialize its engine properties.
local tower = fixture({level = 4, cold_building = true})
assert_rejected("both states uncached", tower)
assert(bus.request(events.BUILDING_QUERY_REQUEST, {entindex = tower:entindex(), read_only = true}) == nil,
    "rejected readonly recovery must not populate building state")

-- CastFilterResult uses the check request repeatedly. Both accepted quotes and
-- rejected quotes must remain silent and side-effect free.
tower = fixture()
local before_quote = wallet()
calls = {}
for _ = 1, 3 do
    local quote = bus.request(events.TOWER_CLASS_CHECK_REQUEST, {tower = tower, player_id = 0, class_index = 1})
    assert(quote and quote.ok, "affordable readonly quote accepts")
end
equal_balances(before_quote, wallet(), "readonly quote")
assert(next(calls) == nil and slot().pending == 0, "successful quote publishes or reserves nothing")
resources._test.accounts()[0].gold = cost.gold - 1
assert_rejected("readonly rejected quote", tower, 0, function()
    return bus.request(events.TOWER_CLASS_CHECK_REQUEST, {tower = tower, player_id = 0, class_index = 1})
end)
assert((calls[events.UI_NOTIFICATION] or 0) == 0, "cast filter failure cannot spam notifications")

-- Exercise the actual Panorama dispatcher too: a failure never starts and
-- then rolls back a cooldown, even if the engine reports the ability castable.
local function ui_request(tower, player)
    local ability = tower.abilities.ability_tower_class_1
    listeners.ui_ability_cast_request(nil, {PlayerID = player or 0, player_id = 1,
        entindex = tower:entindex(), ability_entindex = ability:entindex()})
    for i = #packets, 1, -1 do
        if packets[i].name == "ui_ability_cast_result" then return {ok = packets[i].payload.success == 1} end
    end
    error("UI did not return a cast result")
end
tower = fixture()
resources._test.accounts()[0].wood = cost.wood - 1
assert_rejected("UI resource failure", tower, 0, function() return ui_request(tower) end)

-- Success holds a route slot and the exact charge through the asynchronous
-- transition; completion converts pending to built count without another fee.
tower = fixture()
local initial = wallet()
assert(ui_request(tower).ok and active[tower:entindex()])
assert(calls.cooldown_start == 1 and (calls.cooldown_end or 0) == 0, "successful UI request starts cooldown once")
local held, charged = slot(), wallet()
assert(held.count == 0 and held.pending == 1 and tower.survival_level == 5 and not tower.survival_tower_class)
assert(charged.wood == initial.wood - cost.wood and charged.gold == initial.gold - cost.gold
    and charged.population == initial.population + cost.population)
assert_rejected("same tower duplicate", tower)
local action = active[tower:entindex()]; active[tower:entindex()] = nil; action.on_complete()
assert(tower.survival_level == 6 and tower.survival_tower_class == "class_1", "completion applies chosen class")
assert(slot().count == 1 and slot().pending == 0, "completion replaces reservation with one built tower")
equal_balances(charged, wallet(), "completion")
assert((calls.visual or 0) > 0 and (calls.ability_sync or 0) > 0, "successful completion still applies visuals and abilities")

-- Two requests for the final slot cannot both start. Cancellation frees that
-- slot and refunds the exact charge, allowing the waiting tower to retry.
tower = fixture({towers = 2})
local second = units[2]
for i = 1, slot().maximum - 1 do
    assert(bus.request(events.TOWER_CLASS_SLOT_REQUEST, {operation = "reserve", player_id = 0,
        class_id = "class_1", entindex = 9000 + i}).ok)
end
initial = wallet(); assert(request(tower).ok)
assert(slot().pending == slot().maximum)
assert_rejected("competing last slot", second)
action = active[tower:entindex()]; active[tower:entindex()] = nil; action.on_cancel("test_cancel")
local refunded = wallet()
assert(refunded.wood == initial.wood and refunded.gold == initial.gold and refunded.population == initial.population)
assert(tower.survival_level == 5 and not tower.survival_tower_class and slot().pending == slot().maximum - 1)
assert(request(second).ok and active[second:entindex()], "released slot can be retried")

-- The readonly affordability path must retain real wallet semantics: debug
-- resources can bypass costs, while a missing profile and freeze cannot.
tower = fixture()
assert(bus.request(events.RESOURCE_DEBUG_SET_REQUEST, {player_id = 0, amount = 0}).ok)
initial = wallet(); calls = {}
assert(request(tower).ok, "debug wallet must not be rejected by a manual balance comparison")
local debug_after = wallet()
assert(debug_after.wood == initial.wood and debug_after.gold == initial.gold and debug_after.population == initial.population)

-- Native ability casts use the same authoritative readonly filter, preventing
-- the engine from beginning a cast/cooldown for known unaffordable requests.
UF_SUCCESS, UF_FAIL_CUSTOM = 0, 77
local ability_class = require("abilities/tower_class_ability_factory").create(1)
tower = fixture()
local native = setmetatable({GetCaster = function() return tower end,
    EndCooldown = counted("cooldown_end")}, {__index = ability_class})
resources._test.accounts()[0].wood = cost.wood - 1
assert_rejected("native cast filter", tower, 0, function()
    local filter = native:CastFilterResult()
    assert(filter == UF_FAIL_CUSTOM and native:GetCustomCastError():find("木材", 1, true),
        "native filter supplies the resource error")
    return {ok = filter == UF_SUCCESS}
end)
assert((calls[events.UI_NOTIFICATION] or 0) == 0, "hover/filter checks are silent")
resources._test.accounts()[0].wood = cost.wood
initial = wallet(); calls = {}
assert(native:CastFilterResult() == UF_SUCCESS)
equal_balances(initial, wallet(), "native affordable filter")
assert(next(calls) == nil and slot().pending == 0)
native:OnSpellStart()
assert(active[tower:entindex()] and slot().pending == 1 and (calls.cooldown_end or 0) == 0,
    "native success commits through the same route/wallet transaction")
local native_balance, native_pending = wallet(), slot().pending
calls = {}; IsServer = function() return false end
assert(native:CastFilterResult() == UF_SUCCESS)
native:OnSpellStart()
assert(next(calls) == nil and slot().pending == native_pending, "client prediction cannot reserve or spend")
equal_balances(native_balance, wallet(), "native client guard")
IsServer = function() return true end
print("TOWER_CLASS_PREFLIGHT_PASS: cached/uncached failure has no side effects; real wallet/route limits; UI cooldown and native filter; completion, competition, cancellation and debug semantics")
