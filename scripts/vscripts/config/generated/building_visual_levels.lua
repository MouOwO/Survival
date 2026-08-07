-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: building_visual_levels.csv
local M = {}
M.rows = {
    { visual_id = "main_city_visual_lv01", building_id = "building_main_city", level = 1, model_name = "models/props_structures/tower_good.vmdl", model_scale = 0.55, model_yaw = 0, enabled = true, notes = "主城低阶塔第一阶段" },
    { visual_id = "main_city_visual_lv02", building_id = "building_main_city", level = 2, model_name = "models/props_structures/tower_good.vmdl", model_scale = 0.65, model_yaw = 0, enabled = true, notes = "主城低阶塔逐级放大" },
    { visual_id = "main_city_visual_lv03", building_id = "building_main_city", level = 3, model_name = "models/props_structures/tower_good.vmdl", model_scale = 0.75, model_yaw = 0, enabled = true, notes = "主城低阶塔最终阶段" },
    { visual_id = "main_city_visual_lv04", building_id = "building_main_city", level = 4, model_name = "models/props_structures/tower_good3.vmdl", model_scale = 0.80, model_yaw = 0, enabled = true, notes = "主城切换神圣高塔" },
    { visual_id = "main_city_visual_lv05", building_id = "building_main_city", level = 5, model_name = "models/props_structures/tower_good3.vmdl", model_scale = 0.95, model_yaw = 0, enabled = true, notes = "主城神圣高塔最终阶段" },
    { visual_id = "hero_altar_visual_lv01", building_id = "building_hero_altar", level = 1, model_name = "models/props_structures/radiant_ancient001.vmdl", model_scale = 0.34, model_yaw = 0, enabled = true, notes = "召唤祭坛可选中动态模型" },
    { visual_id = "research_lab_visual_lv01", building_id = "building_research_lab", level = 1, model_name = "models/props_structures/radiant_ancient001.vmdl", model_scale = 0.34, model_yaw = 0, enabled = true, notes = "研究所与英雄祭坛保持相同模型缩放" },
    { visual_id = "farm_visual_lv01", building_id = "building_farm", level = 1, model_name = "models/props_structures/radiant_ancient001.vmdl", model_scale = 0.34, model_yaw = 0, enabled = true, notes = "人口农场与英雄祭坛保持相同模型缩放" },
    { visual_id = "gold_mine_visual_lv01", building_id = "building_gold_mine", level = 1, model_name = "models/props_structures/tower_good4.vmdl", model_scale = 1, model_yaw = 0, enabled = true, notes = "金矿使用模型原生缩放" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["visual_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
