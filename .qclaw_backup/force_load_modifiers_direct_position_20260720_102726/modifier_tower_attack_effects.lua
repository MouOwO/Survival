modifier_tower_attack_effects = class({})
_G.modifier_tower_attack_effects = modifier_tower_attack_effects

local tower_skills = require("systems/tower_skill_runtime")

function modifier_tower_attack_effects:IsHidden() return true end
function modifier_tower_attack_effects:IsPurgable() return false end
function modifier_tower_attack_effects:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_LANDED }
end

local function valid(u) return u and not u:IsNull() and u:IsAlive() end

local function lightning_particle(caster, target)
    local particle = ParticleManager:CreateParticle(
        "particles/units/heroes/hero_zuus/zuus_lightning_bolt.vpcf",
        PATTACH_CUSTOMORIGIN, caster)
    ParticleManager:SetParticleControl(particle, 0, caster:GetAbsOrigin())
    ParticleManager:SetParticleControl(particle, 1, target:GetAbsOrigin())
    ParticleManager:ReleaseParticleIndex(particle)
end

local function deal(caster, target, amount)
    if not valid(target) then return end
    ApplyDamage({ victim = target, attacker = caster, damage = math.max(0, amount), damage_type = DAMAGE_TYPE_PHYSICAL })
end

function modifier_tower_attack_effects:OnAttackLanded(params)
    if not IsServer() or params.attacker ~= self:GetParent() then return end
    local caster, primary = self:GetParent(), params.target
    if not valid(primary) or primary:GetTeamNumber() == caster:GetTeamNumber() then return end
    local skills = tower_skills.get(caster)
    local multi = nil
    local lightning = nil
    for _, row in pairs(skills) do
        if row.skill_id and string.match(row.skill_id, "^multi_attack_") then multi = row end
        if row.skill_id and string.match(row.skill_id, "^lightning_strike_") then lightning = row end
    end
    local damage = caster:GetAverageTrueAttackDamage(caster)
    if multi then
        local max_targets = math.max(1, tonumber(multi.max_targets) or 1)
        local units = FindUnitsInRadius(caster:GetTeamNumber(), primary:GetAbsOrigin(), nil,
            caster:GetAcquisitionRange(), DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
            DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST, false)
        local count = 0
        for _, target in ipairs(units) do
            if target ~= primary and count < max_targets - 1 then
                deal(caster, target, damage * 1.30)
                count = count + 1
            end
        end
    end
    if lightning then
        lightning_particle(caster, primary)
        local max_targets = math.max(1, tonumber(lightning.max_targets) or 1)
        local units = FindUnitsInRadius(caster:GetTeamNumber(), primary:GetAbsOrigin(), nil,
            caster:GetAcquisitionRange(), DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
            DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES, FIND_CLOSEST, false)
        local count, factor = 0, 0.90
        for _, target in ipairs(units) do
            if target ~= primary and count < max_targets - 1 then
                lightning_particle(caster, target)
                deal(caster, target, damage * factor)
                factor = factor * 0.90
                count = count + 1
            end
        end
    end
end
