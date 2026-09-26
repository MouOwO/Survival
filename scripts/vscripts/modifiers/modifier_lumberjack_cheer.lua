modifier_lumberjack_cheer = class({})

function modifier_lumberjack_cheer:IsHidden() return false end
function modifier_lumberjack_cheer:IsPurgable() return false end
function modifier_lumberjack_cheer:RemoveOnDeath() return false end
function modifier_lumberjack_cheer:GetTexture()
    return "survival/native/skill_multi_arrow"
end
function modifier_lumberjack_cheer:DeclareFunctions()
    return { MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE }
end
function modifier_lumberjack_cheer:GetModifierAttackSpeedPercentage()
    return self:GetStackCount()
end