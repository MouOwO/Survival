-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: monkey_king_exclusive_runtime.csv
local M = {}
M.rows = {
    { config_id = "monkey_king_exclusive", q_proc_chance_pct = 10, q_length = 1200, q_total_width = 200, q_attribute_multiplier = 30, q_max_health_pct = 10, q_max_health_hit_limit = 3, w_critical_damage_pct = 2000, w_attack_interval_reduction = 0.1, w_growth_interval = 60, w_growth_pct = 2, w_clone_respawn_delay = 1, w_clone_war3_armor = 10, w_clone_critical_damage_bonus_pct = 1000, w_clone_permanent = true, e_critical_chance_pct = 20, e_attack_multiplier = 3, e_attribute_multiplier = 5, r_cooldown = 0, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["config_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
