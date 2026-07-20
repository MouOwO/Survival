modifier_debug_attack_timing = class({})

local BASE_ATTACK_TIME = 0.1
local ATTACK_POINT = 0.01

function modifier_debug_attack_timing:IsHidden()
    return true
end

function modifier_debug_attack_timing:IsPurgable()
    return false
end

function modifier_debug_attack_timing:RemoveOnDeath()
    return false
end

function modifier_debug_attack_timing:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT,
        MODIFIER_PROPERTY_ATTACK_POINT_CONSTANT,
    }
end

function modifier_debug_attack_timing:GetModifierBaseAttackTimeConstant()
    return BASE_ATTACK_TIME
end

function modifier_debug_attack_timing:GetModifierAttackPointConstant()
    return ATTACK_POINT
end

return modifier_debug_attack_timing
