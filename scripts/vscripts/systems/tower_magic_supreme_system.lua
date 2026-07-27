local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local EFFECTS = {
    finger = {
        particle = "particles/units/heroes/hero_lion/lion_spell_finger_of_death.vpcf",
        sound = "Hero_Lion.FingerOfDeath",
        sound_file = "soundevents/game_sounds_heroes/game_sounds_lion.vsndevts",
        -- 死亡一指的粒子控制点与常规光束相反：0为目标，1为施法者。
        source_control = 1,
        target_control = 0,
    },
    laguna = {
        particle = "particles/units/heroes/hero_lina/lina_spell_laguna_blade.vpcf",
        sound = "Ability.LagunaBlade",
        sound_file = "soundevents/game_sounds_heroes/game_sounds_lina.vsndevts",
        source_control = 0,
        target_control = 1,
    },
    arcane = {
        -- 奥术至尊本身是被动技能，没有单独的攻击弹道。
        -- 使用拉比克绿色奥术伤害弹道表现最终阶段的4倍魔法攻击。
        particle = "particles/units/heroes/hero_rubick/rubick_fade_bolt.vpcf",
        sound = "Hero_Rubick.FadeBolt.Cast",
        sound_file = "soundevents/game_sounds_heroes/game_sounds_rubick.vsndevts",
        source_control = 0,
        target_control = 1,
    },
}

local function exists(unit)
    return unit and not unit:IsNull()
end

local function valid(unit)
    return exists(unit) and unit:IsAlive()
end

local function skill_matching(skills, prefix)
    for _, row in pairs(skills or {}) do
        if row.skill_id and string.match(row.skill_id, "^" .. prefix) then
            return row
        end
    end
    return nil
end

local function owns_ability(tower, skill)
    if not valid(tower) or not skill or not skill.skill_id then return false end
    local ability = tower:FindAbilityByName(skill.skill_id)
    return ability and not ability:IsNull() and ability:GetLevel() > 0
end

local function attack_damage(tower)
    if not valid(tower) then return 0 end
    return math.max(0, tonumber(tower:GetAverageTrueAttackDamage(tower)) or 0)
end

local function play_effect(caster, target, effect)
    if not valid(caster) or not exists(target) or not effect then return end
    local particle = nil
    local ok, error_message = pcall(function()
        particle = ParticleManager:CreateParticle(
            effect.particle,
            PATTACH_CUSTOMORIGIN,
            caster
        )
        ParticleManager:SetParticleControlEnt(
            particle,
            effect.source_control or 0,
            caster,
            PATTACH_POINT_FOLLOW,
            "attach_attack1",
            caster:GetAbsOrigin(),
            true
        )
        ParticleManager:SetParticleControlEnt(
            particle,
            effect.target_control or 1,
            target,
            PATTACH_POINT_FOLLOW,
            "attach_hitloc",
            target:GetAbsOrigin(),
            true
        )
        ParticleManager:ReleaseParticleIndex(particle)
    end)
    if not ok then
        print(string.format(
            "[TowerMagic] particle failed path=%s error=%s",
            tostring(effect.particle), tostring(error_message)
        ))
        if particle then
            pcall(function()
                ParticleManager:DestroyParticle(particle, true)
                ParticleManager:ReleaseParticleIndex(particle)
            end)
        end
    end
    if effect.sound then
        pcall(function() EmitSoundOn(effect.sound, target) end)
    end
end

local function deal_magic(tower, target, damage, tag)
    return event_bus.request(events.TOWER_SKILL_DAMAGE_REQUEST, {
        attacker = tower,
        victim = target,
        damage = math.max(0, damage),
        damage_type = DAMAGE_TYPE_MAGICAL,
        source_kind = "ability",
        tags = { "tower_magic_supreme", tag },
    })
end

local function chance(skill, fallback)
    return math.max(0, math.min(
        100,
        tonumber(skill and skill.trigger_chance_pct) or fallback or 0
    ))
end

local function multiplier(skill, fallback)
    return math.max(
        0,
        tonumber(skill and skill.damage_multiplier) or fallback or 0
    )
end

local function trigger_chance_skill(tower, target, skill, effect, tag, base)
    if not skill or not owns_ability(tower, skill) then return false end
    if not RollPercentage(chance(skill, 20)) then return false end
    play_effect(tower, target, effect)
    deal_magic(tower, target, base * multiplier(skill, 1), tag)
    return true
end

local function on_attack_landed(payload)
    local tower = payload and payload.tower
    local target = payload and payload.target
    -- 普攻可能先将目标击杀；死亡实体仍保留足够长时间用于播放命中特效。
    if not valid(tower) or not exists(target) then return end
    if target:GetTeamNumber() == tower:GetTeamNumber() then return end

    local skills = payload.skills or {}
    local base = attack_damage(tower)
    if base <= 0 then return end

    local finger = skill_matching(skills, "magic_finger_")
    trigger_chance_skill(
        tower,
        target,
        finger,
        EFFECTS.finger,
        "death_finger",
        base
    )

    local laguna = skill_matching(skills, "magic_laguna_")
    trigger_chance_skill(
        tower,
        target,
        laguna,
        EFFECTS.laguna,
        "laguna_blade",
        base
    )

    local supreme = skill_matching(skills, "arcane_supremacy_")
    if supreme and owns_ability(tower, supreme) then
        play_effect(tower, target, EFFECTS.arcane)
        deal_magic(
            tower,
            target,
            base * multiplier(supreme, 4),
            "arcane_supremacy"
        )
    end
end

function M.init()
    event_bus.subscribe(events.TOWER_ATTACK_LANDED, on_attack_landed)
end

function M.precache(context)
    local particles = {}
    local sound_files = {}
    for _, effect in pairs(EFFECTS) do
        if effect.particle and not particles[effect.particle] then
            PrecacheResource("particle", effect.particle, context)
            particles[effect.particle] = true
        end
        if effect.sound_file and not sound_files[effect.sound_file] then
            PrecacheResource("soundfile", effect.sound_file, context)
            sound_files[effect.sound_file] = true
        end
    end
end

return M
