-- ============================================================================
-- Modifier: building_immunity - 建造中无敌
-- ============================================================================
modifier_building_immunity = class({})

function modifier_building_immunity:IsHidden()
    return true
end

function modifier_building_immunity:IsPurgable()
    return false
end

function modifier_building_immunity:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_MAGICAL,
        MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_PHYSICAL,
        MODIFIER_PROPERTY_ABSOLUTE_NO_DAMAGE_PURE,
    }
end

function modifier_building_immunity:GetAbsoluteNoDamageMagical()
    return 1
end

function modifier_building_immunity:GetAbsoluteNoDamagePhysical()
    return 1
end

function modifier_building_immunity:GetAbsoluteNoDamagePure()
    return 1
end
