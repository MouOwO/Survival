-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_daily_rules.csv
local M = {}
M.rows = {
    { rule_id = "default", pass_entitlement_id = "archive_pass", duration_days = 30, price_text = "价格待配置", purchase_enabled = false, makeup_days = 30, timezone_hours = 8, pass_milestones = {"7", "14", "21"}, pass_item_ids = {"daily_wealth_talisman", "daily_ancient_tree", "daily_forest_origin"} },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
