LinkLuaModifier(
    "modifier_survival_hero_mana_standard",
    "modifiers/modifier_survival_hero_mana_standard",
    LUA_MODIFIER_MOTION_NONE
)

modifier_survival_hero_mana_standard = class({})

function modifier_survival_hero_mana_standard:IsHidden() return true end
function modifier_survival_hero_mana_standard:IsPurgable() return false end
function modifier_survival_hero_mana_standard:RemoveOnDeath() return false end
function modifier_survival_hero_mana_standard:GetAttributes()
    return MODIFIER_ATTRIBUTE_PERMANENT
end

function modifier_survival_hero_mana_standard:OnCreated(kv)
    self:SetManaStandard(kv.mana_adjustment, kv.mana_regen)
end

function modifier_survival_hero_mana_standard:OnRefresh(kv)
    self:SetManaStandard(kv.mana_adjustment, kv.mana_regen)
end

function modifier_survival_hero_mana_standard:SetManaStandard(adjustment, regen)
    self.mana_adjustment = tonumber(adjustment) or 0
    self.mana_regen = math.max(0, tonumber(regen) or 0)
    if IsServer() then
        self:SetStackCount(self.mana_adjustment)
    end
end

function modifier_survival_hero_mana_standard:GetManaAdjustment()
    if self.GetStackCount then return tonumber(self:GetStackCount()) or 0 end
    return tonumber(self.mana_adjustment) or 0
end

function modifier_survival_hero_mana_standard:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MANA_BONUS,
        MODIFIER_PROPERTY_MANA_REGEN_CONSTANT,
    }
end

function modifier_survival_hero_mana_standard:GetModifierManaBonus()
    return self:GetManaAdjustment()
end

function modifier_survival_hero_mana_standard:GetModifierConstantManaRegen()
    return tonumber(self.mana_regen) or 0
end

return modifier_survival_hero_mana_standard