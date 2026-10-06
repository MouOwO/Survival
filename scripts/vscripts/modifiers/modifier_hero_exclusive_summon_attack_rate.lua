modifier_hero_exclusive_summon_attack_rate = class({})
_G.modifier_hero_exclusive_summon_attack_rate = modifier_hero_exclusive_summon_attack_rate

local M = modifier_hero_exclusive_summon_attack_rate
local DEFAULT_ATTACK_INTERVAL = 1
local MIN_ATTACK_INTERVAL = 0.01

local function normalized_interval(value)
    local interval = tonumber(value)
    if not interval or interval ~= interval or interval <= 0
        or interval == math.huge then return nil end
    return math.max(MIN_ATTACK_INTERVAL, interval)
end

function M:IsHidden() return true end
function M:IsPurgable() return false end
function M:RemoveOnDeath() return false end

function M:OnCreated(params)
    self.attack_interval = normalized_interval(params and params.attack_interval)
        or DEFAULT_ATTACK_INTERVAL
    if IsServer() then
        self:SetHasCustomTransmitterData(true)
        self:SendBuffRefreshToClients()
    end
end

function M:OnRefresh(params)
    if IsServer() and not self.refreshing_interval then
        self:SetAttackInterval(params and params.attack_interval)
    end
end

function M:SetAttackInterval(value)
    if not IsServer() then return false end
    local interval = normalized_interval(value)
    if not interval then return false end
    if self.attack_interval == interval then return true end
    self.attack_interval = interval
    -- Invalidate the native modifier/property cache as well as transmitting
    -- the value. Updating a Lua field alone can leave the old attack cadence.
    if self.ForceRefresh then
        -- A native refresh may replay creation parameters. Do not let those
        -- overwrite the interval being applied or trigger a nested refresh.
        self.refreshing_interval = true
        self:ForceRefresh()
        self.refreshing_interval = nil
    end
    self:SendBuffRefreshToClients()
    return true
end

function M:DeclareFunctions()
    return { MODIFIER_PROPERTY_FIXED_ATTACK_RATE }
end

function M:GetModifierFixedAttackRate()
    return normalized_interval(self.attack_interval) or DEFAULT_ATTACK_INTERVAL
end

function M:AddCustomTransmitterData()
    return { attack_interval = self:GetModifierFixedAttackRate() }
end

function M:HandleCustomTransmitterData(data)
    if IsServer() then return end
    local interval = normalized_interval(data and data.attack_interval)
    if interval then self.attack_interval = interval end
end

return M
