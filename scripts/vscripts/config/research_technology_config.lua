local M = { technologies = {}, by_id = {}, by_legacy_group = {} }

local function prerequisite(tech_id, required_level, reincarnation_level)
    return {
        tech_id = tech_id,
        required_level = required_level or 0,
        reincarnation_level = reincarnation_level or 0,
    }
end

local function effect(key, value_per_level, mode)
    return { key = key, value_per_level = value_per_level, mode = mode }
end

local function technology(id, name, building, max_level, legacy_group,
        gold_base, gold_step, wood_base, wood_step, required, effects)
    return {
        tech_id = id,
        display_name = name,
        building_id = building,
        max_level = max_level,
        legacy_group = legacy_group,
        cost = {
            gold_base = gold_base,
            gold_step = gold_step,
            wood_base = wood_base,
            wood_step = wood_step,
        },
        prerequisite = required or prerequisite(),
        effects = effects,
    }
end

M.technologies = {
    technology("RS-01", "伐木工攻速", "research_lab", 10,
        "lumberjack_speed", 0, 0, 200, 400, prerequisite(), {
            effect("lumberjack_attack_speed_pct", 0.05),
        }),
    technology("RS-02", "高级伐木工攻速", "research_lab", 30,
        "advanced_lumberjack_speed", 1000, 1000, 5000, 1000,
        prerequisite("RS-01", 5), {
            effect("lumberjack_attack_interval_reduction", -0.01),
        }),
    technology("RS-03", "伐木工暴击", "research_lab", 10,
        "lumberjack_crit", 0, 2000, 500, 5000, prerequisite(), {
            effect("lumberjack_wood_crit_chance_pct", 0.03),
        }),
    technology("RS-04", "伐木效率", "research_lab", 20,
        "lumberjack_efficiency", 0, 0, 200, 300, prerequisite(), {
            effect("lumberjack_wood_per_gather_flat", 1),
        }),
    technology("RS-05", "高级伐木效率", "research_lab", 30,
        "advanced_lumberjack_efficiency", 1000, 500, 5000, 1000,
        prerequisite("RS-04", 10), {
            effect("lumberjack_wood_per_gather_advanced_flat", 3),
        }),
    technology("RS-06", "防御塔强化", "research_lab", 10,
        "tower_attack", 0, 0, 300, 200, prerequisite(), {
            effect("tower_attack_flat", 200),
        }),
    technology("RS-07", "高级防御塔强化", "research_lab", 20,
        "advanced_tower_attack", 1000, 500, 0, 0,
        prerequisite("RS-06", 10), {
            effect("tower_attack_advanced_flat", 1000),
        }),
    technology("RS-08", "墙强化", "research_lab", 10,
        "wall_health", 0, 0, 200, 300, prerequisite(), {
            effect("wall_health_pct", 0.15),
        }),
    technology("RS-09", "高级墙强化", "research_lab", 20,
        "advanced_wall_health", 1000, 500, 0, 0,
        prerequisite("RS-08", 10), {
            effect("wall_health_advanced_pct", 0.30),
        }),
    technology("ARS-01", "伐木工攻击成长", "advanced_research_lab", 30,
        "researcher_lumberjack_attack_growth", 30000, 10000, 0, 0,
        prerequisite(), {
            effect("lumberjack_attack_growth_per_hit", 2),
            effect("lumberjack_wood_per_gather_growth_flat", 5),
        }),
    technology("ARS-02", "伐木工攻击减甲", "advanced_research_lab", 30,
        "researcher_lumberjack_armor_reduction", 20000, 5000, 0, 0,
        prerequisite(), {
            effect("war3_tree_armor_shred_per_hit", -0.1),
            effect("minimum_war3_tree_armor", 100, "constant"),
        }),
    technology("ARS-03", "超级墙强化", "advanced_research_lab", 30,
        "researcher_super_wall_health", 30000, 20000, 100000, 30000,
        prerequisite("RS-09", 10), {
            effect("wall_health_super_pct", 0.60),
            effect("wall_health_bonus_pct", 0.05),
        }),
    technology("ARS-04", "超级墙护甲强化", "advanced_research_lab", 30,
        "researcher_super_wall_armor", 30000, 20000, 100000, 30000,
        prerequisite("RS-09", 10), {
            effect("war3_wall_armor_flat", 10),
            effect("wall_health_bonus_pct", 0.05),
        }),
    technology("ARS-05", "超级防御塔强化", "advanced_research_lab", 30,
        "researcher_super_tower_attack", 30000, 20000, 100000, 30000,
        prerequisite("RS-07", 10), {
            effect("tower_attack_super_flat", 30000),
        }),
    technology("ARS-06", "超级防御塔攻击范围", "advanced_research_lab", 30,
        "researcher_super_tower_range", 30000, 20000, 100000, 30000,
        prerequisite("RS-07", 10), {
            effect("tower_attack_range_flat", 30),
        }),
    technology("ARS-07", "超级防御塔暴击", "advanced_research_lab", 23,
        "researcher_super_tower_crit", 1000, 20000, 300000, 30000,
        prerequisite("RS-07", 10), {
            effect("tower_crit_chance_pct", 0.005),
            effect("tower_attack_bonus_pct", 0.005),
            effect("hero_crit_chance_pct", 0.005),
            effect("hero_attack_bonus_pct", 0.005),
        }),
    technology("ARS-08", "英雄最终伤害", "advanced_research_lab", 19,
        "researcher_hero_final_damage", 10000, 10000, 50000, 50000,
        prerequisite(nil, 0, 3), {
            effect("hero_final_damage_pct", 0.01),
        }),
    technology("ARS-09", "英雄攻击减甲", "advanced_research_lab", 19,
        "researcher_hero_armor_reduction", 10000, 10000, 50000, 50000,
        prerequisite(nil, 0, 3), {
            effect("war3_hero_armor_shred_flat", 0.5),
        }),
    technology("ARS-10", "英雄攻击", "advanced_research_lab", 19,
        "researcher_hero_attack", 10000, 10000, 50000, 50000,
        prerequisite(nil, 0, 3), {
            effect("hero_attack_bonus_pct", 0.02),
        }),
}

for _, definition in ipairs(M.technologies) do
    M.by_id[definition.tech_id] = definition
    M.by_legacy_group[definition.legacy_group] = definition
end

function M.cost_for_level(definition, target_level)
    if not definition or target_level < 1
        or target_level > definition.max_level then return nil end
    return {
        gold = definition.cost.gold_base
            + (target_level - 1) * definition.cost.gold_step,
        wood = definition.cost.wood_base
            + (target_level - 1) * definition.cost.wood_step,
    }
end

return M