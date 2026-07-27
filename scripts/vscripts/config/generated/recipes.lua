-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: recipes.csv
local M = {}
M.rows = {
    { recipe_id = "recipe_growth_max_mask_to_frost_01", result_content_id = "weapon_frost_blade_01", result_count = 1, recipe_type = "auto_synthesis", enabled = true, review_status = "needs_confirmation", notes = "成长之剑MAX+死亡面罩；源表同时出现“幻影之剑/霜之剑刃”命名冲突。" },
    { recipe_id = "recipe_equipment_set_to_infernal_01", result_content_id = "equipment_infernal_armor_01", result_count = 1, recipe_type = "synthesis", enabled = true, review_status = "ok" },
    { recipe_id = "recipe_molten_core_01_to_02", result_content_id = "material_molten_core_02", result_count = 1, recipe_type = "combine_3_to_1", enabled = true, review_status = "ok" },
    { recipe_id = "recipe_molten_core_02_to_03", result_content_id = "material_molten_core_03", result_count = 1, recipe_type = "combine_3_to_1", enabled = true, review_status = "ok" },
    { recipe_id = "recipe_infernal_01_to_02", result_content_id = "equipment_infernal_armor_02", result_count = 1, recipe_type = "equipment_upgrade", enabled = true, review_status = "description_inferred" },
    { recipe_id = "recipe_infernal_02_to_03", result_content_id = "equipment_infernal_armor_03", result_count = 1, recipe_type = "equipment_upgrade", enabled = true, review_status = "description_inferred" },
    { recipe_id = "recipe_infernal_03_to_04", result_content_id = "equipment_infernal_armor_04", result_count = 1, recipe_type = "equipment_upgrade", enabled = true, review_status = "description_inferred" },
    { recipe_id = "recipe_infernal_04_to_max", result_content_id = "equipment_infernal_armor_max", result_count = 1, recipe_type = "equipment_upgrade", enabled = true, review_status = "ok", notes = "需求已确认：狱火熔铠Lv4＋熔火核心Lv4自动合成狱火熔铠Lvmax。" },
    { recipe_id = "recipe_frost_max_crystal_gem_to_ice_01", result_content_id = "weapon_ice_blade_01", result_count = 1, recipe_type = "synthesis", enabled = true, review_status = "ok" },
    { recipe_id = "recipe_ice_infernal_ember_to_epic", result_content_id = "weapon_epic_icefire_00", result_count = 1, recipe_type = "synthesis", enabled = true, review_status = "ok" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["recipe_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
