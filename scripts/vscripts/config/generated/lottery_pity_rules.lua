-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pity_rules.csv
local M = {}
M.rows = {
    { rule_id = "map_ssr_ten_pull", pool_id = "map", target_quality = "ssr", threshold = 10, trigger_mode = "batch_only", priority = 20, enabled = true, review_status = "ok", notes = "仅一次十连请求生效；未自然获得SSR或UR时固定补SSR；连续十次单抽不触发保底。" },
    { rule_id = "cultivation_ssr_ten_pull", pool_id = "cultivation", target_quality = "ssr", threshold = 10, trigger_mode = "batch_only", priority = 20, enabled = true, review_status = "ok", notes = "仅一次十连请求固定至少一件SSR；另有每池最多50抽UR保底，单抽与十连累计。" },
    { rule_id = "dragon_knight_ssr_ten_pull", pool_id = "dragon_knight", target_quality = "ssr", threshold = 10, trigger_mode = "batch_only", priority = 20, enabled = true, review_status = "ok", notes = "仅一次十连请求固定至少一件SSR；另有每池最多50抽UR保底，单抽与十连累计。" },
    { rule_id = "summer_ssr_ten_pull", pool_id = "summer", target_quality = "ssr", threshold = 10, trigger_mode = "batch_only", priority = 20, enabled = true, review_status = "ok", notes = "仅一次十连请求固定至少一件SSR；另有每池最多50抽UR保底，单抽与十连累计。" },
    { rule_id = "cultivation_ur_fifty", pool_id = "cultivation", target_quality = "ur", threshold = 50, trigger_mode = "consecutive_misses", priority = 30, enabled = true, review_status = "ok", notes = "本奖池连续49抽未出UR后第50抽必出；单抽十连累计，自然或保底UR均重置。" },
    { rule_id = "dragon_knight_ur_fifty", pool_id = "dragon_knight", target_quality = "ur", threshold = 50, trigger_mode = "consecutive_misses", priority = 30, enabled = true, review_status = "ok", notes = "本奖池连续49抽未出UR后第50抽必出；单抽十连累计，自然或保底UR均重置。" },
    { rule_id = "summer_ur_fifty", pool_id = "summer", target_quality = "ur", threshold = 50, trigger_mode = "consecutive_misses", priority = 30, enabled = true, review_status = "ok", notes = "本奖池连续49抽未出UR后第50抽必出；单抽十连累计，自然或保底UR均重置。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
