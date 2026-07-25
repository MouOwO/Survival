modifier_research_technology = class({})
modifier_research_armor_reduction = class({})

local event_bus = require("core/event_bus")
local events = require("core/events")
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
    if IsServer() then
        self:GetParent().survival_research_final_damage_pct =
            self.final_damage_pct
    end
end

function M:SetTechnologyValues(attack_pct, final_damage_pct, armor_reduction,
        critical_chance_pct)
    self.attack_pct = math.max(0, tonumber(attack_pct) or 0)
    self.final_damage_pct = math.max(0, tonumber(final_damage_pct) or 0)
    self.armor_reduction = math.max(0, tonumber(armor_reduction) or 0)
    self.critical_chance_pct = math.max(
        0, tonumber(critical_chance_pct) or 0
    )
    self:GetParent().survival_research_final_damage_pct =
        self.final_damage_pct
    self:ForceRefresh()
end

function M:OnDestroy()
    if IsServer() then
        self:GetParent().survival_research_final_damage_pct = nil
    end
end

function M:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_PREATTACK_CRITICALSTRIKE,
        MODIFIER_EVENT_ON_ATTACK_LANDED,
    }
end

function M:GetModifierPreAttack_CriticalStrike()
    if not IsServer() then return 0 end
    return RandomFloat(0, 100) < (self.critical_chance_pct or 0)
        and 200 or 0
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
        { armor_reduction_per_attack = self.armor_reduction }
    )
end

local D = modifier_research_armor_reduction

function D:IsHidden() return false end
function D:IsDebuff() return true end
function D:IsPurgable() return false end
function D:GetAttributes() return MODIFIER_ATTRIBUTE_PERMANENT end

function D:OnCreated(params)
    self.armor_reduction = 0
    self:AddArmorReduction(params and params.armor_reduction_per_attack or 0)
end

function D:OnRefresh(params)
    self:AddArmorReduction(params and params.armor_reduction_per_attack or 0)
end

function D:AddArmorReduction(value)
    if not IsServer() then return end
    local increment = math.max(0, tonumber(value) or 0)
    if increment <= 0 then return end
    local parent = self:GetParent()
    local minimum = tonumber(parent.survival_minimum_armor)
    if minimum ~= nil then
        local current = tonumber(parent:GetPhysicalArmorValue(false)) or minimum
        increment = math.min(increment, math.max(0, current - minimum))
    end
    if increment <= 0 then return end
    self.armor_reduction = (self.armor_reduction or 0) + increment
    self:SetStackCount(math.floor(self.armor_reduction * 100 + 0.5))
    event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
        entindex = parent:entindex(),
        unit = parent,
        reason = "research_armor_reduction",
    })
end

function D:DeclareFunctions()
    return { MODIFIER_PROPERTY_PHYSICAL_ARMOR_BONUS }
end

function D:GetModifierPhysicalArmorBonus()
    return -(self:GetStackCount() or 0) / 100
end

return M
