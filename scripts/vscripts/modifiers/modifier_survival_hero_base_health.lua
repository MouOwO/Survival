LinkLuaModifier(
    "modifier_survival_hero_base_health",
    "modifiers/modifier_survival_hero_base_health",
    LUA_MODIFIER_MOTION_NONE
)

modifier_survival_hero_base_health = class({})

function modifier_survival_hero_base_health:IsHidden() return true end
function modifier_survival_hero_base_health:IsPurgable() return false end
function modifier_survival_hero_base_health:RemoveOnDeath() return false end
function modifier_survival_hero_base_health:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_survival_hero_base_health:OnCreated(kv)
    if IsServer() then self:SetHealthBonus(kv.health_bonus) end
end

function modifier_survival_hero_base_health:OnRefresh(kv)
    if IsServer() then self:SetHealthBonus(kv.health_bonus) end
end

function modifier_survival_hero_base_health:SetHealthBonus(value)
    if not IsServer() then return end
    self:SetStackCount(math.max(0, math.floor(tonumber(value) or 0)))
end

function modifier_survival_hero_base_health:DeclareFunctions()
    return { MODIFIER_PROPERTY_HEALTH_BONUS }
end

function modifier_survival_hero_base_health:GetModifierHealthBonus()
    return self:GetStackCount()
end

return modifier_survival_hero_base_health
