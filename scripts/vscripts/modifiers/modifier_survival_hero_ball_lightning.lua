LinkLuaModifier(
    "modifier_survival_hero_ball_lightning",
    "modifiers/modifier_survival_hero_ball_lightning",
    LUA_MODIFIER_MOTION_HORIZONTAL
)

modifier_survival_hero_ball_lightning = class({})
local destination_validation = require("systems/destination_validation_service")

local PARTICLE = "particles/units/heroes/hero_stormspirit/stormspirit_ball_lightning.vpcf"
local SOUND = "Hero_StormSpirit.BallLightning"

function modifier_survival_hero_ball_lightning:IsHidden() return true end
function modifier_survival_hero_ball_lightning:IsPurgable() return false end
function modifier_survival_hero_ball_lightning:GetPriority()
    return DOTA_MOTION_CONTROLLER_PRIORITY_HIGH
end

function modifier_survival_hero_ball_lightning:CheckState()
    return {
        [MODIFIER_STATE_INVULNERABLE] = true,
        [MODIFIER_STATE_DISARMED] = true,
        [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
        [MODIFIER_STATE_COMMAND_RESTRICTED] = true,
        [MODIFIER_STATE_FLYING_FOR_PATHING_PURPOSES_ONLY] = true,
    }
end

function modifier_survival_hero_ball_lightning:OnCreated(kv)
    if not IsServer() then return end
    local parent = self:GetParent()
    self.target = Vector(
        tonumber(kv.x) or parent:GetAbsOrigin().x,
        tonumber(kv.y) or parent:GetAbsOrigin().y,
        tonumber(kv.z) or parent:GetAbsOrigin().z
    )
    self.speed = math.max(1, tonumber(kv.speed) or 7000)
    self.particle = ParticleManager:CreateParticle(
        PARTICLE,
        PATTACH_ABSORIGIN_FOLLOW,
        parent
    )
    parent:EmitSound(SOUND)
    if not self:ApplyHorizontalMotionController() then
        self:RefundMana()
        self:Destroy()
    end
end

function modifier_survival_hero_ball_lightning:UpdateHorizontalMotion(parent, dt)
    if not IsServer() then return end
    local origin = parent:GetAbsOrigin()
    local delta = self.target - origin
    delta.z = 0
    local remaining = delta:Length2D()
    local step = self.speed * math.max(0, tonumber(dt) or 0)
    if remaining <= math.max(1, step) then
        local valid = destination_validation.validate(self.target, parent)
        if not valid then
            self:RefundMana()
            self:Destroy()
            return
        end
        parent:SetAbsOrigin(self.target)
        self.completed = true
        self:Destroy()
        return
    end
    local next_position = origin + delta:Normalized() * step
    next_position.z = GetGroundHeight(next_position, parent)
    parent:SetAbsOrigin(next_position)
end

function modifier_survival_hero_ball_lightning:OnHorizontalMotionInterrupted()
    if not IsServer() then return end
    self:RefundMana()
    self:Destroy()
end

function modifier_survival_hero_ball_lightning:RefundMana()
    if self.mana_refunded then return end
    self.mana_refunded = true
    local ability = self:GetAbility()
    if ability and not ability:IsNull() then
        if ability.RefundTravelMana then ability:RefundTravelMana()
        else ability:RefundManaCost() end
    end
end

function modifier_survival_hero_ball_lightning:OnDestroy()
    if not IsServer() then return end
    if not self.completed then self:RefundMana() end
    local parent = self:GetParent()
    parent:RemoveHorizontalMotionController(self)
    parent:StopSound(SOUND)
    if self.particle then
        ParticleManager:DestroyParticle(self.particle, false)
        ParticleManager:ReleaseParticleIndex(self.particle)
        self.particle = nil
    end
    if parent:IsAlive() then
        local valid = destination_validation.validate(parent:GetAbsOrigin(), parent)
        if not valid and parent.survival_hero_last_legal_position then
            parent:SetAbsOrigin(parent.survival_hero_last_legal_position)
        end
        FindClearSpaceForUnit(parent, parent:GetAbsOrigin(), true)
        parent:Stop()
    end
end

return modifier_survival_hero_ball_lightning