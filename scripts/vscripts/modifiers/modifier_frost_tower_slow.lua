-- ============================================================================
-- Modifier: frost_tower_slow - 冰冻塔减速效果
-- ============================================================================
modifier_frost_tower_slow = class({})

function modifier_frost_tower_slow:IsHidden()
    return false
end

function modifier_frost_tower_slow:IsPurgable()
    return true
end

function modifier_frost_tower_slow:GetAttributes()
    return MODIFIER_ATTRIBUTE_NONE
end

function modifier_frost_tower_slow:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
    }
end

function modifier_frost_tower_slow:GetModifierMoveSpeedBonus_Percentage()
    return -(TOWERS_CONFIG.frost.slow_percent * 100)
end
