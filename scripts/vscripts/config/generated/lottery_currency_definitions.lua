-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_currency_definitions.csv
local M = {}
M.rows = {
    { currency_id = "lottery_ticket", display_name = "普通抽奖券", acquisition_policy = "gameplay_and_purchase", commerce_sku = "lottery_ticket_single", client_visible = true, enabled = true, review_status = "ok", notes = "普通玩法及福利继续产出；商城直购3元/张，按权威商品配置发放。" },
    { currency_id = "special_lottery_ticket", display_name = "金色抽奖券", acquisition_policy = "external_purchase_only", client_visible = true, enabled = true, review_status = "ok", notes = "保留既有特殊券库存ID；用于修仙、龙骑和暑期宝箱；支付验签发放渠道不变。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["currency_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
