-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: entitlement_definitions.csv
local M = {}
M.rows = {
    { entitlement_id = "vip", display_name = "VIP英雄召唤权限", default_unlocked = true, test_cheat_name = "setvip", enabled = true, notes = "测试阶段默认VIP=true；正式发布时接入存档/平台权益并改回false。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["entitlement_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
