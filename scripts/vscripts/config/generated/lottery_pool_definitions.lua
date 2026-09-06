-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pool_definitions.csv
local M = {}
M.rows = {
    { pool_id = "map", display_name = "地图抽奖", description = "N/R/SR/SSR/UR综合奖池 · 十连保底SR", ticket_content_id = "lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "map", ui_order = 1, enabled = true, review_status = "ok", notes = "UR基础概率0.1%；保底补位固定为SR且不会提升为UR；连续十次单抽不保底。" },
    { pool_id = "cultivation", display_name = "修仙宝箱", description = "特殊奖池 · 十连至少UR", ticket_content_id = "special_lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "special", ui_order = 2, enabled = true, review_status = "needs_confirmation", notes = "当前与其他特殊池共用联调道具；仅直接十连触发至少UR。" },
    { pool_id = "dragon_knight", display_name = "龙骑宝箱", description = "特殊奖池 · 十连至少UR", ticket_content_id = "special_lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "special", ui_order = 3, enabled = true, review_status = "needs_confirmation", notes = "当前与其他特殊池共用联调道具；仅直接十连触发至少UR。" },
    { pool_id = "summer", display_name = "暑期宝箱", description = "特殊奖池 · 十连至少UR", ticket_content_id = "special_lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "special", ui_order = 4, enabled = true, review_status = "needs_confirmation", notes = "当前与其他特殊池共用联调道具；仅直接十连触发至少UR。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
