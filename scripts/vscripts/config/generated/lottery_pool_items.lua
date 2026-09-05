-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pool_items.csv
local M = {}
M.rows = {
    { membership_id = "map_all", pool_id = "map", item_id = "*", item_weight = 1, enabled = true, review_status = "ok", notes = "自动纳入全部已启用积分道具并按品质分组等权抽取。" },
    { membership_id = "cultivation_all", pool_id = "cultivation", item_id = "*", item_weight = 1, enabled = true, review_status = "needs_confirmation", notes = "特殊池暂时共用全部已启用积分道具。" },
    { membership_id = "dragon_knight_all", pool_id = "dragon_knight", item_id = "*", item_weight = 1, enabled = true, review_status = "needs_confirmation", notes = "特殊池暂时共用全部已启用积分道具。" },
    { membership_id = "summer_all", pool_id = "summer", item_id = "*", item_weight = 1, enabled = true, review_status = "needs_confirmation", notes = "特殊池暂时共用全部已启用积分道具。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["membership_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
