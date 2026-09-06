modifier_debug_fixed_attack_rate = class({})

local DEFAULT_ATTACK_INTERVAL = 0.1

local function normalized_interval(value)
    local interval = tonumber(value)
    if not interval or interval <= 0 then
        return DEFAULT_ATTACK_INTERVAL
    end
    return math.max(0.01, interval)
end

function modifier_debug_fixed_attack_rate:OnCreated(params)
    self.attack_interval = normalized_interval(
        params and params.attack_interval
    )
end

function modifier_debug_fixed_attack_rate:OnRefresh(params)
    if params and params.attack_interval ~= nil then
        self.attack_interval = normalized_interval(params.attack_interval)
    end
end

function modifier_debug_fixed_attack_rate:IsHidden()
    return true
end

function modifier_debug_fixed_attack_rate:IsPurgable()
    return false
end

function modifier_debug_fixed_attack_rate:RemoveOnDeath()
    return false
end

function modifier_debug_fixed_attack_rate:DeclareFunctions()
    return { MODIFIER_PROPERTY_FIXED_ATTACK_RATE }
end

function modifier_debug_fixed_attack_rate:GetModifierFixedAttackRate()
    return self.attack_interval or DEFAULT_ATTACK_INTERVAL
end

return modifier_debug_fixed_attack_rate
