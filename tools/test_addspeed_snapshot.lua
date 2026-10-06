package.path = "scripts/vscripts/?.lua;" .. package.path

-- Keep the event bus, combat-stat calculation and cheat real. Only native
-- entities and unrelated equipment/bootstrap services are replaced.
for _, name in ipairs({
    "systems/effect_handler_registry", "systems/equipment_effect_service",
    "systems/equipment_stat_aggregation_service", "systems/triggered_proc_service",
}) do package.loaded[name] = { init = function() end } end
package.loaded["systems/technology_stat_manager"] = {
    get = function() return { final = { hero = {} } } end,
}
package.loaded["config/generated/hero_definitions"] = { by_id = { test_hero = {
    hero_id = "test_hero", unit_name = "npc_test_hero", attack_speed = 1.4,
    base_damage_min = 112, base_damage_max = 120, base_health = 99000,
    base_strength = 19000, base_agility = 19000, base_intellect = 19000,
} } }
package.loaded["config/global_rules"] = {
    number = function(_, fallback) return fallback end,
    hero_strength_health_per_point = 0, hero_intellect_attack_per_point = 0,
}
package.loaded["systems/hero_stat_adapter"] = {
    configured_max_health = function(definition) return definition.base_health end,
    apply_configured_health = function(unit) return unit.maximum, 0, unit.maximum end,
    reapply_projectile_stats = function() end,
}

local bus = require("core/event_bus")
local events = require("core/events")
local active_units, publications = {}, {}
local function get_stats(player_id)
    local result, problem = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST,
        { player_id = player_id or 0 })
    assert(result and result.ok, tostring(problem))
    return result.snapshot
end
local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 1e-8,
        (message or "number mismatch") .. ": " .. tostring(actual) .. " ~= " .. expected)
end

local function unit(id)
    local result = { id = id, maximum = 99000, health = 50000, modifiers = {} }
    function result:IsNull() return false end
    function result:IsAlive() return true end
    function result:entindex() return self.id end
    function result:GetLevel() return 1 end
    function result:GetHealth() return self.health end
    function result:SetHealth(value) self.health = value end
    function result:GetMaxHealth() return self.maximum end
    function result:GetBaseAttackTime() return 1 / 1.4 end
    function result:GetBaseDamageMin() return 112 end
    function result:GetBaseDamageMax() return 120 end
    function result:FindModifierByName(name) return self.modifiers[name] end
    function result:RemoveModifierByName(name) self.modifiers[name] = nil end
    function result:AddNewModifier(_, _, name, params)
        local modifier = { interval = params.attack_interval }
        function modifier:GetModifierFixedAttackRate() return self.interval end
        self.modifiers[name] = modifier
        return modifier
    end
    return result
end

package.loaded["core/modifier_registry"] = { ensure = function(_, name)
    if name == "modifier_weapon_stat_projection" then
        -- ForceRefresh queries the service recursively. Runtime speed markers
        -- must already be committed before this callback to avoid recursion.
        return { ForceRefresh = function() get_stats(0) end }
    end
    return {}
end }

local service = require("systems/hero_combat_stat_service")
local cheat = require("debug/attack_speed_cheat")
local function init(cheat_first)
    bus.reset()
    publications = {}
    active_units = {}
    if cheat_first then cheat.init() end
    service.init()
    if not cheat_first then cheat.init() end
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(payload)
        return { ok = active_units[payload.player_id] ~= nil,
            unit = active_units[payload.player_id] }
    end)
    bus.subscribe(events.HERO_COMBAT_STATS_CHANGED, function(payload)
        publications[#publications + 1] = payload.snapshot
    end)
end
local function summon(id, player_id)
    local hero = unit(id)
    active_units[player_id or 0] = hero
    bus.emit(events.HERO_SUMMONED, {
        player_id = player_id or 0, hero_id = "test_hero", unit = hero,
    })
    return hero
end

for _, cheat_first in ipairs({ false, true }) do
    init(cheat_first)
    local hero = summon(101)
    local before = get_stats()
    near(before.attack_speed, 1.4)
    local count = #publications
    assert(cheat.execute({ player_id = 0 }))
    assert(#publications == count + 1,
        "addspeed must immediately publish a new snapshot for the HUD")
    near(publications[#publications].attack_speed, 10)
    local after = get_stats()
    near(after.attack_speed, 10)
    assert(after.entindex == hero:entindex())
    near(after.attack_min, before.attack_min)
    near(after.max_health, before.max_health)
    near(hero.health, 50000, "changing speed must not heal the hero")
    count = #publications
    for i = 1, 20 do near(get_stats().attack_speed, 10) end
    assert(#publications == count, "identical reads must not republish or recalculate")

    assert(cheat.set_rate(0, 5))
    near(publications[#publications].attack_speed, 5)
    near(get_stats().attack_speed, 5)
    hero:FindModifierByName("modifier_debug_fixed_attack_rate").interval = 0.25
    near(get_stats().attack_speed, 4, "direct refresh must be detected")
    hero:RemoveModifierByName("modifier_debug_fixed_attack_rate")
    near(get_stats().attack_speed, 1.4, "removing the modifier restores configured speed")
    near(publications[#publications].attack_speed, 1.4)

    local replacement = summon(102)
    local replaced = get_stats()
    assert(replaced.entindex == replacement:entindex())
    near(replaced.attack_speed, 5, "saved cheat rate applies to the new source hero")
    local latest_count = #publications
    local stale_request = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {
        player_id = 0, entindex = hero:entindex(),
    })
    assert(stale_request and not stale_request.ok
        and stale_request.error == "hero_entity_mismatch",
        "an old entity must not trigger a refresh on the new hero")
    hero.modifiers.modifier_debug_fixed_attack_rate = { GetModifierFixedAttackRate = function() return 0.01 end }
    near(get_stats().attack_speed, 5, "old hero changes must not affect the replacement")
    assert(#publications == latest_count)

    assert(not cheat.set_rate(0, 0 / 0), "NaN must not reach engine attack intervals")
    near(get_stats().attack_speed, 5)
    local modifier = replacement:FindModifierByName("modifier_debug_fixed_attack_rate")
    for _, invalid in ipairs({ 0, -1, math.huge, -math.huge, 0 / 0 }) do
        modifier.interval = invalid
        near(get_stats().attack_speed, 1.4, "invalid runtime interval must use configured speed")
    end
end

-- An enabled cheat can precede the first hero summon. Both event subscription
-- orders must end with the fixed interval reflected in the first usable HUD.
for _, cheat_first in ipairs({ false, true }) do
    init(cheat_first)
    assert(cheat.execute({ player_id = 0 }))
    summon(201)
    near(get_stats().attack_speed, 10)
    near(publications[#publications].attack_speed, 10)
end
print("ADDSPEED_SNAPSHOT_PASS immediate publication, rate updates/removal, replacement, callback order, health and stable reads")

init(false)
local deleted = summon(301)
active_units[0] = nil
bus.emit(events.HERO_REMOVED, {player_id = 0, unit = deleted, entindex = 301})
local missing = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, {player_id = 0})
assert(missing and not missing.ok and publications[#publications].entindex == -1,
    "hero deletion must clear combat requests and publish an empty HUD identity")
local replacement = summon(302)
bus.emit(events.HERO_REMOVED, {player_id = 0, unit = deleted, entindex = 301})
assert(get_stats().entindex == replacement:entindex(), "stale removal must preserve the replacement's combat stats")
print("HERO_COMBAT_REMOVAL_PASS empty authoritative snapshot, resummon, stale identity protection")
