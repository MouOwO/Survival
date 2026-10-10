-- Capture the real exclusive services' lifecycle events while their existing
-- attack-rate integration fixtures exercise creation, death, respawn and delete.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local original_emit, original_print = bus.emit, print
assert(events.HERO_CLONE_CREATED == "hero.clone.created")
assert(events.HERO_CLONE_REMOVED == "hero.clone.removed")

local cases = {
    { path = "tools/test_monkey_clone_attack_rate.lua", flag = "survival_monkey_king_clone",
        ability = "ability_survival_monkey_king_exclusive", label = "monkey" },
    { path = "tools/test_blademaster_attack_rate.lua", flag = "survival_blademaster_clone",
        ability = "ability_survival_blademaster_exclusive", label = "blademaster" },
}

for _, case in ipairs(cases) do
    -- Each fixture normally runs in a fresh Lua process. Preserve the observed
    -- event-bus object while clearing production module caches between cases.
    bus.reset()
    local modules = {}
    for name in pairs(package.loaded) do
        if name:find("/", 1, true) and name ~= "core/event_bus" and name ~= "core/events" then
            modules[#modules + 1] = name
        end
    end
    for _, name in ipairs(modules) do package.loaded[name] = nil end

    local created, active, errors = {}, {}, {}
    local creations, removals = 0, 0
    local creates_by_player = {}
    print = function(message)
        if tostring(message):find("handler error", 1, true) then errors[#errors + 1] = message end
    end
    bus.emit = function(name, payload)
        if name == events.HERO_CLONE_CREATED then
            local unit = assert(payload and payload.unit, "creation must expose the actual clone handle")
            assert(unit[case.flag] == true and unit:IsAlive(), "only a live combat clone publishes creation")
            assert(payload.player_id == unit:GetPlayerOwnerID() and payload.team == unit:GetTeamNumber(),
                "creation must publish its own player and team")
            local q = assert(unit:FindAbilityByName(case.ability), "Q must be installed before creation publishes")
            assert(not created[unit], "stable stat synchronization must not repeat creation")
            created[unit] = { entindex = unit:entindex(), player_id = payload.player_id, ability = q }
            active[unit] = true
            creations = creations + 1
            creates_by_player[payload.player_id] = (creates_by_player[payload.player_id] or 0) + 1
        elseif name == events.HERO_CLONE_REMOVED then
            local known = assert(created[payload and payload.unit], "removal must identify a previously created clone")
            assert(payload.entindex == known.entindex and payload.player_id == known.player_id,
                "death and deletion must retain the old clone identity for runtime cleanup")
            active[payload.unit] = nil
            removals = removals + 1
        end
        return original_emit(name, payload)
    end

    local ok, failure = pcall(dofile, case.path)
    bus.emit, print = original_emit, original_print
    assert(ok, case.label .. " integration fixture failed: " .. tostring(failure))
    assert(#errors == 0, table.concat(errors, "\n"))
    assert(creations >= 4 and removals >= 2,
        case.label .. ": actual spawn, respawn and deletion must publish lifecycle events")
    assert((creates_by_player[0] or 0) >= 3 and creates_by_player[1] == 1,
        case.label .. ": player-zero replacement must preserve the second player's original clone")

    local active_by_player = {}
    for unit, known in pairs(created) do
        if active[unit] then
            assert(unit:IsAlive() and unit:FindAbilityByName(case.ability) == known.ability,
                "an active projection must belong to the living current clone and Q handle")
            active_by_player[known.player_id] = (active_by_player[known.player_id] or 0) + 1
        else
            assert(not unit:IsAlive(), "removed projection must correspond to a dead or deleted clone")
        end
    end
    assert(active_by_player[0] == 1 and active_by_player[1] == 1,
        case.label .. ": all old clone projections must be cleared after replacement")
    original_print("CLONE_ABILITY_LIFECYCLE_CASE_PASS " .. case.label
        .. " created=" .. creations .. " removed=" .. removals .. " active_players=2")
end

original_print("CLONE_ABILITY_LIFECYCLE_PASS: actual service creation, Q installation, death, respawn, owner deletion and isolated replacement")
