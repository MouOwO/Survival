-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: shop_aggregation_rules.csv
local M = {}
M.rows = {
    { source_id = "weapon", module_name = "weapon_definitions", content_type = "weapon", id_field = "content_id", name_field = "content_id", description_field = "description", category_default = "weapon", wood_cost_field = "wood_cost", gold_cost_field = "gold_cost", grant_type_default = "virtual_item", icon_type_default = "item", enabled = true, notes = "wood_cost或gold_cost任一大于0时进入商店；shop_enabled=0仍显示但置灰。" },
    { source_id = "item", module_name = "item_definitions", content_type = "item", id_field = "content_id", name_field = "content_id", description_field = "description", category_default = "item", wood_cost_field = "wood_cost", gold_cost_field = "gold_cost", grant_type_default = "virtual_item", icon_type_default = "item", enabled = true, notes = "包含材料、消耗品、BUFF类项目。" },
    { source_id = "technology", module_name = "technology_definitions", content_type = "technology", id_field = "technology_id", name_field = "technology_id", description_field = "notes", category_default = "technology", wood_cost_field = "wood_cost", gold_cost_field = "gold_cost", grant_type_default = "technology_level", icon_type_default = "ability", enabled = true, notes = "按科技等级行展示；前置科技由requires_content_id验证。" },
    { source_id = "challenge", module_name = "challenge_definitions", content_type = "challenge", id_field = "challenge_id", name_field = "name", description_field = "description", category_default = "challenge", wood_cost_field = "wood_cost", gold_cost_field = "gold_cost", grant_type_default = "start_encounter", icon_type_default = "item", enabled = true, notes = "未配置encounter_id时显示但置灰。" },
    { source_id = "rebirth", module_name = "rebirth_challenges", content_type = "rebirth", id_field = "challenge_id", name_field = "name", description_field = "description", category_default = "rebirth", wood_cost_field = "wood_cost", gold_cost_field = "gold_cost", grant_type_default = "start_encounter", icon_type_default = "item", enabled = true, notes = "一至十转直接映射MonsterEncounters。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["source_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
