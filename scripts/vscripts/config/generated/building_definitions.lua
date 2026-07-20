-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: building_definitions.csv
local M = {}
M.rows = {
    { building_id = "wall", name = "城墙", unit_name = "building_wall", max_count = 1, requires_city_level = 0, population_cost = 0, builder_ability = "ability_build_wall", disable_after_built = true, notes = "建造成功后Undying的建造城墙技能在客户端置灰；服务端仍验证max_count=1。" },
    { building_id = "main_city", name = "主城", unit_name = "building_main_city", max_count = 1, requires_city_level = 0, population_cost = 0, builder_ability = "ability_build_main_city", disable_after_built = true, notes = "建造成功后Undying的建造主城技能在客户端置灰；服务端仍验证max_count=1。" },
    { building_id = "arrow_tower", name = "箭塔", unit_name = "building_arrow_tower", max_count = 0, requires_city_level = 1, population_cost = 0, unlock_condition = "main_city_level>=1", builder_ability = "ability_build_arrow_tower", disable_after_built = false, notes = "箭塔5级后进入五选一转职。" },
    { building_id = "building_farm", name = "人口农场", unit_name = "building_farm", max_count = 0, requires_city_level = 1, population_cost = 0, unlock_condition = "main_city_level>=1", builder_ability = "ability_build_farm", disable_after_built = false },
    { building_id = "building_research_lab", name = "研究所", unit_name = "building_research_lab", max_count = 1, requires_city_level = 1, population_cost = 0, unlock_condition = "main_city_level>=1", builder_ability = "ability_build_research_lab", disable_after_built = true },
    { building_id = "building_advanced_research_lab", name = "高级研究所", unit_name = "building_advanced_research_lab", max_count = 1, requires_city_level = 4, population_cost = 0, unlock_condition = "main_city_level>=4", builder_ability = "ability_build_advanced_research_lab", disable_after_built = true },
    { building_id = "gold_mine", name = "金矿", unit_name = "building_gold_mine", max_count = 1, requires_city_level = 3, population_cost = 0, unlock_condition = "main_city_level>=3", builder_ability = "ability_build_gold_mine", disable_after_built = true, notes = "主城3级解锁；具体建造费用由building_levels或正式配置补充。" },
    { building_id = "hero_altar", name = "英雄祭坛", unit_name = "building_hero_altar", max_count = 1, requires_city_level = 3, population_cost = 0, unlock_condition = "main_city_level>=3", builder_ability = "ability_build_hero_altar", disable_after_built = true, notes = "主城3级后可建造；每位玩家只能召唤一个英雄。英雄召唤完成后祭坛仅作为普通建筑，商店UI同时解锁。建造费用300木材+100金币为暂定值。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["building_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
