-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_endless_rules.csv
local M = {}
M.rows = {
    { rule_id = "default", monsters_per_wave = 5, time_limit_seconds = 60, score_block_size = 10, score_multiplier = 7, score_offset = -6, model_path = "models/heroes/nevermore/nevermore.vmdl", model_scale = 0.9, move_speed = 280, attack_speed = 1, attack_range = 160, magic_resistance = 0 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
