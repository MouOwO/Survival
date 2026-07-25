local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local EFFECTS = {
    finger = {
        particle = "particles/units/heroes/hero_lion/lion_spell_finger_of_death.vpcf",
        sound = "Hero_Lion.FingerOfDeath",
    },
    laguna = {
        particle = "particles/units/heroes/hero_lina/lina_spell_laguna_blade.vpcf",
        sound = "Ability.LagunaBlade",
    },
    arcane = {
        -- 奥术至尊本身是被动技能，没有单独的攻击弹道。
        -- 使用拉比克绿色奥术伤害弹道表现最终阶段的4倍魔法攻击。
        particle = "particles/units/heroes/hero_rubick/rubick_fade_bolt.vpcf",
        sound = "Hero_Rubick.FadeBolt.Cast",
    },
}

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
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
    if not valid(caster) or not valid(target) or not effect then return end
    local ok, particle = pcall(function()
        return ParticleManager:CreateParticle(
            effect.particle,
            PATTACH_CUSTOMORIGIN,
            caster
        )
    end)
    if ok and particle then
        ParticleManager:SetParticleControlEnt(
            particle,
            0,
            caster,
            PATTACH_POINT_FOLLOW,
            "attach_attack1",
            caster:GetAbsOrigin(),
            true
        )
        ParticleManager:SetParticleControlEnt(
            particle,
            1,
            target,
            PATTACH_POINT_FOLLOW,
            "attach_hitloc",
            target:GetAbsOrigin(),
            true
        )
        ParticleManager:ReleaseParticleIndex(particle)
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
    if not valid(tower) or not valid(target) then return end
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

return M
