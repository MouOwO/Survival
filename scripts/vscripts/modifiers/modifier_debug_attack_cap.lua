modifier_debug_attack_cap = class({})

local ATTACK_SPEED_BONUS = 10000
local ATTACK_SPEED_MAX = 10000

function modifier_debug_attack_cap:IsHidden()
    return true
end

function modifier_debug_attack_cap:IsPurgable()
    return false
end

function modifier_debug_attack_cap:RemoveOnDeath()
    return false
end

function modifier_debug_attack_cap:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
        MODIFIER_PROPERTY_IGNORE_ATTACKSPEED_LIMIT,
        MODIFIER_PROPERTY_ATTACKSPEED_ABSOLUTE_MAX,
    }
end

function modifier_debug_attack_cap:GetModifierAttackSpeedBonus_Constant()
    return ATTACK_SPEED_BONUS
end

function modifier_debug_attack_cap:GetModifierAttackSpeed_Limit()
    return 1
end

function modifier_debug_attack_cap:GetModifierAttackSpeedAbsoluteMax()
    return ATTACK_SPEED_MAX
end

return modifier_debug_attack_cap
