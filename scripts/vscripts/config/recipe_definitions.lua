-- Runtime recipe view assembled from the authoritative CSV generated modules.
local recipes = require("config/generated/recipes")
local ingredients = require("config/generated/recipe_ingredients")
local M = {}
local ingredients_by_recipe = {}
for _, ingredient in ipairs(ingredients.rows or {}) do
    local recipe_id = tostring(ingredient.recipe_id or "")
    ingredients_by_recipe[recipe_id] = ingredients_by_recipe[recipe_id] or {}
    ingredients_by_recipe[recipe_id][#ingredients_by_recipe[recipe_id] + 1] = {
        content_id = ingredient.ingredient_content_id,
        quantity = ingredient.quantity,
        consume = ingredient.consume,
        role = ingredient.role,
        slot = ingredient.slot,
    }
end
M.rows = {}
for _, source in ipairs(recipes.rows or {}) do
    local row = {}
    for key, value in pairs(source) do row[key] = value end
    row.ingredients = ingredients_by_recipe[row.recipe_id] or {}
    table.sort(row.ingredients, function(a, b)
        return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
    end)
    M.rows[#M.rows + 1] = row
end
M.by_id = {}
for _, row in ipairs(M.rows) do M.by_id[row.recipe_id] = row end
return M
