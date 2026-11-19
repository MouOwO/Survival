modifier_lumberjack_native_cadence = class({})
local M = modifier_lumberjack_native_cadence
_G.modifier_lumberjack_native_cadence = M
local function finite(value)
    value = tonumber(value)
    return value and value == value and math.abs(value) < math.huge and value or nil
end
function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end
function M:DeclareFunctions()
    return { MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE, MODIFIER_PROPERTY_ATTACKSPEED_ABSOLUTE_MAX,
        MODIFIER_PROPERTY_IGNORE_ATTACKSPEED_LIMIT }
end
function M:OnCreated()
    self.ratio, self.extra_percentage, self.absolute_max = 1, 0, 10000
    if not IsServer() then return end
    self.sources, self.source_total = {}, 0
    self:SetHasCustomTransmitterData(true)
    -- One census at actual modifier creation, including buffs already alive
    -- before same-entity fusion. Afterwards the source-identity map is updated
    -- by addition/value-change/removal events, never by attacks or a timer.
    local parent = self:GetParent()
    local cheer = parent:FindModifierByName("modifier_lumberjack_cheer")
    if cheer then self.sources[cheer] = cheer:GetStackCount(); self.source_total = self.source_total + self.sources[cheer] end
    if parent.FindAllModifiersByName then
        for _, modifier in ipairs(parent:FindAllModifiersByName("modifier_survival_managed_buff") or {}) do
            if modifier.definition and modifier.definition.effect_type == "attack_speed_pct" then
                local value = finite(modifier.value) or 0
                self.sources[modifier] = value
                self.source_total = self.source_total + value
            end
        end
    end
end
function M:PublishCadence()
    local percentage = (self.ratio - 1) * (100 + self.source_total)
    local maximum = 10000 * math.max(1, self.ratio)
    if percentage == self.extra_percentage and maximum == self.absolute_max then return end
    self.extra_percentage, self.absolute_max = percentage, maximum
    -- Mark native stat caches dirty and replicate only real changes. No full
    -- CalculateStatBonus/ForceRefresh or per-hit animation/order writes.
    self:SetStackCount((self:GetStackCount() + 1) % 1073741823)
    self:SendBuffRefreshToClients()
end
function M:SetCadence(reference_interval, final_interval)
    if not IsServer() then return end
    reference_interval, final_interval = finite(reference_interval), finite(final_interval)
    assert(reference_interval and reference_interval > 0 and final_interval and final_interval > 0,
        "invalid_fused_native_cadence")
    local ratio = reference_interval / final_interval
    if ratio == self.ratio then return end
    self.ratio = ratio
    self:PublishCadence()
end
function M:SetPercentageSource(source, value)
    if not IsServer() or not self.sources or not source then return end
    value = value ~= nil and finite(value) or nil
    local previous = self.sources[source]
    if previous == value then return end
    self.sources[source] = value
    self.source_total = self.source_total - (previous or 0) + (value or 0)
    self:PublishCadence()
end
function M:AddCustomTransmitterData()
    return { extra_percentage = self.extra_percentage or 0, absolute_max = self.absolute_max or 10000 }
end
function M:HandleCustomTransmitterData(data)
    self.extra_percentage = finite(data.extra_percentage) or 0
    self.absolute_max = finite(data.absolute_max) or 10000
end
function M:GetModifierAttackSpeedPercentage() return self.extra_percentage or 0 end
function M:GetModifierAttackSpeedAbsoluteMax() return self.absolute_max or 10000 end
function M:GetModifierAttackSpeed_Limit() return 1 end
function M:OnDestroy()
    self.sources, self.source_total = nil, nil
end
return M
