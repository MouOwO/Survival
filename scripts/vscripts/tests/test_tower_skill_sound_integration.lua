package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local definitions = require("config/generated/tower_skill_sound_definitions")

local expected_families = {
    critical_strike = true,
    bone_cannon = true,
    death_grenade = true,
    laser = true,
    arcane_cannon = true,
    arcane_eye = true,
    lightning_strike = true,
    lightning_storm = true,
    lightning_diffusion = true,
    machine_gun = true,
    bounty_machine_gun = true,
    explosive_gatling = true,
    multi_attack = true,
    piercing_ballista = true,
    burning_great_arrow = true,
    frost_attack = true,
    ice_blizzard = true,
    polar_obelisk = true,
    magic_finger = true,
    magic_laguna = true,
    arcane_supremacy = true,
}

assert(#definitions.rows == 22,
    "tower sound config must cover 21 skill families and the basic attack")
local enabled_count = 0
for _, row in ipairs(definitions.rows) do
    if row.skill_family == "basic_attack" then
        assert(row.cue_id == "tower_basic_attack"
                and row.phase == "launch"
                and row.sound_event == "Creep_Good_Range.Attack",
            "tower basic attack resolved the wrong launch cue")
    else
        assert(expected_families[row.skill_family],
            "unexpected tower sound family: " .. tostring(row.skill_family))
        expected_families[row.skill_family] = nil
    end
    if row.enabled ~= false then enabled_count = enabled_count + 1 end
end
assert(next(expected_families) == nil, "tower sound config missed a skill family")
assert(enabled_count == 21, "exactly one tower sound row must be disabled")
assert(definitions.by_id.tower_machine_gun.enabled == false,
    "pure numeric machine-gun passive must remain explicitly silent")

local now = 0
local played = {}
GameRules = { GetGameTime = function() return now end }
EmitSoundOnLocationWithCaster = function(position, event, source)
    played[#played + 1] = { event = event, position = position, source = source }
end

local unit = {
    IsNull = function() return false end,
    entindex = function() return 810 end,
    EmitSound = function(_, event)
        played[#played + 1] = { event = event, unit = unit, source = unit }
    end,
}
local position = { x = 40, y = 50, z = 60 }

package.loaded["core/sound_service"] = nil
local sounds = require("core/sound_service")
sounds.init()
for _, row in ipairs(definitions.rows) do
    if row.enabled ~= false then
        now = now + 2
        local before = #played
        assert(sounds.play(row.cue_id, {
            source = unit,
            unit = unit,
            position = position,
        }) == true, "enabled tower cue did not play: " .. row.cue_id)
        assert(#played == before + 1 and played[#played].event == row.sound_event,
            "tower cue resolved the wrong native event: " .. row.cue_id)
    end
end
assert(sounds.play("tower_machine_gun", {
    source = unit, unit = unit, position = position,
}) == false, "disabled machine-gun policy played a sound")

local function read(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local content = handle:read("*a")
    handle:close()
    return content
end

local runtime_sources = table.concat({
    read("scripts/vscripts/modifiers/modifier_tower_attack_effects.lua"),
    read("scripts/vscripts/systems/tower_special_skill_system.lua"),
    read("scripts/vscripts/systems/tower_magic_supreme_system.lua"),
}, "\n")
for _, row in ipairs(definitions.rows) do
    if row.enabled ~= false then
        assert(string.find(runtime_sources, '"' .. row.cue_id .. '"', 1, true),
            "tower cue is not wired into a runtime trigger: " .. row.cue_id)
    end
end

local magic_source = read(
    "scripts/vscripts/systems/tower_magic_supreme_system.lua"
)
assert(not string.find(magic_source, "EmitSoundOn", 1, true),
    "magic tower retained a direct sound engine call")
assert(not string.find(magic_source, 'PrecacheResource("soundfile"', 1, true),
    "magic tower retained independent sound precaching")

-- Drive the magic route through its real authoritative attack subscriber.
-- Particle and cue feedback must only follow accepted damage requests.
local attack_handler = nil
local damage_result = { success = true }
local damage_requests = {}
local runtime_cues = {}
package.loaded["core/event_bus"] = {
    subscribe = function(_, handler) attack_handler = handler end,
    request = function(_, payload)
        damage_requests[#damage_requests + 1] = payload
        return damage_result
    end,
}
package.loaded["core/sound_service"] = {
    play = function(cue_id, options)
        runtime_cues[#runtime_cues + 1] = {
            cue_id = cue_id,
            source = options.source,
            position = options.position,
        }
        return true
    end,
}

DAMAGE_TYPE_MAGICAL = 2
PATTACH_CUSTOMORIGIN = 3
PATTACH_POINT_FOLLOW = 4
RollPercentage = function() return true end
ParticleManager = {
    CreateParticle = function() return 1 end,
    SetParticleControlEnt = function() end,
    ReleaseParticleIndex = function() end,
    DestroyParticle = function() end,
}

local ability = {
    IsNull = function() return false end,
    GetLevel = function() return 1 end,
}
local tower = {
    IsNull = function() return false end,
    IsAlive = function() return true end,
    GetTeamNumber = function() return 2 end,
    GetAverageTrueAttackDamage = function() return 100 end,
    GetAbsOrigin = function() return { x = 0, y = 0, z = 0 } end,
    FindAbilityByName = function() return ability end,
}
local target_position = { x = 100, y = 200, z = 10 }
local target = {
    IsNull = function() return false end,
    GetTeamNumber = function() return 3 end,
    GetAbsOrigin = function() return target_position end,
}
local magic_skills = {
    { skill_id = "magic_finger_lv01", trigger_chance_pct = 100,
        damage_multiplier = 0.9 },
    { skill_id = "magic_laguna_lv01", trigger_chance_pct = 100,
        damage_multiplier = 1 },
    { skill_id = "arcane_supremacy_lv01", damage_multiplier = 4 },
}

package.loaded["systems/tower_magic_supreme_system"] = nil
local magic_system = require("systems/tower_magic_supreme_system")
magic_system.init()
assert(attack_handler, "magic tower did not subscribe to authoritative attacks")
attack_handler({ tower = tower, target = target, skills = magic_skills })
assert(#damage_requests == 3 and #runtime_cues == 3,
    "accepted magic damage did not produce exactly three family cues")
local expected_magic_cues = {
    tower_magic_finger = true,
    tower_magic_laguna = true,
    tower_arcane_supremacy = true,
}
for _, call in ipairs(runtime_cues) do
    assert(expected_magic_cues[call.cue_id],
        "magic route played an unexpected cue: " .. tostring(call.cue_id))
    expected_magic_cues[call.cue_id] = nil
    assert(call.source == tower and call.position == target_position,
        "magic cue lost its tower source or target position")
end
assert(next(expected_magic_cues) == nil, "magic route missed a family cue")

damage_result = { success = false, blocked_reason = "test_rejected" }
local cue_count = #runtime_cues
attack_handler({ tower = tower, target = target, skills = magic_skills })
assert(#damage_requests == 6 and #runtime_cues == cue_count,
    "rejected magic damage incorrectly produced particle/audio feedback")

print("TOWER_SKILL_SOUND_INTEGRATION_PASS")
