-- Offline checks: debug commands follow this player's repaired map markers.
package.path = "scripts/vscripts/?.lua;" .. package.path
local wave_markers, map_markers, lookups, created, cleared, diagnostics
local can_walk, is_blocked, ground_height, dev_mode
local vector = {}
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector) end
DOTA_TEAM_BADGUYS, DOTA_UNIT_CAP_MOVE_NONE, DOTA_UNIT_CAP_NO_ATTACK = 3, 0, 0

for _, module in ipairs({
    "debug/weapon_cheat_handlers", "debug/attack_speed_cheat",
    "debug/research_technology_test", "debug/dev_asset_preload", "debug/health_cheat",
    "systems/building_system", "systems/rogue_reward_service", "systems/fishing_service",
    "systems/player_gameplay_stats_order_service", "core/scheduler",
    "config/generated/hero_skill_definitions", "config/generated/hero_skill_pool_members",
}) do package.loaded[module] = {} end
package.loaded["core/logger"] = {info = function() end, warn = function() end}
package.loaded["systems/monster_corpse_lifecycle_service"] = {track = function() end}
package.loaded["systems/wave_system"] = {
    get_player_spawn_marker = function(id) return wave_markers[id] end,
    is_dev_mode = function() return dev_mode end,
}
package.loaded["systems/player_context_service"] = {
    slot = function(id)
        if id >= 0 and id <= 3 then return {wave_spawn_marker = "monsterborn_player" .. (id + 1)} end
    end,
}
package.loaded["debug/armor_engine_diagnostic"] = {
    run = function(options)
        diagnostics[#diagnostics + 1] = options
        return true, {armor_count = 9, case_count = 27}
    end,
}
local commands = require("debug/cheat_command_service")._test
local function marker(x, y, z)
    return {IsNull = function() return false end, GetAbsOrigin = function() return Vector(x, y, z) end}
end
local function reset()
    wave_markers, map_markers, lookups, created, cleared, diagnostics = {}, {}, {}, {}, {}, {}
    can_walk, is_blocked, ground_height, dev_mode = true, false, function() return 384 end, true
    Entities = {FindByName = function(_, _, name)
        lookups[#lookups + 1] = name
        return map_markers[name]
    end}
    GetGroundPosition = function(position)
        return Vector(position.x, position.y, ground_height(position))
    end
    GridNav = {
        IsTraversable = function(_, position)
            if can_walk == "error" then error("navigation unavailable") end
            if type(can_walk) == "function" then return can_walk(position) end
            return can_walk
        end,
        IsBlocked = function() return is_blocked end,
    }
    CreateUnitByName = function(_, position)
        assert(position)
        created[#created + 1] = position
        local unit = {IsNull = function() return false end, entindex = function() return #created end,
            GetAbsOrigin = function() return position end}
        setmetatable(unit, {__index = function(_, key)
            if key:match("^Set") then return function() end end
        end})
        return unit
    end
    FindClearSpaceForUnit = function(_, position) cleared[#cleared + 1] = position end
end
local function add(id)
    return commands.add_monster({player_id = id, args = {"1000", "10", "0", "0"}})
end
local function armor(id)
    return commands.run_armor_engine_diagnostic({player_id = id, args = {}})
end

-- Live wave channel wins, even if an obsolete named marker also exists.
reset(); wave_markers[2] = marker(5000, 4000, 1000)
map_markers.monsterborn_player3 = marker(-9999, -9999, 0)
assert(add(2))
assert(#lookups == 0 and #created == 1 and #cleared == 1)
assert(created[1].x == 5000 and created[1].y == 4000 and created[1].z == 384)

-- Before waves initialize, each player resolves only their own map marker.
reset()
for id = 0, 3 do
    map_markers["monsterborn_player" .. (id + 1)] = marker(id * 2000, 1000, 420)
    assert(add(id))
    assert(created[id + 1].x == id * 2000 and created[id + 1].y == 1000 and created[id + 1].z == 384)
    assert(lookups[id + 1] == "monsterborn_player" .. (id + 1))
end

-- Missing/null marker never falls back to another player or old hardcoded XY.
reset(); map_markers.monsterborn_player1 = marker(100, 200, 400)
local ok, reason = add(1)
assert(not ok and reason:find("未找到本玩家", 1, true) and #created == 0)
wave_markers[1] = {IsNull = function() return true end}
ok, reason = armor(1)
assert(not ok and reason:find("未找到本玩家", 1, true) and #diagnostics == 0)

for _, rejected in ipairs({"blocked", "water", "navigation_error", "ground_error", "ground_absent"}) do
    reset(); wave_markers[0] = marker(2000, 3000, 400)
    if rejected == "blocked" then is_blocked = true
    elseif rejected == "water" then can_walk = false
    elseif rejected == "navigation_error" then can_walk = "error"
    elseif rejected == "ground_error" then GetGroundPosition = function() error("ground unavailable") end
    else GetGroundPosition = nil end
    ok, reason = add(0)
    assert(not ok and type(reason) == "string" and #created == 0 and #cleared == 0, rejected)
end

-- Both commands share the grounded player center; armor checks its full footprint.
reset(); wave_markers[3] = marker(6000, 7000, 1024)
assert(armor(3))
assert(#diagnostics == 1 and diagnostics[1].player_id == 3)
assert(diagnostics[1].origin.x == 6000 and diagnostics[1].origin.y == 7000 and diagnostics[1].origin.z == 384)
reset(); wave_markers[0] = marker(1000, 1000, 400)
can_walk = function(position) return position.x < 1300 end
ok, reason = armor(0)
assert(not ok and reason:find("空地不足", 1, true) and #diagnostics == 0 and #created == 0)
reset(); wave_markers[0] = marker(1000, 1000, 400)
ground_height = function(position) return position.x < 1000 and 0 or 384 end
ok, reason = armor(0)
assert(not ok and reason:find("空地不足", 1, true) and #diagnostics == 0)
reset(); dev_mode = false
ok, reason = armor(0)
assert(not ok and reason == "dev_mode_required: run dev first" and #lookups == 0)

print("PASS debug spawn positions: own-player markers, pre-wave lookup, ground alignment, missing/blocked safety, diagnostic footprint")
