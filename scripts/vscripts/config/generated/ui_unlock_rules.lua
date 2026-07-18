-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: ui_unlock_rules.csv
local M = {}
M.rows = {
    { rule_id = "shop_root_visible", condition = "altar_used==true", description = "英雄祭坛完成选择/使用后显示商店UI。", enabled = true },
    { rule_id = "shop_category_challenge", condition = "altar_used==true", description = "显示挑战商店分栏。", enabled = true },
    { rule_id = "shop_category_rebirth", condition = "altar_used==true", description = "显示转职挑战分栏。", enabled = true },
    { rule_id = "ability_build_wall_enabled", condition = "building_count(building_wall)<1", description = "建造一次后客户端置灰。", enabled = true },
    { rule_id = "ability_build_main_city_enabled", condition = "building_count(building_main_city)<1", description = "建造一次后客户端置灰。", enabled = true },
    { rule_id = "ability_build_hero_altar_enabled", condition = "main_city_level>=3 and building_count(building_hero_altar)<1", description = "主城3级解锁祭坛。", enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
