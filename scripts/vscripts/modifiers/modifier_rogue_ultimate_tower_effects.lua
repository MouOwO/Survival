local effects = require("systems/rogue_ultimate_tower_effect_service")

modifier_rogue_ultimate_tower_effects = class({})

function modifier_rogue_ultimate_tower_effects:IsHidden() return true end
function modifier_rogue_ultimate_tower_effects:IsPurgable() return false end
function modifier_rogue_ultimate_tower_effects:RemoveOnDeath() return false end
function modifier_rogue_ultimate_tower_effects:OnCreated()
    if not IsServer() then return end
    if self.SetHasCustomTransmitterData then self:SetHasCustomTransmitterData(true) end
    self:OnIntervalThink()
    if self.StartIntervalThink then self:StartIntervalThink(0.25) end
end
function modifier_rogue_ultimate_tower_effects:OnIntervalThink()
    local parent = self:GetParent()
    if not parent or parent:IsNull() then return end
    local pct, flat = effects.attack_bonus_delta(parent), effects.pre_attack_delta(parent)
    if pct == self.attack_bonus_pct and flat == self.attack_flat then return end
    self.attack_bonus_pct, self.attack_flat = pct, flat
    if self.SendBuffRefreshToClients then self:SendBuffRefreshToClients() end
end
function modifier_rogue_ultimate_tower_effects:AddCustomTransmitterData()
    return {attack_bonus_pct = self.attack_bonus_pct or 0, attack_flat = self.attack_flat or 0}
end
function modifier_rogue_ultimate_tower_effects:HandleCustomTransmitterData(data)
    self.attack_bonus_pct = tonumber(data.attack_bonus_pct) or 0
    self.attack_flat = tonumber(data.attack_flat) or 0
end
function modifier_rogue_ultimate_tower_effects:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE,
    }
end
function modifier_rogue_ultimate_tower_effects:GetModifierBaseDamageOutgoing_Percentage()
    return IsServer() and effects.attack_bonus_delta(self:GetParent()) or self.attack_bonus_pct or 0
end
function modifier_rogue_ultimate_tower_effects:GetModifierPreAttack_BonusDamage()
    return IsServer() and effects.pre_attack_delta(self:GetParent()) or self.attack_flat or 0
end

return modifier_rogue_ultimate_tower_effects
