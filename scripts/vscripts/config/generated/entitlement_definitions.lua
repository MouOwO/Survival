-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: entitlement_definitions.csv
local M = {}
M.rows = {
    { entitlement_id = "vip", display_name = "VIP英雄召唤权限", default_unlocked = false, test_cheat_name = "setvip", enabled = true, notes = "默认关闭；只有服务端验证通过的玩家档案或测试作弊指令可以授予VIP。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["entitlement_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
