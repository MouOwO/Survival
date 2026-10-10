-- Pure model appearance: no native Sven ability, stats, immunity or orders.
modifier_ultimate_tower_presence = class({})

function modifier_ultimate_tower_presence:IsHidden()
    return true
end

function modifier_ultimate_tower_presence:IsPurgable()
    return false
end

function modifier_ultimate_tower_presence:RemoveOnDeath()
    return true
end

function modifier_ultimate_tower_presence:GetStatusEffectName()
    return "particles/status_fx/status_effect_gods_strength.vpcf"
end

function modifier_ultimate_tower_presence:StatusEffectPriority()
    return 10
end

return modifier_ultimate_tower_presence
