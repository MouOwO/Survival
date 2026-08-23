LinkLuaModifier(
    "modifier_survival_hero_projectile_speed",
    "modifiers/modifier_survival_hero_projectile_speed",
    LUA_MODIFIER_MOTION_NONE
)

modifier_survival_hero_projectile_speed = class({})

function modifier_survival_hero_projectile_speed:IsHidden() return true end
function modifier_survival_hero_projectile_speed:IsPurgable() return false end
function modifier_survival_hero_projectile_speed:RemoveOnDeath() return false end
function modifier_survival_hero_projectile_speed:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_survival_hero_projectile_speed:OnCreated(kv)
    if IsServer() then self:SetProjectileSpeedBonus(kv.projectile_speed_bonus) end
end

function modifier_survival_hero_projectile_speed:OnRefresh(kv)
    if IsServer() then self:SetProjectileSpeedBonus(kv.projectile_speed_bonus) end
end

function modifier_survival_hero_projectile_speed:SetProjectileSpeedBonus(value)
    if not IsServer() then return end
    self:SetStackCount(math.floor(tonumber(value) or 0))
end

function modifier_survival_hero_projectile_speed:DeclareFunctions()
    return { MODIFIER_PROPERTY_PROJECTILE_SPEED_BONUS }
end

function modifier_survival_hero_projectile_speed:GetModifierProjectileSpeedBonus()
    return self:GetStackCount()
end

return modifier_survival_hero_projectile_speed