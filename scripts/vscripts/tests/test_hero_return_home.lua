-- Real own-city resolver, forbidden regions, destination validation and owner
-- context. Only engine entities/terrain/transport are simulated.
package.path = "scripts/vscripts/?.lua;" .. package.path
local region_config = { rows = {} }
package.loaded["config/generated/build_forbidden_regions"] = region_config
package.loaded["systems/building_system"] = {
    main_city_for_team = function() error("return home must never use a team-wide city") end,
}
Vector = function(x, y, z) return { x = x, y = y, z = z or 0 } end
DOTA_TEAM_GOODGUYS, DOTA_UNIT_TARGET_TEAM_BOTH = 2, 3
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 16, 0
local bus, events = require("core/event_bus"), require("core/events")
local regions = require("systems/forbidden_region_service")
local context = require("systems/player_context_service")
local home = require("systems/hero_return_home_service")
local serial, moves, stops, dodges, exits, returns, camera, notices
local heroes, cities, registered, listed, obstacles, height, traversable, blocked
local query_count, fail_move
local function vector_copy(p) return Vector(p.x, p.y, p.z) end
local function unit(owner, position, hull)
    serial = serial + 1
    local u = { id = serial, survival_player_id = owner, origin = position,
        hull = hull or 32, alive = true, forward = Vector(1, 0, 0) }
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetPlayerOwnerID() return owner end
    function u:GetTeamNumber() return 2 end
    function u:GetAbsOrigin() return self.origin end
    function u:GetHullRadius() return self.hull end
    function u:GetForwardVector() return self.forward end
    function u:Stop() stops = stops + 1 end
    function u:SetAbsOrigin(p)
        moves = moves + 1
        if fail_move then
            fail_move = false
            self.origin = Vector(99999, 99999, 128)
        else self.origin = vector_copy(p) end
    end
    function u:FindAbilityByName() error("home service must not modify skill cooldowns") end
    return u
