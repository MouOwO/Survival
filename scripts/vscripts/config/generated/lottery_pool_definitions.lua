-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_pool_definitions.csv
local M = {}
M.rows = {
    { pool_id = "map", display_name = "地图抽奖", description = "普通抽奖券 · 十连保底SSR", ticket_content_id = "lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "map", ui_order = 1, enabled = true, review_status = "ok", notes = "按用户截图限定30种道具，无UR；十连未自然获得SSR时固定补SSR；连续十次单抽不保底。", unlock_draws = 0 },
    { pool_id = "cultivation", display_name = "修仙宝箱", description = "普通抽奖券 · 地图宝箱累计开启100次解锁 · 十连保底SSR", ticket_content_id = "lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "normal", ui_order = 2, enabled = true, review_status = "needs_confirmation", notes = "解锁按地图宝箱累计开启次数计算；单抽计1次，十连计10次。", unlock_pool_id = "map", unlock_draws = 100 },
    { pool_id = "dragon_knight", display_name = "龙骑宝箱", description = "金色抽奖券 · 无前置解锁条件 · 十连至少UR", ticket_content_id = "special_lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "special", ui_order = 3, enabled = true, review_status = "needs_confirmation", notes = "持有足够金色抽奖券即可抽取，不依赖其他宝箱进度。", unlock_draws = 0 },
    { pool_id = "summer", display_name = "暑期宝箱", description = "金色抽奖券 · 无前置解锁条件 · 十连至少UR", ticket_content_id = "special_lottery_ticket", single_cost = 1, ten_cost = 10, pool_group = "special", ui_order = 4, enabled = true, review_status = "needs_confirmation", notes = "持有足够金色抽奖券即可抽取，不依赖其他宝箱进度。", unlock_draws = 0 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
