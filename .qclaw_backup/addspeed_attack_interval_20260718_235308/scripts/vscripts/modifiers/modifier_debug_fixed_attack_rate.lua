modifier_debug_fixed_attack_rate = class({})

local FIXED_ATTACK_INTERVAL = 0.1

function modifier_debug_fixed_attack_rate:IsHidden()
    return true
end

function modifier_debug_fixed_attack_rate:IsPurgable()
    return false
end

function modifier_debug_fixed_attack_rate:RemoveOnDeath()
    return false
end

function modifier_debug_fixed_attack_rate:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_FIXED_ATTACK_RATE,
        MODIFIER_PROPERTY_IGNORE_ATTACKSPEED_LIMIT,
        MODIFIER_PROPERTY_ATTACKSPEED_ABSOLUTE_MAX,
    }
end

function modifier_debug_fixed_attack_rate:GetModifierFixedAttackRate()
    return FIXED_ATTACK_INTERVAL
end

function modifier_debug_fixed_attack_rate:GetModifierAttackSpeed_Limit()
    return 1
end

function modifier_debug_fixed_attack_rate:GetModifierAttackSpeedAbsoluteMax()
    return 10000
end

return modifier_debug_fixed_attack_rate
