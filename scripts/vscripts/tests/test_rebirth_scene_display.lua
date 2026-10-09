-- Run with Lua 5.1 from the addon root. Exercises production scene and combat
-- services together; model readiness, engine entities and visuals are stubbed.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local definitions = require("config/generated/monster_archetypes")
local encounters = require("config/generated/monster_encounters")
local points = require("config/generated/monster_spawn_points")
local now, serial, ready = 0, 0, false
local created, markers, units, callbacks = {}, {}, {}, {}
local spawned, completed, applied, cleared = 0, 0, 0, 0
local failure, outfit_failure, modifier_failure
local noop = function() end
local print_original = print
print = function(message, ...)
    assert(not tostring(message):find("handler error", 1, true), message)
    assert(not tostring(message):find("task failed", 1, true), message)
    print_original(message, ...)
end
GameRules = { GetGameTime = function() return now end }
Vector = function(x, y, z) return { x = x, y = y, z = z } end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_TEAM_NEUTRALS = 2, 3, 4
local function entity(name, origin, team)
    serial = serial + 1
    local unit = { id = serial, name = name, origin = origin, team = team, alive = true, modifiers = {} }
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.id end
    function unit:GetUnitName() return self.name end
    function unit:GetAbsOrigin() return self.origin end
    function unit:SetAbsOrigin(value) self.origin = value end
    function unit:GetForwardVector() return self.forward or Vector(0, -1, 0) end
    function unit:SetForwardVector(value) self.forward = value end
    function unit:GetPlayerOwnerID() return self.owner or -1 end
    function unit:HasModifier(name) return self.modifiers[name] == true end
    function unit:AddNewModifier(_, _, name)
        if modifier_failure and name == "modifier_rebirth_scene_display" then return nil end
        self.modifiers[name] = true
        return {}
    end
    function unit:RemoveModifierByName(name) self.modifiers[name] = nil end
    function unit:SetModel(value) self.model = value end
    function unit:SetOriginalModel(value) self.original = value end
    function unit:SetModelScale(value) self.scale = value end
    function unit:SetIdleAcquire(value) self.acquire = value end
    function unit:SetAcquisitionRange(value) self.acquisition = value end
    function unit:SetDayTimeVisionRange(value) self.day = value end
    function unit:SetNightTimeVisionRange(value) self.night = value end
    function unit:SetHullRadius(value) self.hull = value end
    function unit:SetDeathXP(value) self.xp = value end
    function unit:SetMinimumGoldBounty(value) self.gold_min = value end
    function unit:SetMaximumGoldBounty(value) self.gold_max = value end
    for _, method in ipairs({ "Stop", "SetBaseMaxHealth", "SetMaxHealth", "SetHealth",
        "SetBaseDamageMin", "SetBaseDamageMax", "SetPhysicalArmorBaseValue",
        "SetBaseAttackTime", "Script_SetAttackRange" }) do unit[method] = noop end
    units[unit.id] = unit
    return unit
end
for index = 1, 10 do
    local suffix = string.format("%02d", index)
    markers["rebirth_" .. suffix .. "_boss_spawn"] = entity("marker", Vector(index * 600, -index * 80, index * 14))
    markers["rebirth_" .. suffix .. "_entry"] = entity("marker", Vector(index * 600 - 100, -index * 80, index * 14))
end
Entities = { FindByName = function(_, _, name) return markers[name] end }
CreateUnitByName = function(name, origin, _, _, _, team)
    if failure then return nil end
    local unit = entity(name, origin, team)
    unit.modifiers.modifier_single_health_bar = true
    created[#created + 1] = unit
    return unit
end
UTIL_Remove = function(unit)
    unit.alive = false
    -- Removal can synchronously deliver a death event. Scene bodies must not
    -- enter the combat indexes or award challenge completion in that case.
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = unit })
    unit.removed = true
end
FindClearSpaceForUnit = function(unit, origin)
    assert(not unit.survival_rebirth_scene_display, "display must keep exact marker height")
    unit.origin = origin
