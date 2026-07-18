-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: enums.csv
local M = {}
M.rows = {
    { enum_name = "content_type", enum_value = "weapon", sort_order = 1, enabled = true },
    { enum_name = "content_type", enum_value = "equipment", sort_order = 2, enabled = true },
    { enum_name = "content_type", enum_value = "item", sort_order = 3, enabled = true },
    { enum_name = "content_type", enum_value = "material", sort_order = 4, enabled = true },
    { enum_name = "content_type", enum_value = "technology", sort_order = 5, enabled = true },
    { enum_name = "content_type", enum_value = "building", sort_order = 6, enabled = true },
    { enum_name = "content_type", enum_value = "challenge", sort_order = 7, enabled = true },
    { enum_name = "content_type", enum_value = "rebirth", sort_order = 8, enabled = true },
    { enum_name = "content_type", enum_value = "shop_proxy", sort_order = 9, enabled = true },
    { enum_name = "shop_category", enum_value = "weapon", sort_order = 1, enabled = true },
    { enum_name = "shop_category", enum_value = "item", sort_order = 2, enabled = true },
    { enum_name = "shop_category", enum_value = "technology", sort_order = 3, enabled = true },
    { enum_name = "shop_category", enum_value = "challenge", sort_order = 4, enabled = true },
    { enum_name = "shop_category", enum_value = "rebirth", sort_order = 5, enabled = true },
    { enum_name = "recipe_type", enum_value = "auto_synthesis", sort_order = 1, enabled = true },
    { enum_name = "recipe_type", enum_value = "synthesis", sort_order = 2, enabled = true },
    { enum_name = "recipe_type", enum_value = "combine_3_to_1", sort_order = 3, enabled = true },
    { enum_name = "recipe_type", enum_value = "equipment_upgrade", sort_order = 4, enabled = true },
    { enum_name = "review_status", enum_value = "ok", sort_order = 1, enabled = true },
    { enum_name = "review_status", enum_value = "needs_confirmation", sort_order = 2, enabled = true },
    { enum_name = "review_status", enum_value = "needs_cost", sort_order = 3, enabled = true },
    { enum_name = "review_status", enum_value = "description_inferred", sort_order = 4, enabled = true },
    { enum_name = "progression_type", enum_value = "normal_attack_count", sort_order = 1, enabled = true },
    { enum_name = "progression_type", enum_value = "monster_kill_count", sort_order = 2, enabled = true },
    { enum_name = "progression_type", enum_value = "repeat_purchase", sort_order = 3, enabled = true },
    { enum_name = "progression_type", enum_value = "recipe_upgrade", sort_order = 4, enabled = true },
    { enum_name = "value_type", enum_value = "number", sort_order = 1, enabled = true },
    { enum_name = "value_type", enum_value = "percent", sort_order = 2, enabled = true },
    { enum_name = "value_type", enum_value = "string", sort_order = 3, enabled = true },
    { enum_name = "value_type", enum_value = "boolean", sort_order = 4, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["enum_name"]
    if key ~= nil then M.by_id[key] = row end
end
return M
