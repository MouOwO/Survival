local generated = require("config/generated/technology_definitions")

local M = { technologies = {}, by_id = {}, by_legacy_group = {} }

local IDENTITIES = {
    { id = "RS-01", group = "lumberjack_speed", building = "research_lab" },
    { id = "RS-02", group = "advanced_lumberjack_speed", building = "research_lab" },
    { id = "RS-03", group = "lumberjack_crit", building = "research_lab" },
    { id = "RS-04", group = "lumberjack_efficiency", building = "research_lab" },
    { id = "RS-05", group = "advanced_lumberjack_efficiency", building = "research_lab" },
    { id = "RS-06", group = "tower_attack", building = "research_lab" },
    { id = "RS-07", group = "advanced_tower_attack", building = "research_lab" },
    { id = "RS-08", group = "wall_health", building = "research_lab" },
    { id = "RS-09", group = "advanced_wall_health", building = "research_lab" },
    { id = "ARS-01", group = "researcher_lumberjack_attack_growth", building = "advanced_research_lab" },
    { id = "ARS-02", group = "researcher_lumberjack_armor_reduction", building = "advanced_research_lab" },
    { id = "ARS-03", group = "researcher_super_wall_health", building = "advanced_research_lab" },
    { id = "ARS-04", group = "researcher_super_wall_armor", building = "advanced_research_lab" },
    { id = "ARS-05", group = "researcher_super_tower_attack", building = "advanced_research_lab" },
    { id = "ARS-06", group = "researcher_super_tower_range", building = "advanced_research_lab" },
    { id = "ARS-07", group = "researcher_super_tower_crit", building = "advanced_research_lab" },
    { id = "ARS-08", group = "researcher_hero_final_damage", building = "advanced_research_lab" },
    { id = "ARS-09", group = "researcher_hero_armor_reduction", building = "advanced_research_lab" },
    { id = "ARS-10", group = "researcher_hero_attack", building = "advanced_research_lab" },
}

local EFFECT_RULES = {
    lumberjack_attack_speed_pct = {
        { key = "lumberjack_attack_speed_pct", scale = 0.01 },
    },
    lumberjack_attack_interval_flat = {
        { key = "lumberjack_attack_interval_reduction" },
    },
    lumberjack_wood_per_hit = {
        { key = "lumberjack_wood_per_gather_flat" },
    },
    lumberjack_wood_per_hit_advanced = {
        { key = "lumberjack_wood_per_gather_advanced_flat" },
    },
    lumberjack_critical_chance_pct = {
        { key = "lumberjack_wood_crit_chance_pct", scale = 0.01 },
    },
    tower_attack_flat = {
        { key = "tower_attack_flat" },
    },
    tower_attack_flat_advanced = {
        { key = "tower_attack_advanced_flat" },
    },
    wall_health_pct = {
        { key = "wall_health_pct", scale = 0.01 },
    },
    wall_health_pct_advanced = {
        { key = "wall_health_advanced_pct", scale = 0.01 },
    },
    lumberjack_attack_growth = {
        { key = "lumberjack_attack_growth_per_hit" },
    },
    lumberjack_attack_armor_reduction = {
        { key = "tree_armor_shred_per_hit" },
    },
    super_wall_health_pct = {
        { key = "wall_health_super_pct", scale = 0.01 },
    },
    super_wall_armor_flat = {
        { key = "wall_armor_flat" },
    },
    super_tower_attack_flat = {
        { key = "tower_attack_super_flat" },
    },
    super_tower_attack_range = {
        { key = "tower_attack_range_flat" },
    },
    super_tower_crit_pct = {
        { key = "tower_crit_chance_pct", scale = 0.01 },
        { key = "tower_attack_bonus_pct", scale = 0.01 },
        { key = "hero_crit_chance_pct", scale = 0.01 },
        { key = "hero_attack_bonus_pct", scale = 0.01 },
    },
    hero_final_damage_pct = {
        { key = "hero_final_damage_pct", scale = 0.01 },
    },
    hero_attack_armor_reduction = {
        { key = "hero_armor_shred_flat" },
    },
    hero_attack_flat = {
        { key = "hero_attack_flat" },
    },
}

