LinkLuaModifier(
    "modifier_survival_hero_attack_range",
    "modifiers/modifier_survival_hero_attack_range",
    LUA_MODIFIER_MOTION_NONE
)

modifier_survival_hero_attack_range = class({})

function modifier_survival_hero_attack_range:IsHidden() return true end
function modifier_survival_hero_attack_range:IsPurgable() return false end
function modifier_survival_hero_attack_range:RemoveOnDeath() return false end
function modifier_survival_hero_attack_range:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_survival_hero_attack_range:OnCreated(kv)
    if IsServer() then self:SetAttackRange(kv.attack_range) end
end

function modifier_survival_hero_attack_range:OnRefresh(kv)
    if IsServer() then self:SetAttackRange(kv.attack_range) end
end

function modifier_survival_hero_attack_range:SetAttackRange(value)
    if not IsServer() then return end
    self:SetStackCount(math.max(0, math.floor(tonumber(value) or 0)))
end

function modifier_survival_hero_attack_range:DeclareFunctions()
    return { MODIFIER_PROPERTY_ATTACK_RANGE_BASE_OVERRIDE }
end

function modifier_survival_hero_attack_range:GetModifierAttackRangeOverride()
    return self:GetStackCount()
end

return modifier_survival_hero_attack_range