end
PlayerResource = {
    GetPlayer = function(_, id) return { id = id } end,
    GetTeam = function() return 2 end,
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
    GetSelectedHeroEntity = function() error("placeholder/selection must not identify formal hero") end,
}
CustomGameEventManager = { Send_ServerToPlayer = function(_, player, name, payload)
    camera[#camera + 1] = { player = player.id, name = name, payload = payload }
end }
ProjectileManager = { ProjectileDodge = function() dodges = dodges + 1 end }
GridNav = {
    IsTraversable = function(_, p) return p.x ~= 99999 and traversable(p) end,
    IsBlocked = function(_, p) return blocked(p) end,
}
GetGroundHeight = function(p) return height(p) end
FindClearSpaceForUnit = function() error("must not slide outside the checked landing") end
FindUnitsInRadius = function(_, origin, _, radius, team, kinds, flags)
    query_count = query_count + 1
    assert(team == 3 and kinds == 7 and flags == 16,
        "occupancy includes buildings and hidden invulnerable barriers")
    local found = {}
    for _, u in ipairs(obstacles) do
        local p = u:GetAbsOrigin()
        if (p.x-origin.x)^2 + (p.y-origin.y)^2 <= radius^2 then found[#found + 1] = u end
    end
    return found
end
local function reset()
    bus.reset(); context._reset_for_test()
    serial, moves, stops, dodges, exits, query_count = 100, 0, 0, 0, 0, 0
    returns, camera, notices = {}, {}, {}
    heroes = { [0] = unit(0, Vector(-4000, 0, 128)), [1] = unit(1, Vector(-5000, 0, 128)) }
    for id, hero in pairs(heroes) do hero.survival_hero_id = "hero_" .. tostring(id) end
    registered = { [0] = heroes[0], [1] = heroes[1] }
    cities = { [0] = unit(0, Vector(2000, 0, 128), 48), [1] = unit(1, Vector(7000, 1000, 128), 48) }
    -- The mocked list intentionally includes a same-team foreign city first.
    listed = {
        { building_id = "main_city", player_id = 1, unit = cities[1] },
        { building_id = "main_city", player_id = 0, unit = cities[0] },
    }
    obstacles = { cities[0], cities[1], heroes[0], heroes[1] }
    height = function() return 128 end
    traversable = function() return true end
    blocked = function() return false end
    fail_move = false; region_config.rows = {}; regions.init()
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(p)
        return { ok = registered[p.player_id] ~= nil, unit = registered[p.player_id] }
    end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function(p)
        assert(p.player_id == 0 or p.player_id == 1, "city request is player-specific")
        return { ok = true, buildings = listed }
    end)
    bus.handle_request(events.TRAINING_ROOM_EXIT_REQUEST, function(p)
        assert(p.reason == "return_home")
        assert(moves > 0, "exit is only requested after movement succeeds")
        exits = exits + 1; return { ok = true }
    end)
    bus.subscribe(events.HERO_RETURNED_HOME, function(p)
        returns[#returns + 1] = p
        assert(p.hero:GetAbsOrigin().x == p.position.x)
    end)
    bus.subscribe(events.UI_NOTIFICATION, function(p) notices[#notices + 1] = p end)
end
local function no_return_effects()
    assert(exits == 0 and #returns == 0 and #camera == 0,
        "rejected/failed return cannot exit challenges, begin retry or move camera")
end
local function distance(a, b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end

reset()
assert(home.return_unit(heroes[0], 0).ok)
assert(heroes[0].origin.x == 2256 and heroes[0].origin.y == 0)
assert(home.return_unit(heroes[1], 1).ok)
assert(heroes[1].origin.x == 7256 and heroes[1].origin.y == 1000,
    "same-team second player returns beside own city")
assert(exits == 2 and #returns == 2 and dodges == 2 and stops == 2)
assert(camera[1].player == 0 and camera[1].payload.entindex == heroes[0].id)
assert(camera[2].player == 1 and camera[2].payload.target_x == heroes[1].origin.x)

for _, invalid in ipairs({ "foreign_hero", "clone", "unregistered", "dead", "owner_conflict" }) do
    reset()
    local candidate = heroes[0]
    if invalid == "foreign_hero" then candidate = heroes[1]
    elseif invalid == "clone" then candidate = unit(0, Vector(-6000, 0, 128)); candidate.survival_hero_id = "hero_0"
    elseif invalid == "unregistered" then registered[0] = nil
    elseif invalid == "dead" then candidate.alive = false
    else candidate.survival_player_id = 1 end
    assert(not home.return_unit(candidate, 0).ok, invalid)
    assert(moves == 0 and query_count == 0); no_return_effects()
end

for _, invalid in ipairs({ "missing", "foreign_only", "constructing", "dead" }) do
    reset()
    if invalid == "missing" then listed = {}
    elseif invalid == "foreign_only" then table.remove(listed, 2)
    elseif invalid == "constructing" then listed[2].constructing = true
    else cities[0].alive = false end
    local result = home.return_unit(heroes[0], 0)
    assert(not result.ok and result.error == "main_city_not_found", invalid)
    assert(heroes[0].origin.x == -4000 and query_count == 0); no_return_effects()
end

reset()
cities[0].origin, cities[0].forward = Vector(3500, 600, 128), Vector(0, -1, 0)
assert(home.return_unit(heroes[0], 0).ok)
assert(heroes[0].origin.x == 3500 and heroes[0].origin.y == 344,
    "current own city position and facing are read for each return")

reset()
local wall = unit(-1, Vector(2256, 0, 128), 90)
wall.survival_wall_collision_barrier = true
obstacles[#obstacles + 1] = wall
assert(home.return_unit(heroes[0], 0).ok)
assert(distance(heroes[0].origin, wall.origin) >= wall.hull + heroes[0].hull,
    "destination does not overlap another building/barrier hull")
assert(distance(heroes[0].origin, cities[0].origin) <= 640)

reset()
heroes[0].origin = Vector(2256, 0, 128)
assert(home.return_unit(heroes[0], 0).ok)
assert(heroes[0].origin.x == 2256 and heroes[0].origin.y == 0,
    "hero does not displace itself by being counted as its own obstacle")

reset()
heroes[0].hull = 96
blocked = function(p) return math.abs(p.x - 2352) < 0.1 and math.abs(p.y) < 0.1 end
assert(home.return_unit(heroes[0], 0).ok)
assert(heroes[0].origin.x ~= 2256 or heroes[0].origin.y ~= 0,
    "actual large hero hull is sampled rather than only default 32-radius center")

reset()
height = function(p) return p.x > 2000 and 0 or 128 end
assert(home.return_unit(heroes[0], 0).ok)
assert(heroes[0].origin.x <= 2000 and heroes[0].origin.z == 128,
    "front water is rejected and a same-island point behind the city is used")
reset(); height = function() return 0 end
assert(not home.return_unit(heroes[0], 0).ok)
assert(heroes[0].origin.x == -4000); no_return_effects()

reset()
region_config.rows = {{ enabled = true, region_id = "own_safe_strip", region_type = "hero_movable",
    shape = "circle", center_x = 2320, center_y = 0, radius = 65 }}
regions.init()
assert(home.return_unit(heroes[0], 0).ok)
assert(heroes[0].origin.x == 2320 and heroes[0].origin.y == 0,
    "landing and full hero hull stay inside configured movement region")

reset(); blocked = function() return true end
assert(not home.return_unit(heroes[0], 0).ok)
assert(moves == 0 and query_count == 1); no_return_effects()

reset(); fail_move = true
local result = home.return_unit(heroes[0], 0)
assert(not result.ok and result.error == "final_destination_not_traversable")
assert(heroes[0].origin.x == -4000 and moves == 2, "invalid final relocation rolls back")
assert(notices[#notices].message:find("请稍后重试", 1, true)); no_return_effects()
print("HERO_RETURN_HOME_PASS: formal own hero/city, teammate isolation, collision/water/regions, actual hull, failure rollback, exit/camera only on success")
