-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_currency_definitions.csv
local M = {}
M.rows = {
    { currency_id = "lottery_ticket", display_name = "普通抽奖券", acquisition_policy = "gameplay_reward", client_visible = true, enabled = true, review_status = "ok", notes = "普通地图玩法产出；不得通过付费接口冒充发放。" },
    { currency_id = "special_lottery_ticket", display_name = "金色抽奖券", acquisition_policy = "external_purchase_only", client_visible = true, enabled = true, review_status = "ok", notes = "保留既有特殊券库存ID；用于第三、第四宝箱；支付验签发放渠道不变。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["currency_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
