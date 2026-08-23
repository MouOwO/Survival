-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: blademaster_exclusive_runtime.csv
local M = {}
M.rows = {
    { config_id = "blademaster_exclusive", q_critical_chance_pct = 30, q_critical_damage_bonus_pct = 1500, q_radius = 600, w_proc_chance_pct = 10, w_clone_critical_damage_bonus_pct = 750, w_clone_permanent = true, e_proc_chance_pct = 10, e_duration = 3, e_tick_interval = 1, e_attribute_multiplier = 25, e_radius = 600, e_visual_radius = 600, r_attack_interval_reduction = 0.1, r_growth_interval = 150, r_growth_pct = 1, r_attack_multiplier = 3, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["config_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
