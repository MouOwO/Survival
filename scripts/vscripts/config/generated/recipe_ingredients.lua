-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: recipe_ingredients.csv
local M = {}
M.rows = {
    { recipe_id = "recipe_growth_max_mask_to_frost_01", slot = 1, ingredient_content_id = "weapon_growth_sword_max", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_growth_max_mask_to_frost_01", slot = 2, ingredient_content_id = "item_death_mask", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_equipment_set_to_infernal_01", slot = 1, ingredient_content_id = "equipment_attack_gloves_max", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_equipment_set_to_infernal_01", slot = 2, ingredient_content_id = "equipment_burning_blade_max", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_equipment_set_to_infernal_01", slot = 3, ingredient_content_id = "equipment_iron_armor_max", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_equipment_set_to_infernal_01", slot = 4, ingredient_content_id = "material_synthesis_gem", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_molten_core_01_to_02", slot = 1, ingredient_content_id = "material_molten_core_01", quantity = 3, consume = true, role = "ingredient" },
    { recipe_id = "recipe_molten_core_02_to_03", slot = 1, ingredient_content_id = "material_molten_core_02", quantity = 3, consume = true, role = "ingredient" },
    { recipe_id = "recipe_infernal_01_to_02", slot = 1, ingredient_content_id = "equipment_infernal_armor_01", quantity = 1, consume = true, role = "base_equipment" },
    { recipe_id = "recipe_infernal_01_to_02", slot = 2, ingredient_content_id = "material_molten_core_01", quantity = 1, consume = true, role = "upgrade_material" },
    { recipe_id = "recipe_infernal_02_to_03", slot = 1, ingredient_content_id = "equipment_infernal_armor_02", quantity = 1, consume = true, role = "base_equipment" },
    { recipe_id = "recipe_infernal_02_to_03", slot = 2, ingredient_content_id = "material_molten_core_02", quantity = 1, consume = true, role = "upgrade_material" },
    { recipe_id = "recipe_infernal_03_to_04", slot = 1, ingredient_content_id = "equipment_infernal_armor_03", quantity = 1, consume = true, role = "base_equipment" },
    { recipe_id = "recipe_infernal_03_to_04", slot = 2, ingredient_content_id = "material_molten_core_03", quantity = 1, consume = true, role = "upgrade_material" },
    { recipe_id = "recipe_infernal_04_to_max", slot = 1, ingredient_content_id = "equipment_infernal_armor_04", quantity = 1, consume = true, role = "base_equipment" },
    { recipe_id = "recipe_infernal_04_to_max", slot = 2, ingredient_content_id = "material_molten_core_04", quantity = 1, consume = true, role = "upgrade_material" },
    { recipe_id = "recipe_frost_max_crystal_gem_to_ice_01", slot = 1, ingredient_content_id = "weapon_frost_blade_max", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_frost_max_crystal_gem_to_ice_01", slot = 2, ingredient_content_id = "item_large_polar_crystal", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_frost_max_crystal_gem_to_ice_01", slot = 3, ingredient_content_id = "material_synthesis_gem", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_ice_infernal_ember_to_epic", slot = 1, ingredient_content_id = "weapon_ice_blade_max", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_ice_infernal_ember_to_epic", slot = 2, ingredient_content_id = "equipment_infernal_armor_max", quantity = 1, consume = true, role = "ingredient" },
    { recipe_id = "recipe_ice_infernal_ember_to_epic", slot = 3, ingredient_content_id = "material_ice_soul_ember", quantity = 1, consume = true, role = "ingredient" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["recipe_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
