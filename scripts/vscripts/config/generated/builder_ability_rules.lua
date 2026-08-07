-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: builder_ability_rules.csv
local M = {}
M.rows = {
    { ability_name = "ability_build_wall", building_id = "building_wall", visible_condition = "main_city_level>=0", purchasable_condition = "building_count(building_wall)<1", disable_after_built = true, client_block_when_disabled = true, disabled_text = "城墙已建造", notes = "客户端置灰且不发送；服务器再次验证。" },
    { ability_name = "ability_build_main_city", building_id = "building_main_city", visible_condition = "main_city_level>=0", purchasable_condition = "building_count(building_main_city)<1", disable_after_built = true, client_block_when_disabled = true, disabled_text = "主城已建造", notes = "客户端置灰且不发送；服务器再次验证。" },
    { ability_name = "ability_build_arrow_tower", building_id = "building_arrow_tower", visible_condition = "main_city_built==true", purchasable_condition = "true", disable_after_built = false, client_block_when_disabled = true },
    { ability_name = "ability_build_gold_mine", building_id = "building_gold_mine", visible_condition = "main_city_level>=3", purchasable_condition = "building_count(building_gold_mine)<5", disable_after_built = true, client_block_when_disabled = true, disabled_text = "主城未到3级或金矿已达5座上限" },
    { ability_name = "ability_build_hero_altar", building_id = "building_hero_altar", visible_condition = "main_city_level>=3", purchasable_condition = "building_count(building_hero_altar)<1", disable_after_built = true, client_block_when_disabled = true, disabled_text = "主城未到3级或祭坛已建造" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["ability_name"]
    if key ~= nil then M.by_id[key] = row end
end
return M
