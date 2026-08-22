package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

DOTA_UNIT_TARGET_TEAM_ENEMY = 1
DOTA_UNIT_TARGET_HERO = 2
DOTA_UNIT_TARGET_BASIC = 4
DOTA_UNIT_TARGET_FLAG_NONE = 0
FIND_ANY_ORDER = 0
DAMAGE_TYPE_MAGICAL = 2
PATTACH_WORLDORIGIN = 0

local event_bus = require("core/event_bus")
local events = require("core/events")
local combat_events = require("combat/combat_events")
local proc_service = require("systems/triggered_proc_service")
local effects = require("config/item_level_effects")

local hero_position = { x = 100, y = 200, z = 0 }
local target_position = { x = 900, y = 900, z = 0 }
local sound_events = {}
local hero = {}
function hero:IsNull() return false end
function hero:GetTeamNumber() return 2 end
function hero:GetAbsOrigin() return hero_position end
function hero:EmitSound(sound) sound_events[#sound_events + 1] = sound end

local function unit(team, position)
    local result = {}
    function result:IsNull() return false end
    function result:GetTeamNumber() return team end
    function result:GetAbsOrigin() return position or target_position end
    return result
end

local primary = unit(3, target_position)
local enemy_one = unit(3)
local enemy_two = unit(3)
local radius_calls = {}
FindUnitsInRadius = function(team, position, _, radius, target_team,
        target_type, flags, order, can_grow_cache)
    radius_calls[#radius_calls + 1] = {
        team = team,
        position = position,
        radius = radius,
        target_team = target_team,
        target_type = target_type,
        flags = flags,
        order = order,
        can_grow_cache = can_grow_cache,
    }
    return { enemy_one, enemy_two }
end

local particles = { created = 0, controlled = 0, released = 0 }
ParticleManager = {}
function ParticleManager:CreateParticle(name, attach, owner)
    particles.created = particles.created + 1
    particles.name = name
    particles.attach = attach
    particles.owner = owner
    return 77
end
function ParticleManager:SetParticleControl(index, control, position)
    particles.controlled = particles.controlled + 1
    particles.index = index
    particles.control = control
    particles.position = position
end
function ParticleManager:ReleaseParticleIndex(index)
    particles.released = particles.released + 1
    particles.release_index = index
end

local rolls = {}
RandomFloat = function()
    local value = table.remove(rolls, 1)
    assert(value ~= nil, "unexpected probability roll")
    return value
end

local snapshot = nil
local requests = {}
local proc_events = {}
local fail_second_target = false

local function setup(content_id)
    event_bus.reset()
    requests, proc_events, radius_calls, sound_events = {}, {}, {}, {}
    particles = { created = 0, controlled = 0, released = 0 }
    rolls = {}
    snapshot = content_id and {
        enabled = true,
        sources = {
            {
                source_id = content_id,
                effects = effects.by_content_id[content_id].effects,
            },
        },
    } or { enabled = true, sources = {} }
    event_bus.handle_request(events.EQUIPMENT_EFFECT_SNAPSHOT_GET_REQUEST,
        function() return { ok = true, snapshot = snapshot } end)
    event_bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function()
        return {
            ok = true,
            snapshot = { strength = 100, agility = 200, intellect = 300 },
        }
    end)
    event_bus.handle_request(combat_events.DEAL_REQUEST, function(request)
        requests[#requests + 1] = request
        if fail_second_target and request.victim == enemy_two then
            return { success = false, blocked_reason = "test_blocked" }
        end
        return { success = true }
    end)
    event_bus.subscribe(events.EQUIPMENT_PROC_TRIGGERED, function(payload)
        proc_events[#proc_events + 1] = payload
    end)
    proc_service.init()
end

local function attack(record, event_name, attack_id)
    event_bus.emit(event_name or events.HERO_MAIN_ATTACK_LANDED, {
        player_id = 0,
        attacker = hero,
        target = primary,
        record = record,
        attack_id = attack_id,
        is_main_attack = true,
    })
end

for stage = 0, 10 do
    local content_id = string.format("weapon_legend_abyss_%02d", stage)
    local definition = assert(effects.by_content_id[content_id],
        "missing legend effect snapshot " .. content_id)
    local proc = nil
    for _, effect in ipairs(definition.effects) do
        if effect.effect_type == "proc_attribute_damage" then proc = effect.value end
    end
    assert(proc, content_id .. " proc effect missing")
    assert(proc.probability == 10 and proc.range == 500
        and proc.multiplier == 50,
        content_id .. " proc configuration changed")
end

setup("weapon_legend_abyss_00")
rolls = { 9 }
attack(101, nil, "attack:101:first")
assert(#radius_calls == 1, "successful proc did not query one area")
assert(radius_calls[1].position == hero_position,
    "flame burst was not centered on the equipped hero")
assert(radius_calls[1].radius == 500, "flame burst radius changed")
assert(#requests == 2, "flame burst did not damage every nearby enemy")
for _, request in ipairs(requests) do
    assert(request.attacker == hero and request.source_kind == "splash",
        "flame burst damage request identity changed")
    assert(request.base_damage == 30000,
        "flame burst did not use logical all-attribute snapshot x50")
    assert(request.damage_type == DAMAGE_TYPE_MAGICAL
        and request.can_crit == false,
        "flame burst damage contract changed")
end
assert(particles.created == 1 and particles.controlled == 1
    and particles.released == 1,
    "flame burst visual did not play and release exactly once")
assert(particles.position == hero_position and particles.owner == hero,
    "flame burst visual was not attached to the hero center")
assert(#sound_events == 1 and sound_events[1] == "Hero_Warlock.RainOfChaos",
    "flame burst sound did not play exactly once")
assert(#proc_events == 1 and proc_events[1].damage == 30000
    and proc_events[1].target_count == 2
    and proc_events[1].success_count == 2
    and proc_events[1].failure_count == 0,
    "flame burst result event changed")

attack(101, nil, "attack:101:first")
assert(#requests == 2, "one attack record triggered flame burst twice")

rolls = { 0 }
attack(101, nil, "attack:101:reused")
assert(#requests == 4 and #proc_events == 2,
    "a later attack reusing an engine record was incorrectly suppressed")

rolls = { 0 }
attack(102, events.WEAPON_ATTACK_LANDED)
assert(#requests == 4, "legacy weapon event still triggers flame burst")
assert(#rolls == 1, "legacy weapon event consumed a probability roll")

rolls = {}
event_bus.emit(events.HERO_MAIN_ATTACK_LANDED, {
    player_id = 0,
    attacker = hero,
    target = primary,
    record = 102,
    attack_id = "attack:102:secondary",
    is_main_attack = false,
    is_multishot_secondary = true,
})
assert(#requests == 4 and #rolls == 0,
    "secondary attack triggered or rolled flame burst")

rolls = { 10 }
attack(103)
assert(#requests == 4 and #proc_events == 2,
    "failed 10 percent roll triggered flame burst")

setup(nil)
attack(201)
assert(#requests == 0 and #rolls == 0,
    "unequipped hero triggered or rolled flame burst")

setup("weapon_legend_abyss_10")
fail_second_target = true
rolls = { 0 }
attack(301)
fail_second_target = false
assert(#proc_events == 1 and proc_events[1].success_count == 1
    and proc_events[1].failure_count == 1,
    "damage transaction failures were not reported")

print("WEAPON_LEGEND_ABYSS_PROC_PASS")