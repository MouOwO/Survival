-- 配方层的手工快照；ID 来自 generated recipes/recipe_ingredients。
local M = {}
M.rows = {
    { recipe_id = "recipe_growth_max_mask_to_frost_01", result_content_id = "weapon_frost_blade_01", ingredients = { { content_id = "weapon_growth_sword_max", quantity = 1 }, { content_id = "item_death_mask", quantity = 1 } }, enabled = true, review_status = "needs_confirmation", notes = "死亡面罩按需求映射为吸血面罩；源描述存在幻影之剑/霜之剑刃命名冲突。" },
    { recipe_id = "recipe_equipment_set_to_infernal_01", result_content_id = "equipment_infernal_armor_01", ingredients = { { content_id = "equipment_attack_gloves_max", quantity = 1 }, { content_id = "equipment_burning_blade_max", quantity = 1 }, { content_id = "equipment_iron_armor_max", quantity = 1 }, { content_id = "material_synthesis_gem", quantity = 1 } }, enabled = true, review_status = "ok" },
    { recipe_id = "recipe_molten_core_01_to_02", result_content_id = "material_molten_core_02", ingredients = { { content_id = "material_molten_core_01", quantity = 3 } }, enabled = true, review_status = "ok" },
    { recipe_id = "recipe_molten_core_02_to_03", result_content_id = "material_molten_core_03", ingredients = { { content_id = "material_molten_core_02", quantity = 3 } }, enabled = true, review_status = "ok" },
    { recipe_id = "recipe_infernal_01_to_02", result_content_id = "equipment_infernal_armor_02", ingredients = { { content_id = "equipment_infernal_armor_01", quantity = 1 }, { content_id = "material_molten_core_01", quantity = 1 } }, enabled = true, review_status = "description_inferred" },
    { recipe_id = "recipe_infernal_02_to_03", result_content_id = "equipment_infernal_armor_03", ingredients = { { content_id = "equipment_infernal_armor_02", quantity = 1 }, { content_id = "material_molten_core_02", quantity = 1 } }, enabled = true, review_status = "description_inferred" },
    { recipe_id = "recipe_infernal_03_to_04", result_content_id = "equipment_infernal_armor_04", ingredients = { { content_id = "equipment_infernal_armor_03", quantity = 1 }, { content_id = "material_molten_core_03", quantity = 1 } }, enabled = true, review_status = "description_inferred" },
    { recipe_id = "recipe_infernal_04_to_max", result_content_id = "equipment_infernal_armor_max", ingredients = { { content_id = "equipment_infernal_armor_04", quantity = 1 }, { content_id = "material_molten_core_04", quantity = 1 } }, enabled = true, review_status = "explicit_requirement", notes = "明确需求：狱火熔铠Lv4+熔火核心Lv4→MAX；Excel中核心等级笔误仅进入审核记录。" },
    { recipe_id = "recipe_frost_max_crystal_gem_to_ice_01", result_content_id = "weapon_ice_blade_01", ingredients = { { content_id = "weapon_frost_blade_max", quantity = 1 }, { content_id = "item_large_polar_crystal", quantity = 1 }, { content_id = "material_synthesis_gem", quantity = 1 } }, enabled = true, review_status = "ok" },
    { recipe_id = "recipe_ice_infernal_ember_to_epic", result_content_id = "weapon_epic_icefire_00", ingredients = { { content_id = "weapon_ice_blade_max", quantity = 1 }, { content_id = "equipment_infernal_armor_max", quantity = 1 }, { content_id = "material_ice_soul_ember", quantity = 1 } }, enabled = true, review_status = "ok" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do M.by_id[row.recipe_id] = row end
return M
