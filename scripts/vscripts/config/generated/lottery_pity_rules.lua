-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pity_rules.csv
local M = {}
M.rows = {
    { rule_id = "map_sr_ten_pull", pool_id = "map", target_quality = "sr", threshold = 10, trigger_mode = "batch_only", priority = 10, enabled = true, review_status = "ok", notes = "仅一次十连请求生效；连续十次单抽不触发保底。" },
    { rule_id = "cultivation_ur_ten_pull", pool_id = "cultivation", target_quality = "ur", threshold = 10, trigger_mode = "batch_only", priority = 30, enabled = true, review_status = "ok", notes = "仅一次十连请求生效；连续十次单抽不触发保底。" },
    { rule_id = "dragon_knight_ur_ten_pull", pool_id = "dragon_knight", target_quality = "ur", threshold = 10, trigger_mode = "batch_only", priority = 30, enabled = true, review_status = "ok", notes = "仅一次十连请求生效；连续十次单抽不触发保底。" },
    { rule_id = "summer_ur_ten_pull", pool_id = "summer", target_quality = "ur", threshold = 10, trigger_mode = "batch_only", priority = 30, enabled = true, review_status = "ok", notes = "仅一次十连请求生效；连续十次单抽不触发保底。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
