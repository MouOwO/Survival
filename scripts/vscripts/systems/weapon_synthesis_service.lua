local event_bus = require("core/event_bus")
local events = require("core/events")
local recipes = require("config/generated/recipes")
local ingredients = require("config/generated/recipe_ingredients")
local scheduler = require("core/scheduler")

local M = {}
local processing = {}
local queued = {}
local auto_recipes = {}
local ingredients_by_recipe = {}

local function build_index()
    auto_recipes = {}
    ingredients_by_recipe = {}
    for _, ingredient in ipairs(ingredients.rows or {}) do
        local recipe_id = ingredient.recipe_id
        ingredients_by_recipe[recipe_id] =
            ingredients_by_recipe[recipe_id] or {}
        table.insert(ingredients_by_recipe[recipe_id], ingredient)
    end
    for _, recipe in ipairs(recipes.rows or {}) do
        local result_id = tostring(recipe.result_content_id or "")
        local is_weapon_recipe = string.sub(result_id, 1, 7) == "weapon_"
        if recipe.enabled ~= false
            and (recipe.recipe_type == "auto_synthesis" or is_weapon_recipe) then
            table.insert(auto_recipes, recipe)
        end
    end
end

local function can_make(recipe, counts)
    for _, ingredient in ipairs(
        ingredients_by_recipe[recipe.recipe_id] or {}
    ) do
        local required = tonumber(ingredient.quantity) or 1
        if (counts[ingredient.ingredient_content_id] or 0) < required then
            return false
        end
    end
    return true
end

local function transaction_for(recipe)
    local consume = {}
    for _, ingredient in ipairs(
        ingredients_by_recipe[recipe.recipe_id] or {}
    ) do
        if ingredient.consume ~= false then
            consume[ingredient.ingredient_content_id] =
                (consume[ingredient.ingredient_content_id] or 0)
                + (tonumber(ingredient.quantity) or 1)
        end
    end
    return consume, {
        [recipe.result_content_id] = tonumber(recipe.result_count) or 1,
    }
end

local function process_player(player_id)
    if processing[player_id] then
        return
    end
    processing[player_id] = true
    for _ = 1, 20 do
        local current = event_bus.request(
            events.CONTENT_INVENTORY_GET_REQUEST,
            { player_id = player_id }
        )
        local counts = current and current.snapshot
            and current.snapshot.counts or {}
        local selected = nil
        for _, recipe in ipairs(auto_recipes) do
            if can_make(recipe, counts) then
                selected = recipe
                break
            end
        end
        if not selected then
            break
        end
        local consume, grant = transaction_for(selected)
        local result = event_bus.request(
            events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
            {
                player_id = player_id,
                consume = consume,
                grant = grant,
                reason = "auto_synthesis:" .. selected.recipe_id,
            }
        )
        if not result or not result.ok then
            break
        end
        event_bus.emit(events.WEAPON_SYNTHESIZED, {
            player_id = player_id,
            recipe_id = selected.recipe_id,
            result_content_id = selected.result_content_id,
        })
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "自动合成完成：" .. selected.result_content_id,
            level = "info",
        })
    end
    processing[player_id] = nil
end

local function on_inventory_changed(payload)
    local player_id = tonumber(payload.player_id)
    if queued[player_id] then
        return
    end
    queued[player_id] = true
    scheduler.after(0.01, function()
        queued[player_id] = nil
        process_player(player_id)
    end, "weapon_synthesis_" .. tostring(player_id))
end

function M.init()
    processing = {}
    queued = {}
    build_index()
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_inventory_changed)
end

return M
