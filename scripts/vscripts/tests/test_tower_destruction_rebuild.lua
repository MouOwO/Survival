-- Real building lifecycle, route limits, event bus and placement grid; only
-- engine entities and independent visual/economy services are substituted.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local config = require("config/buildings_config")
local noop = function() end
local units, entities, next_index = {}, {}, 0
local destroyed, pop_releases, visuals = {}, {}, {}
local fail_visual, fail_construction, warnings = false, false, 0
for _, name in ipairs({"tower_skill_runtime", "building_population_service", "asset_preload_service",
    "building_sound_service", "tower_utility_ability_sync", "wall_destruction_visual", "tower_ability_sync",
    "war3_armor_target", "wall_collision_barrier_service", "online_time_service"}) do
    package.loaded["systems/" .. name] = {reset = noop, apply = noop, sync = noop,
        clear = noop, play = noop, queue_particle = noop}
end
package.loaded["systems/building_construction_visual_service"] = {
    reset = noop, cancel = function() if fail_construction then error("injected construction cleanup failure") end end,
}
package.loaded["systems/building_visual_service"] = {
    init = noop, clear = noop,
    play_death = function(unit)
        visuals[unit] = (visuals[unit] or 0) + 1
        if fail_visual then error("injected death visual failure") end
        assert(not unit:IsAlive(), "death visual must not create another live tower")
        return true
    end,
}
package.loaded["systems/building_relocation"] = {bind = noop}
package.loaded["debug/dev_wall_stats"] = {apply = noop, reset = noop}
package.loaded["core/team_alignment"] = {enforce = noop}
package.loaded["core/logger"] = {info = noop, warn = function() warnings = warnings + 1 end}
package.loaded["core/scheduler"] = {cancel = noop, every = noop, after = noop}
package.loaded["systems/rogue_effect_state_service"] = {numeric = function() return 0 end}
package.loaded["systems/multiplayer_player_service"] = {is_disconnected = function() return false end}
package.loaded["systems/forbidden_region_service"] = {validate_building_footprint = function() return true end}

class = function(value) return value end
LinkLuaModifier, IsServer = noop, function() return true end
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3, 1, 2
DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 4, 16, 0
local vector_mt = {}
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector_mt) end
vector_mt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_mt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_mt.__index = {Length2D = function(v) return math.sqrt(v.x * v.x + v.y * v.y) end}
GameRules = {GetGameTime = function() return 0 end}
GetGroundHeight = function() return 0 end
GridNav = {IsTraversable = function() return true end, IsBlocked = function() return false end,
    IsNearbyTree = function() return false end}
Entities = {FindAllByClassname = function() return units end}
EntIndexToHScript = function(id) return entities[id] end
FindUnitsInRadius = function() return units end
local destroy_ability = {IsNull = function() return false end,
    IsHidden = function() return false end, IsActivated = function() return true end}
local function tower(grid_x, class_id)
    next_index = next_index + 1
    local unit = {index = next_index, alive = true, modifiers = {},
        position = Vector((grid_x + 1) * 64, 64, 0),
        survival_is_building = true, survival_building_id = "arrow_tower", survival_player_id = 0,
        survival_level = class_id and 6 or 1, survival_tower_class = class_id,
        survival_grid_x = grid_x, survival_grid_y = 0,
        survival_grid_footprint = config.arrow_tower.footprint, survival_population_occupied = 3}
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:GetUnitName() return config[self.survival_building_id].unit_name end
    function unit:GetAbsOrigin() return self.position end
    function unit:SetAbsOrigin(position) self.position = position end
    function unit:GetTeamNumber() return 2 end
    function unit:GetPlayerOwnerID() return 0 end
    function unit:GetMaxHealth() return 100 end
    function unit:GetPhysicalArmorBaseValue() return 0 end
    function unit:SetHullRadius(radius) self.hull = radius end
    function unit:GetHullRadius() return self.hull or 0 end
    function unit:SetAcquisitionRange() end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:AddNewModifier(_, _, name) self.modifiers[name] = {}; return self.modifiers[name] end
    function unit:FindAbilityByName(name)
        if name == "ability_destroy_arrow_tower" then return destroy_ability end
    end
    -- Intentionally no engine event: the real method must complete logical
    -- removal synchronously instead of relying on a later entity_killed tick.
    function unit:ForceKill() self.alive = false end
    units[#units + 1], entities[unit.index] = unit, unit
    return unit
end
local grid = require("systems/grid_placement_system")
local building = require("systems/building_system")
local builder = {IsNull = function() return false end, IsAlive = function() return true end}
local function query(unit)
    return bus.request(events.BUILDING_QUERY_REQUEST, {entindex = unit:entindex()})
end
local function base_count() return building._building_limit_for_test.count_for(0, "arrow_tower") end
local function can_place(unit)
    return assert(bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = unit.position, footprint = config.arrow_tower.footprint,
    }))
end
local function can_build(unit)
    return assert(bus.request(events.BUILD_CAN_PLACE_REQUEST, {
        player_id = 0, caster = builder, building_id = "arrow_tower", position = unit.position,
    }))
end
local function occupied(unit)
    local cells = grid._occupied_for_test()
    return cells[unit.survival_grid_x] and cells[unit.survival_grid_x][unit.survival_grid_y]
