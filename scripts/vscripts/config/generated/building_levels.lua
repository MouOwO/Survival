-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: building_levels.csv
local M = {}
M.rows = {
    { level_id = "building_main_city_lv01", building_id = "building_main_city", level = 1, wood_cost = 0, gold_cost = 0, population_add = 10, prerequisite_text = "城墙", unlock_text = "解锁研究所、农场LV1、箭塔、挑战建筑（城墙、箭塔加成、金币、伐木效率挑战BOSS）", enabled = true, source = "建筑/行4" },
    { level_id = "building_main_city_lv02", building_id = "building_main_city", level = 2, wood_cost = 600, gold_cost = 0, population_add = 5, prerequisite_text = "基地LV1", enabled = true, source = "建筑/行5" },
    { level_id = "building_main_city_lv03", building_id = "building_main_city", level = 3, wood_cost = 3000, gold_cost = 0, population_add = 5, prerequisite_text = "基地LV2", unlock_text = "解锁金矿", enabled = true, source = "建筑/行6" },
    { level_id = "building_main_city_lv04", building_id = "building_main_city", level = 4, wood_cost = 11000, gold_cost = 100, population_add = 5, prerequisite_text = "基地LV3", unlock_text = "解锁高级研究所", enabled = true, source = "建筑/行7", notes = "解锁祭坛→装备商店→挑战商店、转升挑战" },
    { level_id = "building_main_city_lv05", building_id = "building_main_city", level = 5, wood_cost = 30000, gold_cost = 500, population_add = 5, prerequisite_text = "基地LV4", unlock_text = "解锁挑战建筑额外内容（英雄攻击及属性挑战BOSS），解锁农民合成。", enabled = true, source = "建筑/行8" },
    { level_id = "building_farm_lv01", building_id = "building_farm", level = 1, wood_cost = 100, gold_cost = 0, population_add = 1, prerequisite_text = "基地LV1", enabled = true, source = "建筑/行25" },
    { level_id = "building_farm_lv02", building_id = "building_farm", level = 2, wood_cost = 1000, gold_cost = 0, population_add = 3, prerequisite_text = "基地LV2", enabled = true, source = "建筑/行26" },
    { level_id = "building_farm_lv03", building_id = "building_farm", level = 3, wood_cost = 3000, gold_cost = 0, population_add = 2, prerequisite_text = "基地LV3", enabled = true, source = "建筑/行27" },
    { level_id = "building_farm_lv04", building_id = "building_farm", level = 4, wood_cost = 5000, gold_cost = 0, population_add = 1, prerequisite_text = "基地LV4", enabled = true, source = "建筑/行28" },
    { level_id = "building_farm_lv05", building_id = "building_farm", level = 5, wood_cost = 8000, gold_cost = 0, population_add = 1, prerequisite_text = "基地LV5", enabled = true, source = "建筑/行29" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["level_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
