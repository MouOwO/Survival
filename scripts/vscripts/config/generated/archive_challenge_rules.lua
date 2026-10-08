-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_challenge_rules.csv
local M = {}
M.rows = {
    { rule_id = "default", building_unlock_difficulty = 1, building_spacing = 240, building_offset_y = 360, building_model = "models/survival_buildings/archive_challenge_01.vmdl", building_model_scale = 1, base_fragment_daily_limit = 20, pass_fragment_daily_limit = 40, cage_daily_limit = 30, pass_cage_daily_limit = 90, cage_drop_count = 1, pass_cage_extra_count = 1, day_timezone_offset = 28800, final_boss_shadow_drops_enabled = false, building_model_1 = "models/survival_buildings/archive_challenge_01.vmdl", building_model_2 = "models/survival_buildings/archive_challenge_02.vmdl", building_model_3 = "models/survival_buildings/archive_challenge_03.vmdl", phase_duration_seconds = 1800, building_anchor = "player_wall" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
