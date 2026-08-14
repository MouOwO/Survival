-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: builder_ability_stages.csv
local M = {}
M.rows = {
    { stage_id = "wall_pending", stage_order = 10, trigger_state = "wall_not_built", ability_name = "ability_build_wall", slot_order = 1, required_city_level = 0, building_id = "wall", max_building_count = 1, disable_after_hero_summoned = false, enabled = true, notes = "游戏开始只显示建造城墙。" },
    { stage_id = "city_pending", stage_order = 20, trigger_state = "wall_built_city_not_built", ability_name = "ability_build_main_city", slot_order = 1, required_city_level = 0, building_id = "main_city", max_building_count = 1, disable_after_hero_summoned = false, enabled = true, notes = "城墙完成后，同一建造链技能替换为建造主城。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_arrow_tower", slot_order = 1, required_city_level = 1, building_id = "arrow_tower", max_building_count = 7, disable_after_hero_summoned = false, enabled = true, notes = "主城完成后可建造；最多同时存在7座未转职箭塔，转职后释放名额。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_research_lab", slot_order = 2, required_city_level = 1, building_id = "building_research_lab", max_building_count = 1, disable_after_hero_summoned = false, enabled = true, notes = "主城完成后W技能解锁建造研究所；研究所最多建造1座。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_challenge", slot_order = 2, required_city_level = 1, building_id = "building_challenge", max_building_count = 1, disable_after_hero_summoned = false, enabled = true, notes = "研究所完成后替换W槽；挑战建筑最多建造1座。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_farm", slot_order = 3, required_city_level = 1, building_id = "building_farm", max_building_count = 1, disable_after_hero_summoned = false, enabled = true, notes = "主城完成后解锁人口农场，最多建造1座；达到上限后移除建造技能。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_hero_altar", slot_order = 4, required_city_level = 3, building_id = "hero_altar", max_building_count = 1, disable_after_hero_summoned = true, enabled = true, notes = "祭坛显示在技能列表中；主城不足3级时置灰；召唤英雄后永久置灰。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_gold_mine", slot_order = 5, required_city_level = 3, building_id = "gold_mine", max_building_count = 5, disable_after_hero_summoned = false, enabled = true, notes = "主城3级后显示，最多建造5座金矿；达到上限后移除建造技能。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["stage_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
