-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_daily_schedule.csv
local M = {}
M.rows = {
    { day_id = 1, item_ids = {"daily_growth_gem"}, item_counts = {"3"}, enabled = true },
    { day_id = 2, item_ids = {"daily_regen_shard"}, item_counts = {"3"}, enabled = true },
    { day_id = 3, item_ids = {"daily_attribute_gem"}, item_counts = {"3"}, enabled = true },
    { day_id = 4, item_ids = {"daily_attack_shard"}, item_counts = {"3"}, enabled = true },
    { day_id = 5, item_ids = {"daily_health_gem", "daily_wood_gem"}, item_counts = {"3", "3"}, enabled = true },
    { day_id = 6, item_ids = {"daily_block_shard", "daily_attribute_shard"}, item_counts = {"3", "3"}, enabled = true },
    { day_id = 7, item_ids = {"daily_gold_gem"}, item_counts = {"3"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["day_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
