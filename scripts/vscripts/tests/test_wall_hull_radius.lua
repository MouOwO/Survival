package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

local subscribers = {}
package.loaded["core/event_bus"] = {
    emit = function() end,
    request = function() return nil end,
    handle_request = function() end,
    subscribe = function(event_name, handler)
        subscribers[event_name] = subscribers[event_name] or {}
        subscribers[event_name][#subscribers[event_name] + 1] = handler
    end,
}
package.loaded["core/modifier_registry"] = { register = function() end }
package.loaded["core/team_alignment"] = { enforce = function() return true end }
package.loaded["systems/tower_skill_runtime"] = { apply = function() end }
package.loaded["core/scheduler"] = {
    every = function() end,
    after = function() end,
}
package.loaded["systems/building_population_service"] = {
    grant_level = function() return 0 end,
}
package.loaded["systems/building_visual_service"] = {
    apply = function() return true end,
    clear = function() end,
}
package.loaded["systems/building_relocation"] = { bind = function() end }
-- Barrier geometry has its own integration coverage; this fixture checks hull setup.
package.loaded["systems/wall_collision_barrier_service"] = {
    create = function() end,
    clear = function() end,
}

local grid = require("config/grid_placement_config")
local buildings = require("config/buildings_config")
local events = require("core/events")
local building_system = require("systems/building_system")

local wall = assert(buildings.wall, "wall definition is missing")
assert(wall.footprint.x == 4 and wall.footprint.y == 4,
    "wall footprint must remain 4x4")
assert(tonumber(grid.cell_size) == 64, "grid cell size must remain 64")
assert(tonumber(wall.hull_radius) == 256,
    "wall hull radius must remain at the configured 256 units")

local new_wall_radius = nil
local new_wall = {}
function new_wall:IsNull() return false end
function new_wall:SetBaseMaxHealth() end
function new_wall:SetMaxHealth() end
function new_wall:SetHealth() end
function new_wall:SetPhysicalArmorBaseValue() end
function new_wall:SetModel() end
function new_wall:SetOriginalModel() end
function new_wall:SetHullRadius(radius) new_wall_radius = radius end

local apply_initial_stats = assert(
    building_system._apply_initial_stats_for_test,
    "building initial stats test API is unavailable"
)
apply_initial_stats(new_wall, wall)
assert(new_wall_radius == 256 and new_wall.survival_hull_radius == 256,
    "new wall did not receive the configured 256 hull radius")
new_wall_radius = nil
assert(building_system._apply_hull_radius_for_test(new_wall, wall) == true
        and new_wall_radius == 256,
    "reapplying the wall hull radius must remain idempotent")

local recovered_wall_radius = nil
local recovered_wall = {
    survival_is_building = true,
    survival_building_id = "wall",
    survival_level = 1,
    survival_player_id = 0,
}
function recovered_wall:IsNull() return false end
function recovered_wall:entindex() return 901 end
function recovered_wall:GetUnitName() return "building_wall" end
function recovered_wall:GetTeamNumber() return 2 end
function recovered_wall:GetPlayerOwnerID() return 0 end
function recovered_wall:GetAbsOrigin() return { x = 0, y = 0, z = 0 } end
function recovered_wall:HasModifier() return false end
function recovered_wall:AddNewModifier() end
function recovered_wall:SetHullRadius(radius) recovered_wall_radius = radius end

Entities = {
    FindAllByClassname = function(_, class_name)
        if class_name == "npc_dota_creature" then return { recovered_wall } end
        return {}
    end,
}
building_system.init()
assert(recovered_wall_radius == 256
        and recovered_wall.survival_hull_radius == 256,
    "recovered wall did not restore the configured 256 hull radius")
recovered_wall_radius = nil
assert(subscribers[events.BUILDING_CHANGED]
        and subscribers[events.BUILDING_CHANGED][1],
    "building change handler was not registered")
subscribers[events.BUILDING_CHANGED][1]({
    entindex = 901,
    level = 2,
})
assert(recovered_wall_radius == 256,
    "wall upgrade did not preserve the configured 256 hull radius")

local apply_hull_radius = assert(building_system._apply_hull_radius_for_test,
    "building hull radius test API is unavailable")
local colliding = assert(building_system._colliding_buildings_for_test,
    "building collision whitelist test API is unavailable")
assert(colliding.wall == true and colliding.main_city == true,
    "wall and main city must remain in the collision whitelist")

local expected_radii = {
    wall = 256,
    main_city = 48, -- Current 2x2 placement footprint; visual mesh is larger.
    building_farm = 0,
    arrow_tower = 0,
    building_research_lab = 0,
    gold_mine = 0,
    hero_altar = 0,
}
local definitions_seen = {}
for key, definition in pairs(buildings) do
    if type(definition) == "table" and definition.id
        and expected_radii[definition.id] ~= nil then
        definitions_seen[definition.id] = true
        local applied_radius = nil
        local building = {}
        function building:IsNull() return false end
        function building:SetHullRadius(radius) applied_radius = radius end
        assert(apply_hull_radius(building, definition) == true,
            "hull application failed for " .. tostring(definition.id))
        assert(applied_radius == expected_radii[definition.id]
                and building.survival_hull_radius == expected_radii[definition.id],
            "unexpected hull radius for " .. tostring(definition.id))
        assert((colliding[definition.id] == true)
                == (expected_radii[definition.id] > 0),
            "collision whitelist mismatch for " .. tostring(definition.id))
    end
end
local definition_count = 0
for _ in pairs(definitions_seen) do definition_count = definition_count + 1 end
assert(definition_count == 7,
    "building collision test did not cover every building definition")

print("WALL_HULL_RADIUS_PASS")
