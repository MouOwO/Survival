-- Run from the addon root: lua scripts/vscripts/tests/test_archive_challenge_hub_positions.lua
package.path = "scripts/vscripts/?.lua;" .. package.path

local markers, wave_markers, created, scheduled, registered, lookups
local wave_lookups, ground_calls, serial
local function vector(x, y, z) return { x = x, y = y, z = z } end
Vector = vector
DOTA_TEAM_GOODGUYS = 2
local function marker(x, y, z)
    return { IsNull = function() return false end, GetAbsOrigin = function() return vector(x, y, z) end }
end
local function ability()
    return { IsNull = function() return false end, SetLevel = function() end,
        SetActivated = function() end }
end
local function create_unit(name, position)
    serial = serial + 1
    local unit = { name = name, position = position, index = serial, abilities = {} }
    function unit:IsNull() return false end
    function unit:entindex() return self.index end
    function unit:FindAbilityByName(key) return self.abilities[key] end
    function unit:AddAbility(key) self.abilities[key] = ability(); return self.abilities[key] end
    function unit:SetControllableByPlayer(id) self.owner = id end
    function unit:SetModel() end
    function unit:SetOriginalModel() end
    function unit:SetModelScale() end
    function unit:AddNewModifier() end
    created[#created + 1] = unit
    return unit
end
package.loaded["core/event_bus"] = { emit = function() end }
package.loaded["core/events"] = { UI_NOTIFICATION = "notification" }
package.loaded["config/generated/archive_challenge_definitions"] = { rows = {}, by_id = {} }
package.loaded["config/generated/archive_challenge_stats"] = { by_id = {} }
package.loaded["config/generated/archive_challenge_rules"] = { by_id = { default = {
    building_unlock_difficulty = 5, building_spacing = 240, building_offset_y = 360,
    building_model = "hub.vmdl", building_model_scale = 1,
} } }
package.loaded["systems/player_context_service"] = {
    register_unit = function(id, unit, role)
        registered[#registered + 1] = { id = id, unit = unit, role = role }
    end,
}
package.loaded["systems/wave_system"] = {
    get_player_spawn_marker = function(id)
        wave_lookups = wave_lookups + 1
        return wave_markers[id]
    end,
}
package.loaded["systems/archive_service"] = {}
package.loaded["core/scheduler"] = {
    every = function(_, callback, key) scheduled[#scheduled + 1] = { callback = callback, key = key } end,
}
package.loaded["systems/archive_endless_service"] = { is_running = function() return false end }
package.loaded["systems/archive_endless_config"] = { group = function() return {} end }

local function reset()
    markers, wave_markers, created, scheduled, registered, lookups = {}, {}, {}, {}, {}, {}
    wave_lookups, ground_calls, serial = 0, 0, 0
    Entities = { FindByName = function(_, _, name)
        lookups[#lookups + 1] = name
        return markers[name]
    end }
    GetGroundPosition = function(position)
        ground_calls = ground_calls + 1
        return vector(position.x, position.y, 384)
    end
    CreateUnitByName = create_unit
    CustomNetTables = nil
    package.loaded["systems/archive_challenge_service"] = nil
    return require("systems/archive_challenge_service")
end
local function same(position, x, y, z)
    assert(position.x == x and position.y == y and position.z == z,
        string.format("expected (%s,%s,%s), got (%s,%s,%s)", x, y, z, position.x, position.y, position.z))
end
local function begin(service, ids)
    local result = service.begin({ difficulty_id = "N5", player_ids = ids })
    assert(result.ok and result.keep_running)
end

-- Dedicated markers work without any wave marker and cannot select another
-- player's buildings; positions are grounded before CreateUnitByName.
local service = reset()
for player = 0, 3 do
    for index = 1, 3 do
        markers["player_" .. player .. "_archive_hub_" .. index] = marker(player * 1000, index * 100, 420)
    end
end
begin(service, {0,1,2,3})
assert(#created == 12 and #scheduled == 0 and wave_lookups == 0 and ground_calls == 12)
for player = 0, 3 do
    for index = 1, 3 do
        local unit = service._test.players()[player].hubs[index]
        same(unit.position, player * 1000, index * 100, 384)
        assert(unit.owner == player and unit.survival_archive_hub == index)
        assert(registered[player * 3 + index].id == player)
        assert(registered[player * 3 + index].role == "archive_challenge")
    end
end
begin(service, {0,1,2,3})
assert(#created == 12 and #lookups == 12, "existing hubs must not respawn or repeat position lookups")

-- Partial/new marker sets use the original per-player wave offset only for
-- the missing slot, never another player's dedicated marker.
service = reset()
markers.player_0_archive_hub_2 = marker(100, 200, 900)
markers.player_1_archive_hub_1 = marker(-900, -800, 500)
wave_markers[0] = marker(1000, 2000, 128)
begin(service, {0})
same(created[1].position, 760, 2360, 128)
same(created[2].position, 100, 200, 384)
same(created[3].position, 1240, 2360, 128)
assert(wave_lookups == 2 and ground_calls == 1)

-- An old map or unavailable entity API preserves the original placement.
service = reset()
Entities = nil
wave_markers[2] = marker(-1000, -2000, 64)
begin(service, {2})
same(created[1].position, -1240, -1640, 64)
same(created[2].position, -1000, -1640, 64)
same(created[3].position, -760, -1640, 64)
assert(ground_calls == 0 and #scheduled == 0)

-- Removed/null markers behave like absent ones; no positioning exception.
service = reset()
markers.player_0_archive_hub_1 = { IsNull = function() return true end }
markers.player_0_archive_hub_2 = { IsNull = function() return false end, GetAbsOrigin = function() return nil end }
wave_markers[0] = marker(0, 0, 16)
begin(service, {0})
assert(#created == 3 and wave_lookups == 3 and #scheduled == 0)

-- A missing/failed ground API retains the dedicated marker origin instead
-- of falling back to the wave lane or passing nil to CreateUnitByName.
for _, outcome in ipairs({"nil", "error", "absent"}) do
    service = reset()
    for index = 1, 3 do markers["player_0_archive_hub_" .. index] = marker(index, 20, 400) end
    if outcome == "nil" then GetGroundPosition = function() return nil end
    elseif outcome == "error" then GetGroundPosition = function() error("engine unavailable") end
    else GetGroundPosition = nil end
    begin(service, {0})
    for index = 1, 3 do same(created[index].position, index, 20, 400) end
    assert(wave_lookups == 0 and #scheduled == 0)
end

-- Neither marker type ready: existing retry behavior waits without spawning
-- at an arbitrary coordinate; a later dedicated set completes the retry.
service = reset()
begin(service, {3})
assert(#created == 0 and #scheduled == 1)
assert(scheduled[1].key == "archive_hubs_retry:3")
for index = 1, 3 do markers["player_3_archive_hub_" .. index] = marker(300, index, 400) end
assert(scheduled[1].callback() == false)
assert(#created == 3)
print("PASS archive hubs: player isolation, marker priority, ground alignment, old-map fallback, missing-marker retry")
