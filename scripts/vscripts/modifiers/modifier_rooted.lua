-- ============================================================================
-- Modifier: rooted - 固定建筑不可移动
-- ============================================================================
modifier_rooted = class({})

function modifier_rooted:IsHidden()
    return true
end

function modifier_rooted:IsPurgable()
    return false
end

function modifier_rooted:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_rooted:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_DISABLE_AUTOATTACK,
        MODIFIER_PROPERTY_MOVESPEED_ABSOLUTE_MIN,
    }
end

function modifier_rooted:GetModifierDisableAutoAttack()
    return 1
end

function modifier_rooted:GetModifierMoveSpeed_AbsoluteMin()
    return 0
end

function modifier_rooted:CheckState()
    return { [MODIFIER_STATE_ROOTED] = true }
end