end
local function slot(class_id, operation, unit)
    return assert(bus.request(events.TOWER_CLASS_SLOT_REQUEST, {player_id = 0,
        class_id = class_id, operation = operation or "snapshot", entindex = unit and unit:entindex()}))
end
local function fixture()
    bus.reset(); units, entities, next_index = {}, {}, 0
    destroyed, pop_releases, visuals = {}, {}, {}; fail_visual, fail_construction, warnings = false, false, 0
    for i = 1, 7 do tower(-14 + (i - 1) * 4) end
    local city = tower(0)
    city.survival_building_id, city.survival_grid_y = "main_city", 10
    city.survival_grid_footprint = config.main_city.footprint
    city.position = Vector(64, 704, 0)
    bus.handle_request(events.BUILDER_GET_REQUEST, function() return {ok = true, player_id = 0, builder = builder} end)
    bus.handle_request(events.RESOURCE_RELEASE_POP_REQUEST, function(payload)
        pop_releases[#pop_releases + 1] = payload; return {ok = true}
    end)
    bus.subscribe(events.BUILDING_DESTROYED, function(payload) destroyed[#destroyed + 1] = payload end)
    grid.init(); building.init()
    assert(config.arrow_tower.max_count == 7 and base_count() == 7)
    assert(not can_build(units[1]).ok, "seven living basic towers is the configured cap")
    return units[1]
end
local victim = fixture()
assert(occupied(victim) == victim:entindex())
assert(building.destroy_arrow_tower_for_player(0, victim:entindex()))
assert(base_count() == 6 and occupied(victim) == nil,
    "manual destroy must release the count/grid before returning, without any engine death event")
assert(#destroyed == 1 and #pop_releases == 1 and pop_releases[1].population == 3)
assert(visuals[victim] == 1 and not victim:IsAlive() and not victim:IsNull(), "native corpse remains during visual tail")
local placement, build_check = can_place(victim), can_build(victim)
assert(placement.ok and build_check.ok, "a dead corpse cannot block its immediately reusable footprint: "
    .. tostring(placement.error) .. "/" .. tostring(build_check.error))
assert(query(victim) == nil and base_count() == 6, "stale selected-corpse query cannot recover it into live state")
local replacement = tower(victim.survival_grid_x)
assert(query(replacement) and base_count() == 7 and occupied(replacement) == replacement:entindex())
assert(not can_build(victim).ok, "replacement restores the seven-tower cap")
for _ = 1, 3 do bus.emit(events.ENGINE_ENTITY_KILLED, {victim = victim}) end
assert(base_count() == 7 and #destroyed == 1 and #pop_releases == 1)
assert(occupied(replacement) == replacement:entindex(), "late corpse events must not free a replacement's cells")
assert(not building.destroy_arrow_tower_for_player(0, victim:entindex()), "destroying an already retired tower rejects")

-- Natural damage deaths and optional visual errors use the same resilient
-- retirement path; neither error may strand the slot, population or tile.
victim = fixture(); fail_visual, fail_construction = true, true
victim.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = victim})
assert(base_count() == 6 and occupied(victim) == nil and #destroyed == 1 and #pop_releases == 1)
assert(warnings == 2 and can_place(victim).ok and can_build(victim).ok)
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = victim})
assert(base_count() == 6 and #pop_releases == 1)

-- A promoted tower has its own class count. Death must clear every held route
-- reservation, not short-circuit after the first successful release.
victim = fixture()
local promoted = tower(14, "class_1")
assert(query(promoted) and base_count() == 7 and slot("class_1").count == 1)
for index = 1, 7 do assert(slot("class_" .. tostring(index), "reserve", promoted).ok) end
assert(slot("class_3", "reserve", victim).ok)
promoted.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = promoted})
assert(base_count() == 7 and slot("class_1").count == 0 and occupied(promoted) == nil)
for index = 1, 7 do
    local expected_pending = index == 3 and 1 or 0
    assert(slot("class_" .. tostring(index)).pending == expected_pending, "released incorrect route reservation")
end
assert(#destroyed == 1 and #pop_releases == 1)
-- Individual defeat releases only the owner's buildings, counts and cells.
victim = fixture()
local survivor = tower(25)
survivor.survival_player_id = 1
assert(query(survivor) and occupied(survivor) == survivor:entindex())
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 0, defeat_cleanup = true})
assert(base_count() == 0 and #destroyed == 8 and #pop_releases == 7)
assert(not victim:IsAlive() and occupied(victim) == nil and query(victim) == nil)
assert(survivor:IsAlive() and query(survivor) and occupied(survivor) == survivor:entindex())
assert(building._building_limit_for_test.count_for(1, "arrow_tower") == 1)
for _, unit in ipairs(units) do
    if unit.survival_player_id == 0 then
        bus.emit(events.ENGINE_ENTITY_KILLED, {victim = unit})
    end
end
assert(#destroyed == 8 and #pop_releases == 7, "late cleanup events cannot release resources twice")
print("TOWER_DESTRUCTION_REBUILD_PASS: synchronous manual cleanup, live cap, immediate rebuild, delayed duplicate, natural death, visual failures, all route reservations")
