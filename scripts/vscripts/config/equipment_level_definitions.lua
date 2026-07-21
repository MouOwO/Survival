-- 每个阶段都是完整效果快照；消费者不得从前级隐式继承。
local M = {}

local function effects(values)
    local result = {}
    for effect_type, value in pairs(values) do
        result[#result + 1] = { effect_type = effect_type, value = value }
    end
    table.sort(result, function(a, b) return a.effect_type < b.effect_type end)
    return result
end

local function row(id, level, progression, values)
    return { content_id = id, level = level, progression = progression, effects = effects(values), snapshot_complete = true, enabled = true }
end

M.rows = {
    row("weapon_growth_sword_01", 1, { type = "normal_attack_count", required = 200 }, { attack_gain_on_attack = 1 }),
    row("weapon_growth_sword_02", 2, { type = "normal_attack_count", required = 200 }, { attack_gain_on_attack = 2 }),
    row("weapon_growth_sword_03", 3, { type = "normal_attack_count", required = 200 }, { attack_gain_on_attack = 3 }),
    row("weapon_growth_sword_04", 4, { type = "normal_attack_count", required = 200 }, { attack_gain_on_attack = 4 }),
    row("weapon_growth_sword_max", 5, nil, { attack_gain_on_attack = 5 }),

    row("weapon_frost_blade_01", 1, { type = "normal_attack_count", required = 200 }, { attack_gain_on_attack = 6, lifesteal_pct = 50 }),
    row("weapon_frost_blade_02", 2, { type = "normal_attack_count", required = 300 }, { attack_gain_on_attack = 7, lifesteal_pct = 50 }),
    row("weapon_frost_blade_03", 3, { type = "normal_attack_count", required = 400 }, { attack_gain_on_attack = 8, lifesteal_pct = 50 }),
    row("weapon_frost_blade_04", 4, { type = "normal_attack_count", required = 500 }, { attack_gain_on_attack = 9, lifesteal_pct = 50 }),
    row("weapon_frost_blade_max", 5, nil, { attack_gain_on_attack = 10, lifesteal_pct = 50 }),

    row("weapon_ice_blade_01", 1, { type = "valid_enemy_kill_count", required = 200, attribution = "owner_player" }, { attack_gain_on_player_kill = 12, lifesteal_pct = 50, critical_chance_pct = 50, critical_multiplier = 2, all_attributes_flat = 2000 }),
    row("weapon_ice_blade_02", 2, { type = "valid_enemy_kill_count", required = 300, attribution = "owner_player" }, { attack_gain_on_player_kill = 13, lifesteal_pct = 50, critical_chance_pct = 50, critical_multiplier = 2, all_attributes_flat = 2500 }),
    row("weapon_ice_blade_03", 3, { type = "valid_enemy_kill_count", required = 400, attribution = "owner_player" }, { attack_gain_on_player_kill = 14, lifesteal_pct = 50, critical_chance_pct = 50, critical_multiplier = 2, all_attributes_flat = 3000 }),
    row("weapon_ice_blade_04", 4, { type = "valid_enemy_kill_count", required = 500, attribution = "owner_player" }, { attack_gain_on_player_kill = 15, lifesteal_pct = 50, critical_chance_pct = 50, critical_multiplier = 5, all_attributes_flat = 3500 }),
    row("weapon_ice_blade_max", 5, nil, { attack_gain_on_player_kill = 16, lifesteal_pct = 50, critical_chance_pct = 50, critical_multiplier = 5, all_attributes_flat = 5000 }),

    row("equipment_attack_gloves_01", 1, nil, { attack_speed_pct = 20 }),
    row("equipment_attack_gloves_02", 2, nil, { attack_speed_pct = 40 }),
    row("equipment_attack_gloves_03", 3, nil, { attack_speed_pct = 60 }),
    row("equipment_attack_gloves_04", 4, nil, { attack_speed_pct = 80 }),
    row("equipment_attack_gloves_max", 5, nil, { attack_speed_pct = 100 }),

    row("equipment_burning_blade_01", 1, nil, { attack_flat = 1000 }),
    row("equipment_burning_blade_02", 2, nil, { attack_flat = 2000 }),
    row("equipment_burning_blade_03", 3, nil, { attack_flat = 4000 }),
    row("equipment_burning_blade_04", 4, nil, { attack_flat = 6000 }),
    row("equipment_burning_blade_max", 5, nil, { attack_flat = 8000 }),

    row("equipment_iron_armor_01", 1, nil, { armor_flat = 10, health_flat = 5000 }),
    row("equipment_iron_armor_02", 2, nil, { armor_flat = 30, health_flat = 10000 }),
    row("equipment_iron_armor_03", 3, nil, { armor_flat = 50, health_flat = 20000 }),
    row("equipment_iron_armor_04", 4, nil, { armor_flat = 70, health_flat = 30000 }),
    row("equipment_iron_armor_max", 5, nil, { armor_flat = 100, health_flat = 50000 }),

    row("equipment_infernal_armor_01", 1, nil, { attack_flat = 20000, attack_speed_pct = 150, health_flat = 100000, armor_flat = 150, aura_attribute_damage = { radius = 200, interval = 1, multiplier = 1 } }),
    row("equipment_infernal_armor_02", 2, nil, { attack_flat = 30000, attack_speed_pct = 200, health_flat = 200000, armor_flat = 200, aura_attribute_damage = { radius = 200, interval = 1, multiplier = 1 } }),
    row("equipment_infernal_armor_03", 3, nil, { attack_flat = 50000, attack_speed_pct = 250, health_flat = 300000, armor_flat = 250, aura_attribute_damage = { radius = 200, interval = 1, multiplier = 1 } }),
    row("equipment_infernal_armor_04", 4, nil, { attack_flat = 70000, attack_speed_pct = 300, health_flat = 500000, armor_flat = 300, aura_attribute_damage = { radius = 200, interval = 1, multiplier = 1 } }),
    row("equipment_infernal_armor_max", 5, nil, { attack_flat = 100000, attack_speed_pct = 400, health_flat = 800000, armor_flat = 400, aura_attribute_damage = { radius = 200, interval = 1, multiplier = 1 } }),
}

-- 完整阶段快照；史诗+7源数值缺失，保留ID但关闭，绝不外推。
local epic_attack = { 200000, 250000, 300000, 350000, 400000, 450000, 500000 }
local epic_health = { 800000, 850000, 900000, 1000000, 1000000, 1000000, 1000000 }
local epic_armor = { 500, 550, 600, 650, 700, 750, 800 }
local epic_attr = { 8000, 10000, 12000, 15000, 18000, 20000, 25000 }
local function endgame_effects(attack, health, armor, attributes, source)
    return effects({ attack_flat = attack, attack_speed_pct = 400, lifesteal_pct = 100, health_flat = health, armor_flat = armor, all_attributes_flat = attributes,
        aura_attribute_damage = { range = 200, multiplier = 5, internal_cooldown = 1, stacking = "single_aura_per_source", source = source },
        attack_gain_on_attack = 20, attributes_gain_on_attack = 5,
        proc_attribute_damage = { probability = 10, range = 500, multiplier = 50, internal_cooldown = 0, stacking = "independent_proc_per_source", source = source } })
end
for stage = 0, 7 do
    local known = stage <= 6
    M.rows[#M.rows + 1] = { content_id = string.format("weapon_epic_icefire_%02d", stage), level = stage, enabled = known,
        review_status = known and "needs_confirmation" or "unknown_disabled", snapshot_complete = true,
        progression = stage < 7 and { type = "seven_sins_stage", required = 1 } or nil,
        effects = known and endgame_effects(epic_attack[stage + 1], epic_health[stage + 1], epic_armor[stage + 1], epic_attr[stage + 1], "epic_icefire") or {} }
end
local legend_attack = { 600000, 700000, 800000, 900000, 1000000, 1100000, 1200000, 1300000, 1400000, 1500000, 2000000 }
local legend_health = { 1000000, 1000000, 1000000, 1000000, 1000000, 1100000, 1200000, 1300000, 1400000, 1500000, 2000000 }
local legend_attr = { 30000, 50000, 100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000 }
for stage = 0, 10 do
    M.rows[#M.rows + 1] = { content_id = string.format("weapon_legend_abyss_%02d", stage), level = stage, enabled = true,
        review_status = "needs_confirmation", snapshot_complete = true,
        progression = stage < 10 and { type = "ten_commandments_stage", required = 1 } or nil,
        effects = endgame_effects(legend_attack[stage + 1], legend_health[stage + 1], 850, legend_attr[stage + 1], "legend_abyss") }
end

M.by_id = {}
for _, definition in ipairs(M.rows) do M.by_id[definition.content_id] = definition end

return M
