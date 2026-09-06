-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_shadow_challenge_drop_rules.csv
local M = {}
M.rows = {
    { challenge_id = "shadow_1", source_boss_difficulty = "n1", drop_count = 2, pass_extra_count = 0, allow_duplicates = true, enabled = true, notes = "从工作簿虚空之影N1对应物品池独立随机2次，允许重复，最终固定2件。" },
    { challenge_id = "shadow_2", source_boss_difficulty = "n2", drop_count = 2, pass_extra_count = 0, allow_duplicates = true, enabled = true, notes = "从工作簿虚空之影N2对应物品池独立随机2次，允许重复，最终固定2件。" },
    { challenge_id = "shadow_3", source_boss_difficulty = "n3", drop_count = 2, pass_extra_count = 0, allow_duplicates = true, enabled = true, notes = "从工作簿虚空之影N3对应物品池独立随机2次，允许重复，最终固定2件。" },
    { challenge_id = "shadow_4", source_boss_difficulty = "n4", drop_count = 2, pass_extra_count = 1, allow_duplicates = true, enabled = true, notes = "沿用既有虚空之影4规则；基础2件，通行证额外1件。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["challenge_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
