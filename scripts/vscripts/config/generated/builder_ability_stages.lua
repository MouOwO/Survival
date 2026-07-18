-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: builder_ability_stages.csv
local M = {}
M.rows = {
    { stage_id = "wall_pending", stage_order = 10, trigger_state = "wall_not_built", ability_name = "ability_build_wall", slot_order = 1, required_city_level = 0, building_id = "wall", max_building_count = 1, disable_after_hero_summoned = false, enabled = true, notes = "游戏开始只显示建造城墙。" },
    { stage_id = "city_pending", stage_order = 20, trigger_state = "wall_built_city_not_built", ability_name = "ability_build_main_city", slot_order = 1, required_city_level = 0, building_id = "main_city", max_building_count = 1, disable_after_hero_summoned = false, enabled = true, notes = "城墙完成后，同一建造链技能替换为建造主城。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_arrow_tower", slot_order = 1, required_city_level = 1, building_id = "arrow_tower", max_building_count = 0, disable_after_hero_summoned = false, enabled = true, notes = "主城完成后常驻显示，可重复建造。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_hero_altar", slot_order = 2, required_city_level = 3, building_id = "hero_altar", max_building_count = 1, disable_after_hero_summoned = true, enabled = true, notes = "祭坛显示在技能列表中；主城不足3级时置灰；召唤英雄后永久置灰。" },
    { stage_id = "city_built", stage_order = 30, trigger_state = "main_city_built", ability_name = "ability_build_gold_mine", slot_order = 3, required_city_level = 3, building_id = "gold_mine", max_building_count = 1, disable_after_hero_summoned = false, enabled = false, notes = "当前建造阶段按最新需求只显示箭塔和祭坛，因此默认停用。金矿系统与配置保留，策划将enabled改为1即可恢复。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["stage_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
