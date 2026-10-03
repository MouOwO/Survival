-- Replicated cosmetic modifier, so activity overrides also run on clients.
LinkLuaModifier("modifier_tower_laser_pose", "modifiers/modifier_tower_laser_pose", LUA_MODIFIER_MOTION_NONE)
modifier_tower_laser_pose = class({})
function modifier_tower_laser_pose:IsHidden() return true end
function modifier_tower_laser_pose:IsPurgable() return false end
function modifier_tower_laser_pose:DeclareFunctions()
    return { MODIFIER_PROPERTY_OVERRIDE_ANIMATION, MODIFIER_PROPERTY_OVERRIDE_ANIMATION_RATE,
        MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK }
end
function modifier_tower_laser_pose:GetOverrideAnimation()
    -- Wisp is already a hovering emitter and has no humanoid casting pose.
    local unit = self:GetParent()
    if unit.GetModelName and string.find(unit:GetModelName() or "", "/wisp/", 1, true) then
        return ACT_DOTA_IDLE
    end
    return ACT_DOTA_CAST_ABILITY_1
end
function modifier_tower_laser_pose:GetOverrideAnimationRate() return 0.35 end
function modifier_tower_laser_pose:OnCreated()
    if IsServer() then self:OnIntervalThink(); self:StartIntervalThink(0.03) end
end
function modifier_tower_laser_pose:OnIntervalThink()
    local unit = self:GetParent()
    unit:RemoveGesture(ACT_DOTA_ATTACK)
    unit:RemoveGesture(ACT_DOTA_ATTACK2)
end
function modifier_tower_laser_pose:OnAttackStart(event)
    if IsServer() and event.attacker == self:GetParent() then self:OnIntervalThink() end
end
function modifier_tower_laser_pose:OnAttack(event)
    if IsServer() and event.attacker == self:GetParent() then self:OnIntervalThink() end
end
