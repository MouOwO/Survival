-- Run from the addon root with Lua 5.1. No engine, rewards, or network calls.
package.path = "scripts/vscripts/?.lua;" .. package.path

local rules = require("config/generated/archive_challenge_rules").by_id.default
assert(rules.building_anchor == "wave_portal", "production archive rules must select wave_portal")
assert(rules.building_offset_y == 360, "production portal offset must remain 360")
local bus = require("core/event_bus")
local events = require("core/events")
local report = print
local logs = {}
print = function(message) logs[#logs + 1] = tostring(message) end

local function vector(x, y, z) return {x = x, y = y, z = z or 0} end
Vector = vector
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH = 3
DOTA_UNIT_TARGET_HERO = 1
DOTA_UNIT_TARGET_BASIC = 2
DOTA_UNIT_TARGET_BUILDING = 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE = 8
FIND_ANY_ORDER = 0
GameRules = {GetGameTime = function() return 100 end}
CustomNetTables = nil

local fixture
local function entity(x, y, z, hull)
    local unit = {position = vector(x, y, z), hull = hull or 80}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:GetAbsOrigin() return vector(self.position.x, self.position.y, self.position.z) end
    function unit:GetHullRadius() return self.hull end
    return unit
end
local function ability()
    local result = {level = 0, activated = true}
    function result:IsNull() return false end
    function result:GetLevel() return self.level end
    function result:SetLevel(level) self.level = level end
    function result:IsActivated() return self.activated end
    function result:SetActivated(value) self.activated = value end
    return result
end
local function create_unit(name, position, find_clear_space, owner, unit_owner, team)
    assert(name:match("^npc_archive_challenge_[123]$"), "fixture may only create archive hubs")
    assert(find_clear_space == false, "immobile hubs must disable native clear-space search")
    assert(team == DOTA_TEAM_GOODGUYS and owner == nil and unit_owner == nil)
    local unit = entity(position.x, position.y, position.z)
    unit.name, unit.index, unit.abilities = name, #fixture.created + 1, {}
    function unit:entindex() return self.index end
    function unit:FindAbilityByName(key) return self.abilities[key] end
    function unit:AddAbility(key) self.abilities[key] = ability(); return self.abilities[key] end
    function unit:SetControllableByPlayer(id) self.owner = id end
    function unit:SetModel(path) self.model = path end
    function unit:SetOriginalModel(path) self.original_model = path end
    function unit:SetModelScale(scale) self.scale = scale end
    function unit:AddNewModifier(_, _, name) self[name] = true end
    fixture.created[#fixture.created + 1] = unit
    return unit
end
local function forbidden_external_call() error("reward/network/game-end path must not run in placement tests") end
package.loaded["systems/archive_service"] = {
    record_challenge = forbidden_external_call, has_pending = forbidden_external_call,
}
package.loaded["systems/archive_endless_service"] = {is_running = function() return false end}
package.loaded["systems/archive_endless_config"] = {group = function() return {} end}
package.loaded["systems/challenge_guardian_visual_service"] = {
    apply = function(unit) unit.visual_applied = true end,
}
package.loaded["systems/player_context_service"] = {
    slot = function(id)
        fixture.slot_lookups = fixture.slot_lookups + 1
        return {builder_spawn_marker = "player_" .. id .. "_builder_spawn"}
    end,
    register_unit = function(id, unit, role)
        assert(role == "archive_challenge")
        fixture.registered[#fixture.registered + 1] = {id = id, unit = unit}
    end,
}
package.loaded["systems/building_system"] = {
    wall_for_player = function(id)
        fixture.wall_lookups = fixture.wall_lookups + 1
        return fixture.old_markers["wall_" .. id]
    end,
}
package.loaded["systems/wave_system"] = {
    get_player_spawn_marker = function(id)
        fixture.wave_lookups = fixture.wave_lookups + 1
        return fixture.portals[id]
    end,
    spawn_challenge_monster = forbidden_external_call,
}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, key)
        assert(key == "archive_challenge_phase_timer" and delay == rules.phase_duration_seconds)
        fixture.timers[key] = {callback = callback, delay = delay}
    end,
    every = function(delay, callback, key)
        assert(key:match("^archive_hubs_retry:[0-3]$") and delay == 1)
        fixture.timers[key] = {callback = callback, delay = delay}
    end,
    cancel = function(key) fixture.timers[key] = nil end,
}

local function reset()
    fixture = {
        portals = {}, old_markers = {}, created = {}, registered = {}, timers = {}, units = {},
        blocked = function() return false end, trees = function() return false end,
        traversable = function() return true end, height = function() return 24 end,
        grid_queries = 0, wall_lookups = 0, slot_lookups = 0, marker_lookups = 0,
        wave_lookups = 0, nav_queries = 0, clear_space_calls = 0, fog_calls = 0,
    }
    for id = 0, 3 do
        -- Every old anchor exists at a raised, unrelated site; none may win.
        fixture.old_markers["wall_" .. id] = entity(9000 + id * 1000, 9000, 384)
        fixture.old_markers["player_" .. id .. "_builder_spawn"] = entity(9000 + id * 1000, 9500, 384)
        for index = 1, 3 do
            fixture.old_markers["player_" .. id .. "_archive_hub_" .. index] =
                entity(9000 + id * 1000, 10000 + index * 240, 408)
        end
    end
    Entities = {FindByName = function(_, _, name)
        fixture.marker_lookups = fixture.marker_lookups + 1
        return fixture.old_markers[name]
    end}
    GetGroundPosition = function(position)
        return vector(position.x, position.y, fixture.height(position))
    end
    GridNav = {
        IsTraversable = function(_, position)
            fixture.nav_queries = fixture.nav_queries + 1
            return fixture.traversable(position)
        end,
        IsBlocked = function(_, position) return fixture.blocked(position) end,
        IsNearbyTree = function(_, position, radius, full_collision)
            assert(radius >= 64 and full_collision == true)
            return fixture.trees(position)
        end,
    }
    FindUnitsInRadius = function(team, position, _, radius, target_team, target_type, flags)
        assert(team == DOTA_TEAM_GOODGUYS and target_team == DOTA_UNIT_TARGET_TEAM_BOTH)
        assert(target_type == DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING)
        assert(flags == DOTA_UNIT_TARGET_FLAG_INVULNERABLE)
        local result = {}
        for _, group in ipairs({fixture.units, fixture.created}) do
            for _, unit in ipairs(group) do
                local p = unit:GetAbsOrigin()
                if (p.x - position.x)^2 + (p.y - position.y)^2 <= radius^2 then
                    result[#result + 1] = unit
                end
            end
        end
        return result
    end
    CreateUnitByName = create_unit
    FindClearSpaceForUnit = function()
        fixture.clear_space_calls = fixture.clear_space_calls + 1
        error("engine clear-space movement is forbidden")
    end
    AddFOWViewer = function(team, position, radius, duration)
        assert(team == DOTA_TEAM_GOODGUYS and radius == 600 and duration == rules.phase_duration_seconds)
        assert(position.z == fixture.height(position))
        fixture.fog_calls = fixture.fog_calls + 1
    end
    bus.reset()
    bus.handle_request(events.GRID_CAN_PLACE_REQUEST, function()
        fixture.grid_queries = fixture.grid_queries + 1
        -- This represents the ordinary Z=384 lawn construction restriction.
        return {ok = false, error = "terrain_not_build_level"}
    end)
    package.loaded["systems/archive_hub_placement"] = nil
    package.loaded["systems/archive_challenge_service"] = nil
    return require("systems/archive_challenge_service")
end
local function begin(service, ids)
    local result = service.begin({difficulty_id = "N5", player_ids = ids})
    assert(result.ok and result.keep_running, "challenge phase must remain active")
end
local function retry_count()
    local count = 0
    for key in pairs(fixture.timers) do
        if key:match("^archive_hubs_retry:") then count = count + 1 end
    end
    return count
end
local function retry(id)
    local key = "archive_hubs_retry:" .. id
    local timer = assert(fixture.timers[key], "missing existing retry for player " .. id)
    local keep_running = timer.callback()
    if keep_running == false then fixture.timers[key] = nil end
    return keep_running
end
local function assert_cardinal(unit, portal, distances)
    local p, anchor = unit:GetAbsOrigin(), portal:GetAbsOrigin()
    local dx, dy = p.x - anchor.x, p.y - anchor.y
    assert((dx == 0) ~= (dy == 0), "each hub must lie on one cardinal side of its actual portal")
    assert(distances[math.abs(dx) + math.abs(dy)], "hub must remain in the bounded portal neighborhood")
    assert(p.z == 24, "hub must be grounded on the actual lower approach")
end
local function assert_complete(service, ids, distances)
    assert(#fixture.created == #ids * 3 and #fixture.registered == #ids * 3)
    assert(fixture.fog_calls == #ids * 3 and retry_count() == 0)
    for _, id in ipairs(ids) do
        local state = assert(service._test.players()[id])
        for index = 1, 3 do
            local unit = assert(state.hubs[index], "all three original hub types must exist")
            assert(unit.owner == id and unit.survival_archive_hub == index and unit.visual_applied)
            assert(unit.model == rules["building_model_" .. index] and unit.original_model == unit.model)
            assert(unit.scale == rules.building_model_scale and unit.modifier_invulnerable)
            assert(unit.modifier_building_no_health_bar)
            assert_cardinal(unit, fixture.portals[id], distances)
        end
    end
    for index, unit in ipairs(fixture.created) do
        for previous = 1, index - 1 do
            local a, b = unit.position, fixture.created[previous].position
            assert((a.x - b.x)^2 + (a.y - b.y)^2 >= (rules.building_spacing * .8)^2,
                "hubs owned by different players must not overlap")
        end
    end
    assert(fixture.wall_lookups == 0 and fixture.slot_lookups == 0 and fixture.marker_lookups == 0,
        "wall, builder, and obsolete dedicated markers must never be selected")
    assert(fixture.grid_queries == 0, "portal system spawns must bypass ordinary lawn construction policy")
    assert(fixture.clear_space_calls == 0)
end

-- Real rules and real creation service produce exactly three hubs per player.
local service = reset()
for id, xy in pairs({[0] = {3600, 0}, [1] = {0, -3600}, [2] = {-3600, 0}, [3] = {0, 3600}}) do
    fixture.portals[id] = entity(xy[1], xy[2], 48, 0)
end
begin(service, {0, 1, 2, 3})
assert_complete(service, {0, 1, 2, 3}, {[360] = true})
local wave_lookups, nav_queries, fog_calls = fixture.wave_lookups, fixture.nav_queries, fixture.fog_calls
begin(service, {0, 1, 2, 3})
assert(#fixture.created == 12 and fixture.wave_lookups == wave_lookups)
assert(fixture.nav_queries == nav_queries and fixture.fog_calls == fog_calls,
    "duplicate begin must reuse all ready hubs without repeating placement")

-- Occupied units, trees, and blocked/unwalkable terrain use another side.
for _, failure in ipairs({"occupied", "tree", "blocked", "unwalkable"}) do
    service = reset()
    fixture.portals[0] = entity(1000, 2000, 48, 0)
    local preferred_x, preferred_y = 1000, 2360
    if failure == "occupied" then
        fixture.units[1] = entity(preferred_x, preferred_y, 24, 80)
    elseif failure == "tree" then
        fixture.trees = function(p) return p.x == preferred_x and p.y == preferred_y end
    elseif failure == "blocked" then
        fixture.blocked = function(p) return math.abs(p.x - preferred_x) <= 64 and math.abs(p.y - preferred_y) <= 64 end
    else
        fixture.traversable = function(p) return not (math.abs(p.x - preferred_x) <= 64 and math.abs(p.y - preferred_y) <= 64) end
    end
    begin(service, {0})
    assert_complete(service, {0}, {[360] = true})
    for _, unit in ipairs(fixture.created) do
        assert(unit.position.x ~= preferred_x or unit.position.y ~= preferred_y,
            failure .. " preferred site must not receive a hub")
    end
end

-- No safe terrain: keep the original retry and stop after 12 candidates/player.
service = reset()
for id = 0, 3 do fixture.portals[id] = entity(id * 3000, 2000, 48, 0) end
fixture.traversable = function() return false end
begin(service, {0, 1, 2, 3})
assert(#fixture.created == 0 and retry_count() == 4)
assert(fixture.nav_queries == 48, "placement must stop after 12 failed candidates per player")
local before_retry = fixture.nav_queries
assert(retry(0) == true and #fixture.created == 0)
assert(fixture.nav_queries - before_retry == 12 and retry_count() == 4)
fixture.traversable = function() return true end
for id = 0, 3 do assert(retry(id) == false, "unblocked retry must complete") end
assert_complete(service, {0, 1, 2, 3}, {[360] = true})

-- Several owners may share the same runtime portal. All 12 hubs stay separate.
service = reset()
local shared = entity(-1024, 4096, 48, 0)
for id = 0, 3 do fixture.portals[id] = shared end
begin(service, {0, 1, 2, 3})
assert_complete(service, {0, 1, 2, 3}, {[360] = true, [600] = true, [840] = true})
begin(service, {0, 1, 2, 3})
assert(#fixture.created == 12 and retry_count() == 0)

-- A missing runtime portal waits even when all old anchor types are available.
service = reset()
begin(service, {2})
assert(#fixture.created == 0 and retry_count() == 1 and fixture.nav_queries == 0)
assert(fixture.wall_lookups == 0 and fixture.slot_lookups == 0 and fixture.marker_lookups == 0)
fixture.portals[2] = entity(3000, 4000, 48, 0)
assert(retry(2) == false)
assert_complete(service, {2}, {[360] = true})

print = report
print("ARCHIVE_PORTAL_HUBS_PASS: production rules, four owners/12 hubs, cardinal offsets, old-anchor rejection, lower ground, occupancy/trees/navigation, bounded retries, idempotency, shared portal, native clear-space disabled")
