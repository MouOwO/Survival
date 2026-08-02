modifier_debug_move_speed_cap = class({})
_G.modifier_debug_move_speed_cap = modifier_debug_move_speed_cap

local MOVE_SPEED_CAP = 600

function modifier_debug_move_speed_cap:IsHidden()
    return true
end

function modifier_debug_move_speed_cap:IsPurgable()
    return false
end

function modifier_debug_move_speed_cap:RemoveOnDeath()
    return false
end

function modifier_debug_move_speed_cap:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MOVESPEED_MAX,
        MODIFIER_PROPERTY_MOVESPEED_LIMIT,
    }
end

function modifier_debug_move_speed_cap:GetModifierMoveSpeed_Max()
    return MOVE_SPEED_CAP
end

function modifier_debug_move_speed_cap:GetModifierMoveSpeed_Limit()
    return MOVE_SPEED_CAP
end

return modifier_debug_move_speed_cap