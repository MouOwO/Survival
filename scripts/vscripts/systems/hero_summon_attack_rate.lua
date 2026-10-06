-- All hero-owned combat summons inherit the final attack interval. Preserve
-- their natural BAT: the engine uses BAT / fixed interval to accelerate the
-- attack animation. Setting both to the final interval leaves a slow animation
-- even though GetAttacksPerSecond and the HUD report the inherited fast rate.
local M = {}
local MODIFIER = "modifier_hero_exclusive_summon_attack_rate"
local MIN_INTERVAL = 0.01

local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
end

local function positive(value)
    value = tonumber(value)
    if value and value == value and value > 0 and value < math.huge then return value end
end

local function read(unit, method, ...)
    if not valid(unit) or type(unit[method]) ~= "function" then return nil end
    local ok, result = pcall(unit[method], unit, ...)
    if ok then return result end
end

function M.current(source, fallback_aps)
    local fixed = read(source, "FindModifierByName", "modifier_debug_fixed_attack_rate")
    local interval = positive(read(fixed, "GetModifierFixedAttackRate"))
    if interval then return 1 / interval end
    local aps = positive(read(source, "GetAttacksPerSecond", false))
    if aps then return aps end
    interval = positive(read(source, "GetSecondsPerAttack", false))
    return interval and 1 / interval or positive(fallback_aps) or 0
end

function M.apply(unit, source, fallback_aps, inherit_pct)
    if not valid(unit) then return nil, nil, "summon_invalid" end
    local aps = positive(M.current(source, fallback_aps)
        * (tonumber(inherit_pct) or 100) / 100)
    if not aps then return nil, nil, "attack_rate_invalid" end
    local interval = math.max(MIN_INTERVAL, 1 / aps)
    local modifier = read(unit, "FindModifierByName", MODIFIER)
    if not modifier or type(modifier.SetAttackInterval) ~= "function" then
        modifier = unit:AddNewModifier(valid(source) and source or unit, nil,
            MODIFIER, { attack_interval = interval })
        if not modifier then return nil, nil, "attack_rate_modifier_failed" end
    else
        modifier:SetAttackInterval(interval)
    end
    unit.survival_summon_attack_interval = interval
    unit.survival_attack_speed = 1 / interval
    return unit.survival_attack_speed, interval
end

return M
