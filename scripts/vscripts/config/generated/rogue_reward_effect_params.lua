-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: rogue_reward_effect_params.csv
local M = {}
M.rows = {
    { param_id = "frozen_wall_pct", effect_id = "frozen_wall_slow", param_name = "value", value_type = "number", number_value = -15, enabled = true },
    { param_id = "frozen_wall_target", effect_id = "frozen_wall_slow", param_name = "target_group", value_type = "string", string_value = "wave_and_building_challenge", enabled = true },
    { param_id = "recruit_training_pct", effect_id = "recruit_training_attack", param_name = "value", value_type = "number", number_value = 100, enabled = true },
    { param_id = "recruit_training_level", effect_id = "recruit_training_attack", param_name = "level_exclusive_max", value_type = "number", number_value = 5, enabled = true },
    { param_id = "recruit_training_ids", effect_id = "recruit_training_attack", param_name = "target_record_ids", value_type = "string", string_value = "arrow_tower_lv01|arrow_tower_lv02|arrow_tower_lv03|arrow_tower_lv04", enabled = true },
    { param_id = "ion_shield_pct", effect_id = "ion_shield_cap", param_name = "value", value_type = "number", number_value = 20, enabled = true },
    { param_id = "weakening_orb_pct", effect_id = "weakening_orb_boss", param_name = "value", value_type = "number", number_value = -50, enabled = true },
    { param_id = "weakening_boss_role", effect_id = "weakening_orb_boss", param_name = "boss_role", value_type = "string", string_value = "assault_boss", enabled = true },
    { param_id = "weakening_elite_role", effect_id = "weakening_orb_boss", param_name = "elite_role", value_type = "string", string_value = "wave_leader", enabled = true },
    { param_id = "divine_wish_count", effect_id = "divine_wish_policy", param_name = "count", value_type = "number", number_value = 3, enabled = true },
    { param_id = "tower_growth_pct", effect_id = "tower_growth_upgrade", param_name = "value", value_type = "number", number_value = 10, enabled = true },
    { param_id = "fortifications_pct", effect_id = "fortifications_attack_speed", param_name = "value", value_type = "number", number_value = 6, enabled = true },
    { param_id = "feast_multiplier", effect_id = "feast_wall_health", param_name = "multiplier", value_type = "number", number_value = 2, enabled = true },
    { param_id = "boss_promise_pct", effect_id = "boss_promise_speed", param_name = "value", value_type = "number", number_value = 100, enabled = true },
    { param_id = "boss_promise_duration", effect_id = "boss_promise_speed", param_name = "duration_seconds", value_type = "number", number_value = 120, enabled = true },
    { param_id = "far_sighted_count", effect_id = "far_sighted_take_all", param_name = "choice_count", value_type = "number", number_value = 3, enabled = true },
    { param_id = "command_change_count", effect_id = "command_change_reroll", param_name = "count", value_type = "number", number_value = 1, enabled = true },
    { param_id = "infrastructure_maniac_count", effect_id = "infrastructure_maniac_upgrade", param_name = "count", value_type = "number", number_value = 3, enabled = true },
    { param_id = "gunpowder_splash_pct", effect_id = "gunpowder_splash_damage", param_name = "value", value_type = "number", number_value = 30, enabled = true },
    { param_id = "gunpowder_splash_stage", effect_id = "gunpowder_splash_damage", param_name = "target_stage_ids", value_type = "string", string_value = "piercing_ballista", enabled = true },
    { param_id = "radiant_sapling_pct", effect_id = "radiant_sapling_wood", param_name = "value", value_type = "number", number_value = 20, enabled = true },
    { param_id = "kick_when_down_pct", effect_id = "kick_when_down_damage", param_name = "value", value_type = "number", number_value = 50, enabled = true },
    { param_id = "tower_network_pct", effect_id = "tower_network_attack", param_name = "value_per_target", value_type = "number", number_value = 5, enabled = true },
    { param_id = "tower_network_cap", effect_id = "tower_network_attack", param_name = "max_value", value_type = "number", number_value = 50, enabled = true },
    { param_id = "fiscal_subsidy_value", effect_id = "fiscal_subsidy_gold", param_name = "value", value_type = "number", number_value = 10000, enabled = true },
    { param_id = "corrosive_shield_value", effect_id = "corrosive_shield_armor", param_name = "value", value_type = "number", number_value = -1, enabled = true },
    { param_id = "goblin_success_pct", effect_id = "goblin_duplicator_action", param_name = "success_chance_pct", value_type = "number", number_value = 49, enabled = true },
    { param_id = "lucky_watch_count", effect_id = "lucky_watch_cooldown", param_name = "count", value_type = "number", number_value = 3, enabled = true },
    { param_id = "nuclear_boss", effect_id = "nuclear_bomb_action", param_name = "exclude_boss", value_type = "boolean", boolean_value = true, enabled = true },
    { param_id = "nuclear_batch_size", effect_id = "nuclear_bomb_action", param_name = "batch_size", value_type = "number", number_value = 4, enabled = true },
    { param_id = "nuclear_batch_interval", effect_id = "nuclear_bomb_action", param_name = "batch_interval_seconds", value_type = "number", number_value = 0.05, enabled = true },
    { param_id = "bounty_order_count", effect_id = "bounty_order_rewards", param_name = "count", value_type = "number", number_value = 5, enabled = true },
    { param_id = "bounty_order_multiplier", effect_id = "bounty_order_rewards", param_name = "multiplier", value_type = "number", number_value = 2, enabled = true },
    { param_id = "high_morale_pct", effect_id = "high_morale_attack", param_name = "value", value_type = "number", number_value = 30, enabled = true },
    { param_id = "in_step_pct", effect_id = "in_step_attack", param_name = "value", value_type = "number", number_value = 10, enabled = true },
    { param_id = "construction_order_count", effect_id = "construction_order_action", param_name = "count", value_type = "number", number_value = 1, enabled = true },
    { param_id = "internship_count", effect_id = "internship_capacity", param_name = "value", value_type = "number", number_value = 2, enabled = true },
    { param_id = "internship_training_id", effect_id = "internship_capacity", param_name = "training_id", value_type = "string", string_value = "train_repairer_01", enabled = true },
    { param_id = "internship_wood_override", effect_id = "internship_capacity", param_name = "wood_cost_override", value_type = "number", number_value = 0, enabled = true, notes = "兼容配置契约；上限效果不读取此参数。" },
    { param_id = "internship_gold_override", effect_id = "internship_capacity", param_name = "gold_cost_override", value_type = "number", number_value = 0, enabled = true, notes = "兼容配置契约；上限效果不读取此参数。" },
    { param_id = "bloodthirst_burst", effect_id = "bloodthirst_lifesteal", param_name = "initial_value", value_type = "number", number_value = 100, enabled = true },
    { param_id = "bloodthirst_duration", effect_id = "bloodthirst_lifesteal", param_name = "burst.duration_seconds", value_type = "number", number_value = 60, enabled = true },
    { param_id = "bloodthirst_permanent", effect_id = "bloodthirst_lifesteal", param_name = "later_value", value_type = "number", number_value = 20, enabled = true },
    { param_id = "outsourcing_per_building", effect_id = "infrastructure_outsourcing_gold", param_name = "value_per_target", value_type = "number", number_value = 100, enabled = true },
    { param_id = "iron_fist_pct", effect_id = "iron_fist_armor", param_name = "value", value_type = "number", number_value = 40, enabled = true },
    { param_id = "training_dummy_duration", effect_id = "training_dummy_growth", param_name = "duration_seconds", value_type = "number", number_value = 30, enabled = true },
    { param_id = "training_dummy_attack", effect_id = "training_dummy_growth", param_name = "value", value_type = "number", number_value = 100, enabled = true },
    { param_id = "training_dummy_distance", effect_id = "training_dummy_growth", param_name = "distance", value_type = "number", number_value = 256, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["param_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
