local event_bus = require("core/event_bus")
local events = require("core/events")
local recipe_config = require("config/recipe_definitions")
local effect_config = require("config/item_level_effects")
local levels = require("config/equipment_level_definitions")
local weapons = require("config/generated/weapon_definitions")
local effects = require("config/effect_dictionary")
local tooltip_view_model = require("ui/tooltip_view_model")

local M = {}

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function authoritative_growth(equipped, weapon_growth, equipment_progress)
    local result = copy(weapon_growth)
    local content_id = tostring(equipped.main_hand_content_id or "")
    local definition = levels.by_id[content_id]
    if not definition or not definition.progression
        or definition.progression.type ~= "valid_enemy_kill_count" then
        return result
    end
    local configured_target = tonumber(
        weapons.by_id[content_id] and weapons.by_id[content_id].progression_value
    )
    local target = configured_target and configured_target > 0
        and configured_target or 200
    local current = math.max(
        0,
        tonumber(equipment_progress and equipment_progress[content_id]) or 0
    )
    result.stage_attack_count = current
    result.stage_attack_target = target
    result.stage_attack_remaining = math.max(0, target - current)
    return result
end

local function valid_player(id)
    return id ~= nil and id >= 0 and PlayerResource:IsValidPlayerID(id)
end

local function send(id, event_name, data)
    if not valid_player(id) then return end
    local player = PlayerResource:GetPlayer(id)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, event_name, data)
    end
end

local function publish(id, reason)
    if not valid_player(id) then return end
    local equipment = event_bus.request(
        events.WEAPON_EQUIPMENT_GET_REQUEST, { player_id = id })
    local growth = event_bus.request(
        events.WEAPON_GROWTH_GET_REQUEST, { player_id = id })
    local instances = event_bus.request(
        events.EQUIPMENT_INSTANCE_GET_REQUEST, { player_id = id })
    local equipment_growth = event_bus.request(
        events.EQUIPMENT_GROWTH_GET_REQUEST, { player_id = id })
    local equipped = equipment and equipment.snapshot or { player_id = id }
    local raw_weapon_growth = growth and growth.snapshot or { player_id = id }
    local equipment_progress = equipment_growth and equipment_growth.progress or {}
    local weapon_growth = authoritative_growth(
        equipped,
        raw_weapon_growth,
        equipment_progress
    )
    CustomNetTables:SetTableValue(
        "survival_weapon_equipment", tostring(id), equipped)
    CustomNetTables:SetTableValue(
        "survival_weapon_growth", tostring(id), weapon_growth)
    CustomNetTables:SetTableValue(
        "survival_equipment_instances", tostring(id), instances or { ok = false })
    CustomNetTables:SetTableValue(
        "survival_equipment_growth", tostring(id), equipment_growth or { ok = false })
    CustomNetTables:SetTableValue("survival_weapon_snapshot", tostring(id), {
        player_id = id,
        reason = reason or "changed",
        equipment = equipped,
        growth = weapon_growth,
        instances = instances and instances.instances or {},
        equipment_growth = equipment_progress,
        tooltip_view_model = tooltip_view_model.weapon_snapshot(
            equipped,
            weapon_growth,
            instances and instances.instances or {},
            equipment_progress
        ),
    })
    send(id, "ui_weapon_synthesis_snapshot", {
        player_id = id, reason = reason or "changed", success = 1,
    })
end

local function publish_catalog()
    local enabled_recipes = {}
    for _, row in ipairs(recipe_config.rows or {}) do
        if row.enabled ~= false then
            enabled_recipes[#enabled_recipes + 1] = row
        end
    end
    local enabled_ingredients = {}
    for _, recipe in ipairs(enabled_recipes) do
        for _, ingredient in ipairs(recipe.ingredients or {}) do
            enabled_ingredients[#enabled_ingredients + 1] = {
                recipe_id = recipe.recipe_id,
                content_id = ingredient.content_id,
                quantity = ingredient.quantity,
            }
        end
    end
    CustomNetTables:SetTableValue(
        "survival_weapon_recipes", "root", {
            rows = enabled_recipes, ingredients = enabled_ingredients,
        })
    CustomNetTables:SetTableValue("survival_weapon_effects", "root", {
        definitions = effects.definitions,
        unknown_policy = effects.unknown_policy,
        rows = effect_config.by_content_id or {},
    })
    CustomNetTables:SetTableValue(
        "survival_equipment_levels", "root", { rows = levels.rows or {} })
end

local function changed(payload)
    publish(tonumber(payload and payload.player_id), "state_changed")
end

function M.publish_player(player_id, reason)
    publish(tonumber(player_id), reason)
end

function M.init()
    publish_catalog()
    event_bus.subscribe(events.HERO_READY, changed)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, changed)
    event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, changed)
    event_bus.subscribe(events.WEAPON_GROWTH_CHANGED, changed)
    event_bus.subscribe(events.EQUIPMENT_INSTANCE_CHANGED, changed)
    event_bus.subscribe(events.EQUIPMENT_GROWTH_CHANGED, changed)
    event_bus.subscribe(events.WEAPON_SYNTHESIZED, changed)
end

return M
