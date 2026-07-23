modifier_research_technology = class({})
modifier_research_armor_reduction = class({})

local M = modifier_research_technology

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function M:OnCreated(params)
    self:ApplyValues(params or {})
end

function M:OnRefresh(params)
    self:ApplyValues(params or {})
end

function M:ApplyValues(params)
    self.attack_pct = tonumber(params.attack_pct) or self.attack_pct or 0
    self.final_damage_pct = tonumber(params.final_damage_pct)
        or self.final_damage_pct or 0
    self.armor_reduction = tonumber(params.armor_reduction)
        or self.armor_reduction or 0
end

function M:SetTechnologyValues(attack_pct, final_damage_pct, armor_reduction)
    self.attack_pct = math.max(0, tonumber(attack_pct) or 0)
    self.final_damage_pct = math.max(0, tonumber(final_damage_pct) or 0)
    self.armor_reduction = math.max(0, tonumber(armor_reduction) or 0)
    self:ForceRefresh()
end

function M:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_PROPERTY_TOTALDAMAGEOUTGOING_PERCENTAGE,
        MODIFIER_EVENT_ON_ATTACK_LANDED,
    }
end

function M:GetModifierBaseDamageOutgoing_Percentage()
    return self.attack_pct or 0
end

function M:GetModifierTotalDamageOutgoing_Percentage()
    return self.final_damage_pct or 0
end

function M:OnAttackLanded(keys)
    if not IsServer() or keys.attacker ~= self:GetParent() then return end
    local target = keys.target
    if not target or target:IsNull()
        or target:GetTeamNumber() == keys.attacker:GetTeamNumber()
        or (self.armor_reduction or 0) <= 0 then
        return
    end
    local modifier = target:AddNewModifier(
        keys.attacker,
        nil,
        "modifier_research_armor_reduction",
        { armor_reduction = self.armor_reduction }
    )
    if modifier and modifier.SetArmorReduction then
        modifier:SetArmorReduction(self.armor_reduction)
    end
end

local D = modifier_research_armor_reduction

function D:IsHidden() return false end
function D:IsDebuff() return true end
function D:IsPurgable() return true end

function D:OnCreated(params)
    self:SetArmorReduction(params and params.armor_reduction or 0)
end

function D:OnRefresh(params)
    self:SetArmorReduction(params and params.armor_reduction or 0)
end

function D:SetArmorReduction(value)
    self.armor_reduction = math.max(0, tonumber(value) or 0)
end

function D:DeclareFunctions()
    return { MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS }
end

function D:GetModifierPhysicalArmorBonus()
    return -(self.armor_reduction or 0)
end

return M
