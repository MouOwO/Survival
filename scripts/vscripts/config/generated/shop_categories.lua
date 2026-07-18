-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: shop_categories.csv
local M = {}
M.rows = {
    { category_id = "weapon", name = "武器与装备", sort_order = 10, visible_condition = "altar_used==true", enabled = true, description = "武器、护甲、饰品和可重复升级装备。" },
    { category_id = "item", name = "道具与材料", sort_order = 20, visible_condition = "altar_used==true", enabled = true, description = "消耗品、BUFF道具与合成材料。" },
    { category_id = "technology", name = "科技与服务", sort_order = 30, visible_condition = "altar_used==true", enabled = true, description = "科技升级和一次性服务。" },
    { category_id = "challenge", name = "挑战商店", sort_order = 40, visible_condition = "altar_used==true", enabled = true, description = "原建筑表中的挑战商店内容迁入此分栏。" },
    { category_id = "rebirth", name = "转职挑战", sort_order = 50, visible_condition = "altar_used==true", enabled = true, description = "原建筑表中的转升挑战内容迁入此分栏。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["category_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
