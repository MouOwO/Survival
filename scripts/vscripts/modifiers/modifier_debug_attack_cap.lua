if LinkLuaModifier then
    LinkLuaModifier("modifier_debug_attack_cap", "modifiers/modifier_debug_attack_cap", LUA_MODIFIER_MOTION_NONE)
end
modifier_debug_attack_cap = class({})
_G.modifier_debug_attack_cap = modifier_debug_attack_cap

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
        MODIFIER_PROPERTY_IGNORE_ATTACKSPEED_LIMIT,
        MODIFIER_PROPERTY_ATTACKSPEED_ABSOLUTE_MAX,
    }
end

function modifier_debug_attack_cap:GetModifierIgnoreAttackSpeedLimit()
    return 1
end

function modifier_debug_attack_cap:GetModifierAttackSpeedAbsoluteMax()
    return ATTACK_SPEED_MAX
end

return modifier_debug_attack_cap
