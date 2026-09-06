-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: entitlement_definitions.csv
local M = {}
M.rows = {
    { entitlement_id = "vip", display_name = "VIP英雄召唤权限", default_unlocked = false, test_cheat_name = "setvip", enabled = true, notes = "默认关闭；只有服务端验证通过的玩家档案或测试作弊指令可以授予VIP。" },
    { entitlement_id = "archive_pass", display_name = "虚空之影通行证", default_unlocked = false, enabled = true, notes = "仅支付后台验证购买后下发；最终BOSS额外掉落1件；可携带expires_at秒级时间戳。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["entitlement_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
