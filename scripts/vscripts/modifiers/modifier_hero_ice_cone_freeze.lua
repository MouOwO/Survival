modifier_hero_ice_cone_freeze = class({})

local TARGET_PARTICLE = "particles/units/heroes/hero_winter_wyvern/wyvern_winters_curse.vpcf"
local STATUS_PARTICLE = "particles/status_fx/status_effect_wyvern_curse_target.vpcf"

function modifier_hero_ice_cone_freeze:IsHidden() return false end
function modifier_hero_ice_cone_freeze:IsDebuff() return true end
function modifier_hero_ice_cone_freeze:IsStunDebuff() return true end
function modifier_hero_ice_cone_freeze:IsPurgable() return false end
function modifier_hero_ice_cone_freeze:IsPurgeException() return true end
function modifier_hero_ice_cone_freeze:RemoveOnDeath() return true end

function modifier_hero_ice_cone_freeze:GetTexture()
    return "survival/native/skill_frost"
end

function modifier_hero_ice_cone_freeze:CheckState()
    return { [MODIFIER_STATE_STUNNED] = true }
end

function modifier_hero_ice_cone_freeze:GetStatusEffectName()
    return STATUS_PARTICLE
end

function modifier_hero_ice_cone_freeze:StatusEffectPriority()
    return 40
end

function modifier_hero_ice_cone_freeze:OnCreated()
    self:CreateFreezeParticle()
end

function modifier_hero_ice_cone_freeze:OnRefresh()
    self:CreateFreezeParticle()
end

function modifier_hero_ice_cone_freeze:CreateFreezeParticle()
    if not IsServer() or self.freeze_particle ~= nil then return end
    local parent = self:GetParent()
    if not parent or (parent.IsNull and parent:IsNull()) then return end

    local particle
    local ok = pcall(function()
        particle = ParticleManager:CreateParticle(
            TARGET_PARTICLE, PATTACH_ABSORIGIN_FOLLOW, parent
        )
        assert(type(particle) == "number" and particle >= 0, "Invalid freeze particle")
        local position = parent:GetAbsOrigin()
        ParticleManager:SetParticleControlEnt(
            particle, 0, parent, PATTACH_ABSORIGIN_FOLLOW, "", position, true
        )
        ParticleManager:SetParticleControl(particle, 1, position)
        -- This is the native target preview scale, not the ground area's radius.
        ParticleManager:SetParticleControl(particle, 2, Vector(1, 1, 1))
        ParticleManager:SetParticleControl(particle, 61, Vector(0, 0, 0))
        -- Immediate destruction keeps native body frost tied to actual stun time.
        self:AddParticle(particle, true, false, -1, false, false)
    end)
    if ok then
        self.freeze_particle = particle
    elseif type(particle) == "number" and particle >= 0 then
        ParticleManager:DestroyParticle(particle, true)
        ParticleManager:ReleaseParticleIndex(particle)
    end
end

function modifier_hero_ice_cone_freeze:OnDestroy()
    -- AddParticle owns destruction and release on expiry, strong dispel, or death.
    self.freeze_particle = nil
end

_G.modifier_hero_ice_cone_freeze = modifier_hero_ice_cone_freeze
return modifier_hero_ice_cone_freeze
