local M = {}
local calculator_rules = require(
    "config/generated/war3_damage_calculator_rules"
)

M.MODERN_MAPPING_VERSION = 2
M.CUSTOM_WAR3_MAPPING_VERSION = 3
M.MODERN_DOTA_ARMOR_A = 225
M.MODERN_DOTA_ARMOR_B = 650
M.WAR3_POSITIVE_ARMOR_FACTOR = 0.02
M.DOTA_POSITIVE_ARMOR_NUMERATOR = 0.052
M.DOTA_POSITIVE_ARMOR_BASE = 0.9
M.DOTA_POSITIVE_ARMOR_DENOMINATOR = 0.048

local function rule_value(rule_id)
    local row = calculator_rules.by_id[rule_id]
    return assert(row and tonumber(row.value),
        "invalid armor calculator rule: " .. tostring(rule_id))
end

M.WAR3_TO_DOTA_RATIO = rule_value("war3_to_dota_ratio")
M.WAR3_POSITIVE_ARMOR_FACTOR = rule_value("war3_positive_armor_factor")
M.DOTA_POSITIVE_ARMOR_NUMERATOR = rule_value(
    "dota_positive_armor_numerator"
)
M.DOTA_POSITIVE_ARMOR_BASE = rule_value("dota_positive_armor_base")
M.DOTA_POSITIVE_ARMOR_DENOMINATOR = rule_value(
    "dota_positive_armor_denominator"
)

local function number(value)
    return tonumber(value) or 0
end

-- Legacy linear conversion remains the compatibility boundary for heroes,
-- buildings, equipment and technology values that still aggregate additively.
function M.from_war3_linear(war3_armor)
    return number(war3_armor) * M.WAR3_TO_DOTA_RATIO
end

function M.to_war3_linear(dota_armor)
    return number(dota_armor) / M.WAR3_TO_DOTA_RATIO
end

function M.from_war3(war3_armor)
    return M.from_war3_linear(war3_armor)
end

function M.to_war3(dota_armor)
    return M.to_war3_linear(dota_armor)
end

function M.from_war3_modern(war3_armor)
    local value = number(war3_armor)
    if value <= 0 then return M.from_war3_linear(value) end
    local numerator = M.DOTA_POSITIVE_ARMOR_BASE
        * M.WAR3_POSITIVE_ARMOR_FACTOR * value
    local denominator = M.DOTA_POSITIVE_ARMOR_NUMERATOR
        + M.WAR3_POSITIVE_ARMOR_FACTOR * value
            * (M.DOTA_POSITIVE_ARMOR_NUMERATOR
                - M.DOTA_POSITIVE_ARMOR_DENOMINATOR)
    if denominator <= 0 then return nil end
    return numerator / denominator
end

function M.to_war3_modern(dota_armor)
    local value = number(dota_armor)
    if value <= 0 then return M.to_war3_linear(value) end
    local denominator = M.WAR3_POSITIVE_ARMOR_FACTOR
        * (M.DOTA_POSITIVE_ARMOR_BASE
            - value * (M.DOTA_POSITIVE_ARMOR_NUMERATOR
                - M.DOTA_POSITIVE_ARMOR_DENOMINATOR))
    if denominator <= 0 then return nil end
    return value * M.DOTA_POSITIVE_ARMOR_NUMERATOR / denominator
end

function M.from_war3_for_mapping(war3_armor, mapping_version)
    if tonumber(mapping_version) == M.MODERN_MAPPING_VERSION then
        return M.from_war3_modern(war3_armor)
    end
    return M.from_war3_linear(war3_armor)
end

function M.to_war3_for_mapping(dota_armor, mapping_version)
    if tonumber(mapping_version) == M.MODERN_MAPPING_VERSION then
        return M.to_war3_modern(dota_armor)
    end
    return M.to_war3_linear(dota_armor)
end

function M.modern_physical_reduction_pct(dota_armor)
    local value = number(dota_armor)
    return 100 * (M.DOTA_POSITIVE_ARMOR_NUMERATOR * value)
        / (M.DOTA_POSITIVE_ARMOR_BASE
            + M.DOTA_POSITIVE_ARMOR_DENOMINATOR * math.abs(value))
end

function M.effective_war3_armor(base_war3_armor, reduction, minimum_war3_armor,
        percentage_reduction)
    local base = number(base_war3_armor)
    local reduced = base - math.max(0, number(reduction))
    local minimum = tonumber(minimum_war3_armor)
    if minimum ~= nil then reduced = math.max(minimum, reduced) end
    local pct = math.max(0, math.min(100, number(percentage_reduction))) / 100
    if reduced >= 0 then reduced = reduced * (1 - pct)
    else reduced = reduced * (1 + pct) end
    return reduced
end

function M.war3_positive_damage_multiplier(war3_armor)
    local armor = math.max(0, tonumber(war3_armor) or 0)
    return 1 / (1 + M.WAR3_POSITIVE_ARMOR_FACTOR * armor)
end

function M.war3_physical_damage_multiplier(war3_armor, ignore_pct)
    local armor = math.max(0, tonumber(war3_armor) or 0)
    local ignored = math.max(0, math.min(100, tonumber(ignore_pct) or 0))
    return M.war3_positive_damage_multiplier(armor * (1 - ignored / 100))
end

function M.war3_physical_reduction_pct(war3_armor, ignore_pct)
    return 100 * (1 - M.war3_physical_damage_multiplier(
        war3_armor,
        ignore_pct
    ))
end

function M.dota_positive_damage_multiplier(dota_armor)
    local armor = math.max(0, tonumber(dota_armor) or 0)
    local reduction = M.DOTA_POSITIVE_ARMOR_NUMERATOR * armor
        / (M.DOTA_POSITIVE_ARMOR_BASE
            + M.DOTA_POSITIVE_ARMOR_DENOMINATOR * armor)
    return 1 - reduction
end

function M.monster_physical_damage_compensation(runtime_armor)
    local armor = tonumber(runtime_armor) or 0
    if armor <= 0 then return 1 end
    -- DamageFilter runs before native physical armor. Apply only the ratio
    -- between the requested War3 curve and the current Dota armor curve.
    local engine_multiplier = M.dota_positive_damage_multiplier(armor)
    if engine_multiplier <= 0 then return 1 end
    local target_multiplier = M.war3_positive_damage_multiplier(
        M.to_war3(armor)
    )
    return target_multiplier / engine_multiplier
end

function M.physical_armor_ignore_compensation(runtime_armor, ignore_pct,
        use_war3_curve)
    local armor = tonumber(runtime_armor) or 0
    if armor <= 0 then return 1 end
    local ignored = math.max(0, math.min(100, tonumber(ignore_pct) or 0))
    local engine_multiplier = M.dota_positive_damage_multiplier(armor)
    if engine_multiplier <= 0 then return 1 end
    local target_multiplier
    if use_war3_curve then
        local war3_armor = M.to_war3_modern(armor)
        if war3_armor == nil then return 1 end
        local effective_war3_armor = war3_armor * (1 - ignored / 100)
        target_multiplier = M.war3_positive_damage_multiplier(
            effective_war3_armor
        )
    else
        local effective_armor = armor * (1 - ignored / 100)
        target_multiplier = M.dota_positive_damage_multiplier(effective_armor)
    end
    return target_multiplier / engine_multiplier
end

return M