local ACCUMULATED_GROUPS = { advanced_lumberjack_speed = true }
local rows_by_group = {}
local generated_by_id = {}

for _, row in ipairs(generated.rows or {}) do
    generated_by_id[row.technology_id] = row
    if row.enabled ~= false then
        local group = tostring(row.technology_group or "")
        local level = tonumber(row.level)
        if group ~= "" and level and level > 0 then
            rows_by_group[group] = rows_by_group[group] or {}
            rows_by_group[group][level] = row
        end
    end
end

local function scaled(value, rule)
    return (tonumber(value) or 0) * (tonumber(rule.scale) or 1)
end

local function effect_values(rows, maximum, rule)
    local values = {}
    local display_values = {}
    local running = 0
    local display_running = 0
    for level = 1, maximum do
        local row = rows[level]
        local value = scaled(row and row.effect_value, rule)
        local display_value = scaled(
            row and (row.war3_effect_value or row.effect_value),
            rule
        )
        if ACCUMULATED_GROUPS[row and row.technology_group] then
            running = running + value
            display_running = display_running + display_value
            values[level] = running
            display_values[level] = display_running
        else
            values[level] = value
            display_values[level] = display_value
        end
    end
    return values, display_values
end

for _, identity in ipairs(IDENTITIES) do
    local rows = rows_by_group[identity.group] or {}
    local first = rows[1]
    assert(first, "missing generated research technology group: " .. identity.group)
    local maximum = 0
    for level, _ in pairs(rows) do
        if level > maximum then maximum = level end
    end
    local definition = {
        tech_id = identity.id,
        display_name = tostring(first.display_name or identity.group)
            :gsub("%s+Lv%.%d+$", ""),
        building_id = identity.building,
        max_level = maximum,
        legacy_group = identity.group,
        generated_rows = rows,
        prerequisite = {
            tech_id = nil,
            required_level = 0,
            reincarnation_level = tonumber(first.required_rebirth_level) or 0,
        },
        effects = {},
    }
    local rules = EFFECT_RULES[first.effect_type] or {}
    for _, rule in ipairs(rules) do
        local values, display_values = effect_values(rows, maximum, rule)
        definition.effects[#definition.effects + 1] = {
            key = rule.key,
            value_per_level = scaled(first.value_per_level, rule),
            display_value_per_level = scaled(
                first.war3_value_per_level or first.value_per_level,
                rule
            ),
            values_by_level = values,
            display_values_by_level = display_values,
        }
    end
    M.technologies[#M.technologies + 1] = definition
    M.by_id[definition.tech_id] = definition
    M.by_legacy_group[definition.legacy_group] = definition
end

for _, definition in ipairs(M.technologies) do
    local first = definition.generated_rows[1]
    local prerequisite_row = generated_by_id[first.prerequisite_id]
    local prerequisite = prerequisite_row
        and M.by_legacy_group[prerequisite_row.technology_group] or nil
    local required_level = tonumber(prerequisite_row and prerequisite_row.level) or 0
    if not prerequisite then
        prerequisite = M.by_legacy_group[first.unlock_technology_group]
        required_level = tonumber(first.unlock_required_level) or 0
    end
    if prerequisite and required_level > 0 then
        definition.prerequisite.tech_id = prerequisite.tech_id
        definition.prerequisite.required_level = required_level
    end
end

function M.cost_for_level(definition, target_level)
    local row = definition and definition.generated_rows
        and definition.generated_rows[target_level] or nil
    if not row then return nil end
    return {
        gold = tonumber(row.gold_cost) or 0,
        wood = tonumber(row.wood_cost) or 0,
    }
end

function M.effect_value(effect, level, display)
    level = math.max(0, math.floor(tonumber(level) or 0))
    if level == 0 or not effect then return 0 end
    local values = display and effect.display_values_by_level
        or effect.values_by_level
    return tonumber(values and values[level]) or 0
end

function M.effect_per_level(effect, display)
    if not effect then return 0 end
    return tonumber(display and effect.display_value_per_level
        or effect.value_per_level) or 0
end

return M