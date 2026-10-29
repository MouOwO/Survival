-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_challenge_gear_quality_rules.csv
local M = {}
M.rows = {
    { rule_id = "archive_gear_early", min_wave = 1, max_wave = 49, weight_n = 6000, weight_r = 3000, weight_sr = 900, weight_ssr = 90, weight_ur = 10, enabled = true },
    { rule_id = "archive_gear_middle", min_wave = 50, max_wave = 99, weight_n = 4500, weight_r = 3500, weight_sr = 1600, weight_ssr = 350, weight_ur = 50, enabled = true },
    { rule_id = "archive_gear_high", min_wave = 100, max_wave = 199, weight_n = 2500, weight_r = 4000, weight_sr = 2500, weight_ssr = 900, weight_ur = 100, enabled = true },
    { rule_id = "archive_gear_peak", min_wave = 200, max_wave = 100000, weight_n = 1000, weight_r = 4000, weight_sr = 3500, weight_ssr = 1300, weight_ur = 200, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
