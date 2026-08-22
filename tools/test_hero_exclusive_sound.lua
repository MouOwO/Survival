package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"
    .. package.path

local vector_mt = {
    __add = function(left, right)
        return Vector(left.x + right.x, left.y + right.y, left.z + right.z)
    end,
    __mul = function(left, right)
        if type(left) == "number" then left, right = right, left end
        return Vector(left.x * right, left.y * right, left.z * right)
    end,
}
Vector = function(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vector_mt)
end

PATTACH_WORLDORIGIN = 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_TARGET_HERO = 4
DOTA_UNIT_TARGET_BASIC = 8
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 16
FIND_CLOSEST = 32

local now = 0
GameRules = { GetGameTime = function() return now end }

local scheduled = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, task_id)
        scheduled[task_id] = { delay = delay, callback = callback }
        return task_id
    end,
}

local sound_calls = {}
package.loaded["core/sound_service"] = {
    play = function(cue_id, options)
        sound_calls[#sound_calls + 1] = {
            cue_id = cue_id,
            options = options,
        }
        return false
    end,
}

local particles = {}
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        particles[#particles + 1] = {
            path = path,
            attach = attach,
            owner = owner,
            controls = {},
        }
        return #particles
    end,
    SetParticleControl = function(_, id, control_point, value)
        particles[id].controls[control_point] = value
    end,
    ReleaseParticleIndex = function() end,
}

local function make_target(index, position)
    return {
        IsNull = function() return false end,
        IsAlive = function() return true end,
        entindex = function() return index end,
        GetAbsOrigin = function() return position end,
    }
end

local attacker = {
    IsNull = function() return false end,
    IsAlive = function() return true end,
    entindex = function() return 100 end,
    GetAbsOrigin = function() return Vector(10, 20, 30) end,
    GetForwardVector = function() return Vector(1, 0, 0) end,
    GetTeamNumber = function() return 2 end,
}

local created_units = {}
local fail_create = false
local function make_summon(index, position)
    local alive = true
    local unit = {
        IsNull = function() return false end,
        IsAlive = function() return alive end,
        entindex = function() return index end,
        GetAbsOrigin = function() return position end,
        GetTeamNumber = function() return 2 end,
        SetOwner = function() end,
        SetPlayerID = function() end,
        SetControllableByPlayer = function() end,
        SetBaseDamageMin = function() end,
        SetBaseDamageMax = function() end,
        SetBaseAttackTime = function() end,
        SetPhysicalArmorBaseValue = function() end,
        SetBaseMaxHealth = function() end,
        SetMaxHealth = function() end,
        SetHealth = function() end,
        AddNewModifier = function() end,
        ForceKill = function() alive = false end,
    }
    return unit
end

CreateUnitByName = function(_, position)
    if fail_create then return nil end
    local unit = make_summon(200 + #created_units, position)
    created_units[#created_units + 1] = unit
    return unit
end

local primary = make_target(301, Vector(100, 200, 0))
local secondary_a = make_target(302, Vector(120, 200, 0))
local secondary_b = make_target(303, Vector(140, 200, 0))
local radius_targets = { primary, secondary_a, secondary_b }
FindUnitsInRadius = function() return radius_targets end

package.loaded["systems/hero_exclusive_passive_service"] = nil
local service = require("systems/hero_exclusive_passive_service")
local deals = {}
service.init({
    deal_group = function(context, targets, multiplier)
        deals[#deals + 1] = {
            context = context,
            targets = targets,
            multiplier = multiplier,
        }
    end,
})

local base_context = {
    player_id = 0,
    attacker = attacker,
    target = primary,
    level = 1,
    attributes = {
        attack = 100,
        attack_speed = 2,
        max_health = 1000,
        runtime_armor = 20,
    },
}
local summon_definition = {
    duration = { 10 },
    attack_inherit_pct = { 100 },
    attack_speed_inherit_pct = { 100 },
    health_inherit_pct = { 100 },
    armor_inherit_pct = { 100 },
}

fail_create = true
base_context.skill_id = "skill_doom_infernal"
assert(service.runners.skill_doom_infernal(base_context, summon_definition) == false,
    "Failed infernal creation unexpectedly succeeded")
assert(#sound_calls == 0,
    "Failed infernal creation played a spawn sound")

fail_create = false
assert(service.runners.skill_doom_infernal(base_context, summon_definition) == true,
    "Infernal creation did not succeed")
assert(#sound_calls == 1
        and sound_calls[1].cue_id == "hero_doom_infernal_spawn"
        and sound_calls[1].options.unit == created_units[1]
        and sound_calls[1].options.source == attacker,
    "Successful infernal creation used the wrong sound lifecycle")
assert(service.runners.skill_doom_infernal(base_context, summon_definition) == false,
    "Active infernal lock allowed a duplicate summon")
assert(#sound_calls == 1,
    "Locked infernal summon replayed its spawn sound")

local raze_context = {
    player_id = 0,
    attacker = attacker,
    target = primary,
    skill_id = "skill_shadow_fiend_raze",
    level = 1,
    attributes = {},
}
assert(service.runners.skill_shadow_fiend_raze(raze_context, {
    radius = { 250 },
    stack_duration = { 3 },
    max_stacks = { 5 },
    damage_multiplier = { 25 },
    damage_per_stack_pct = { 10 },
}) == true, "Shadowraze runner failed")
assert(#sound_calls == 2
        and sound_calls[2].cue_id == "hero_shadow_raze_impact"
        and sound_calls[2].options.position == primary:GetAbsOrigin(),
    "Shadowraze did not play exactly one position sound")
assert(#deals == 1 and #deals[1].targets == 3,
    "Shadowraze sound integration changed range damage")

local helix_context = {
    player_id = 0,
    attacker = attacker,
    target = primary,
    skill_id = "skill_axe_counter_helix",
    level = 1,
    attributes = {},
}
assert(service.runners.skill_axe_counter_helix(helix_context, {
    radius = { 400 },
    damage_multiplier = { 30 },
}) == true, "Counter Helix runner failed")
assert(#sound_calls == 3
        and sound_calls[3].cue_id == "hero_axe_counter_helix_impact",
    "Counter Helix did not play exactly one position sound")
assert(#deals == 2 and #deals[2].targets == 3,
    "Counter Helix sound integration changed range damage")

local secondary_attacks = {}
local drow = make_summon(401, Vector(0, 0, 0))
drow.survival_drow_companion = true
drow.survival_drow_attack_range = 1200
drow.survival_drow_max_targets = 5
drow.PerformAttack = function(_, target)
    secondary_attacks[#secondary_attacks + 1] = target
end
assert(service.on_drow_companion_attack_fired(drow, primary) == true,
    "Drow companion volley failed")
assert(#sound_calls == 4
        and sound_calls[4].cue_id == "hero_drow_companion_volley"
        and sound_calls[4].options.unit == drow,
    "Drow companion volley did not play once on the companion")
assert(#secondary_attacks == 2,
    "Drow companion sound integration changed secondary attacks")

local normal_unit = make_summon(402, Vector(0, 0, 0))
assert(service.on_drow_companion_attack_fired(normal_unit, primary) == false,
    "Non-companion attack entered the volley lifecycle")
assert(#sound_calls == 4,
    "Non-companion attack played a volley sound")

print("HERO_EXCLUSIVE_SOUND_STATE_PASS")