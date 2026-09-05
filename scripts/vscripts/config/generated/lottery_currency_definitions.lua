-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: lottery_currency_definitions.csv
local M = {}
M.rows = {
    { currency_id = "lottery_ticket", display_name = "地图抽奖券", acquisition_policy = "gameplay_reward", client_visible = true, enabled = true, review_status = "ok", notes = "普通地图玩法产出；不得通过付费接口冒充发放。" },
    { currency_id = "special_lottery_ticket", display_name = "特殊抽奖券", acquisition_policy = "external_purchase_only", client_visible = true, enabled = true, review_status = "needs_confirmation", notes = "仅允许支付后台验签后写入内容背包；正式SKU待支付平台确认。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["currency_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
