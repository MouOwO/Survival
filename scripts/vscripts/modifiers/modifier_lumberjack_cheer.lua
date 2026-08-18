modifier_lumberjack_cheer = class({})

function modifier_lumberjack_cheer:IsHidden() return true end
function modifier_lumberjack_cheer:IsPurgable() return false end
function modifier_lumberjack_cheer:RemoveOnDeath() return false end
function modifier_lumberjack_cheer:DeclareFunctions()
    return { MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT }
end
function modifier_lumberjack_cheer:GetModifierAttackSpeedBonus_Constant()
    return self:GetStackCount() * 10
end