end
GetGroundPosition = function(origin) return Vector(origin.x, origin.y, origin.z - 24) end
local hero = entity("hero", Vector(0, 0, 0), 2)
hero.owner = 0
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
    GetSelectedHeroEntity = function() return hero end,
}
package.loaded["systems/player_context_service"] = { is_defeated = function() return false end }
package.loaded["systems/startup_asset_preload_service"] = { snapshot = function() return { complete = ready } end }
package.loaded["systems/monster_hull_scale"] = { apply = noop }
package.loaded["systems/monster_navigation_policy"] = { apply = noop }
package.loaded["systems/challenge_session_service"] = { handles = function() return false end }
package.loaded["systems/monster_hero_visual_service"] = {
    apply = function(unit, archetype, options)
        assert(options.fresh_unit and options.allow_outside_formal_wave)
        assert(options.model_path == archetype.model_path)
        applied = applied + 1
        unit.outfit = archetype.default_wearable_asset_id
        if outfit_failure then return false, "test_outfit_failure" end
        return true
    end,
    clear = function(unit) cleared = cleared + 1; unit.outfit = nil end,
    on_death = noop,
}
local original_after = scheduler.after
scheduler.after = function(delay, callback, id)
    callbacks[#callbacks + 1] = { delay = delay, callback = callback, id = id }
    return original_after(delay, callback, id)
end
local scene = require("systems/rebirth_scene_display_service")
local combat = require("systems/monster_spawn_service")
bus.reset(); scheduler.clear(); combat.init()
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function() return { unit = hero } end)
bus.handle_request(events.WAVE_STATE_GET_REQUEST, function() return { ok = true, difficulty_id = "N1" } end)
bus.subscribe(events.MONSTER_SPAWNED, function() spawned = spawned + 1 end)
bus.subscribe(events.MONSTER_ENCOUNTER_COMPLETED, function() completed = completed + 1 end)
local function displays()
    local result = {}
    for _, unit in ipairs(created) do
        if unit.survival_rebirth_scene_display and not unit.removed then result[#result + 1] = unit end
    end
    return result
end
local function tick(value) now = value; scheduler.think() end
local function start(index, player)
    return bus.request(events.MONSTER_ENCOUNTER_START_REQUEST, {
        encounter_id = string.format("encounter_rebirth_%02d", index), player_id = player or 0,
    })
end
assert(not scene.start().ok and #created == 0, "display cannot precede asset readiness")
ready = true
assert(scene.start().displayed == 10 and #displays() == 10)
assert(scene.start().displayed == 10 and #created == 10, "repeated ready callbacks cannot duplicate bodies")
assert(spawned == 0 and completed == 0 and scheduler.task_count() == 0)
for _, unit in ipairs(displays()) do
    local index = tonumber(unit.name:match("(%d+)$"))
    local definition = definitions.by_id[string.format("rebirth_boss_%02d", index)]
    local encounter = encounters.by_id[string.format("encounter_rebirth_%02d", index)]
    local marker = markers[points.by_id[encounter.spawn_point_id].hammer_target_name]
    assert(unit.origin.x == marker.origin.x and unit.origin.y == marker.origin.y
        and unit.origin.z == marker.origin.z - 24 and unit.forward.y == -1)
    assert(unit.model == definition.model_path and unit.original == unit.model and unit.scale == definition.model_scale)
    assert(unit.outfit == definition.default_wearable_asset_id)
    assert(unit.team == 4 and unit.acquire == false and unit.acquisition == 0 and unit.day == 0 and unit.night == 0)
    assert(unit.hull == 0 and unit.xp == 0 and unit.gold_min == 0 and unit.gold_max == 0)
    assert(unit.survival_hide_custom_health_bar and unit.modifiers.modifier_rebirth_scene_display)
    assert(not unit.modifiers.modifier_single_health_bar, "spawned health-bar thinker must be removed immediately")
end

failure = true
assert(not start(1).ok and #displays() == 10, "combat creation failure must retain the display")
failure = nil
local first = assert(start(1))
assert(first.ok and #displays() == 9 and spawned == 1 and completed == 0)
assert(not start(1, 1).ok and #displays() == 9, "failed competing challenge must not restore active arena")
bus.emit(events.HERO_RETURNED_HOME, { player_id = 0, hero = hero })
assert(#displays() == 10 and completed == 0, "cancel returns the display without a kill reward")
assert(not start(1).ok, "existing two-second retry cooldown remains authoritative")
tick(2)
local second = assert(start(1)); assert(second.ok and #displays() == 9)
local victim = units[second.entindex]; victim.alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = victim, attacker = hero })
assert(completed == 1 and #displays() == 9, "wait for the original death presentation")
local death_callback = callbacks[#callbacks]
assert(death_callback.delay >= 1.45 and death_callback.delay < 2)
tick(3.4); assert(#displays() == 9)
tick(3.6); assert(#displays() == 10 and completed == 1)
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = victim, attacker = hero })
assert(completed == 1 and #displays() == 10, "duplicate death event stays idempotent")

local third = assert(start(2)); assert(third.ok)
units[third.entindex].alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = units[third.entindex], attacker = hero })
local stale_reentry = callbacks[#callbacks].callback
local fourth = assert(start(2)); assert(fourth.ok)
stale_reentry()
assert(#displays() == 9, "old corpse callback cannot draw over a new active challenge")
bus.emit(events.PLAYER_DISCONNECTED, { player_id = 0, defeat_cleanup = true })
assert(#displays() == 10 and completed == 2, "defeat cleanup restores only the scene")

local fifth = assert(start(3)); assert(fifth.ok)
units[fifth.entindex].alive = false
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = units[fifth.entindex], attacker = hero })
local stale_world = callbacks[#callbacks].callback
scene.reset()
assert(#displays() == 0 and scheduler.task_count() == 0)
assert(scene.start().displayed == 10)
local count = #created
stale_world()
assert(#displays() == 10 and #created == count, "old-world callback cannot recreate a display")

scene.reset()
local missing = markers.rebirth_10_boss_spawn
markers.rebirth_10_boss_spawn = nil
assert(not scene.start().ok and #displays() == 9, "missing marker never falls back to the origin")
markers.rebirth_10_boss_spawn = missing
assert(scene.start().displayed == 10 and #displays() == 10, "idempotent retry fills only missing displays")
scene.reset(); outfit_failure = true
assert(not scene.start().ok and #displays() == 0, "failed outfit attachment rolls back incomplete bodies")
outfit_failure = nil
assert(scene.start().displayed == 10)
scene.reset(); assert(#displays() == 0 and scheduler.task_count() == 0)
modifier_failure = true
assert(not scene.start().ok and #displays() == 0, "failed isolation must not leave a targetable combat-capable body")
modifier_failure = nil
assert(scene.start().displayed == 10)
scene.reset(); assert(#displays() == 0 and scheduler.task_count() == 0)
assert(applied > 10 and cleared > 10)
print("REBIRTH_SCENE_DISPLAY_PASS: 10 markers/outfits, ready gate, combat failure, cancel/retry, death/corpse delay, defeat, duplicate/stale callbacks, reset, missing marker/outfit rollback; no idle timer")
