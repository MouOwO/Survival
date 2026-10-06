local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local recipe_config = require("config/recipe_definitions")
local effect_config = require("config/item_level_effects")
local levels = require("config/equipment_level_definitions")
local weapons = require("config/generated/weapon_definitions")
local effects = require("config/effect_dictionary")
local tooltip_view_model = require("ui/tooltip_view_model")
local weapon_progression = require("systems/weapon_progression")

local M = {}
local states, generation = {}, 0
local GROWTH_PUBLISH_INTERVAL = 0.1

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function authoritative_growth(equipped, weapon_growth, equipment_progress)
    local result = copy(weapon_growth)
    local content_id = tostring(equipped.main_hand_content_id or "")
    if weapon_progression.is_max_level(weapons.by_id[content_id]) then
        result.is_max_level = 1
        result.stage_attack_target, result.stage_attack_remaining = 0, 0
        return result
    end
    local definition = levels.by_id[content_id]
    if not definition or not definition.progression
        or definition.progression.type ~= "valid_enemy_kill_count" then
        return result
    end
    local configured_target = tonumber(
        weapons.by_id[content_id] and weapons.by_id[content_id].progression_value
    )
    -- Growth already applied the player's permanent requirement reduction.
    local target = tonumber(result.stage_attack_target)
    if not target or target <= 0 then
        target = configured_target and configured_target > 0 and configured_target or 200
    end
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

local function publish(id, reason, active)
    if not valid_player(id) then return end
    local equipment = event_bus.request(
        events.WEAPON_EQUIPMENT_GET_REQUEST, { player_id = id })
    if not active() then return end
    local growth = event_bus.request(
        events.WEAPON_GROWTH_GET_REQUEST, { player_id = id })
    if not active() then return end
    local instances = event_bus.request(
        events.EQUIPMENT_INSTANCE_GET_REQUEST, { player_id = id })
    if not active() then return end
    local equipment_growth = event_bus.request(
        events.EQUIPMENT_GROWTH_GET_REQUEST, { player_id = id })
    if not active() then return end
    local equipped = equipment and equipment.snapshot or { player_id = id }
    local raw_weapon_growth = growth and growth.snapshot or { player_id = id }
    local equipment_progress = equipment_growth and equipment_growth.progress or {}
    local weapon_growth = authoritative_growth(
        equipped,
        raw_weapon_growth,
        equipment_progress
    )
    local combined = {
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
    }
    if not active() then return end
    for _, entry in ipairs({
        { "survival_weapon_equipment", equipped },
        { "survival_weapon_growth", weapon_growth },
        { "survival_equipment_instances", instances or { ok = false } },
        { "survival_equipment_growth", equipment_growth or { ok = false } },
        { "survival_weapon_snapshot", combined },
    }) do
        if not active() then return end
        CustomNetTables:SetTableValue(entry[1], tostring(id), entry[2])
    end
    if not active() then return end
    send(id, "ui_weapon_synthesis_snapshot", {
        player_id = id, reason = reason or "changed", success = 1,
    })
end

local function state(id)
    if not states[id] then states[id] = { revision = 0 } end
    return states[id]
end

local function cancel_pending(current)
    local pending = current.pending
    current.pending = nil
    if pending then scheduler.cancel(pending.task) end
end

local flush
local function schedule_publish(id, current, delay)
    if current.pending then return end
    local pending, active_generation = {}, generation
    current.pending = pending
    pending.task = scheduler.after(delay, function()
        if generation ~= active_generation or states[id] ~= current
            or current.pending ~= pending then return end
        current.pending = nil
        current.immediate_reason = current.immediate_reason or "state_changed"
        flush(id, current)
    end)
end

flush = function(id, current)
    if current.publishing then return end
    local active_generation = generation
    local passes = 0
    -- A nested equipment/lifecycle event invalidates the in-flight snapshot.
    -- Publish its replacement after unwinding rather than writing older data
    -- over a new hero. Bound synchronous retries if a native callback reenters.
    while current.immediate_reason and states[id] == current
        and generation == active_generation and passes < 2 do
        local reason, revision = current.immediate_reason, current.revision
        current.immediate_reason, current.publishing = nil, true
        local ok, err = pcall(publish, id, reason, function()
            return generation == active_generation and states[id] == current
                and current.revision == revision
        end)
        current.publishing = false
        if not ok then error(err) end
        passes = passes + 1
    end
    if current.immediate_reason and states[id] == current
        and generation == active_generation then schedule_publish(id, current, 0) end
end

local function publish_immediately(id, reason)
    if not valid_player(id) then return end
    local current = state(id)
    cancel_pending(current)
    current.revision = current.revision + 1
    current.immediate_reason = reason or "state_changed"
    flush(id, current)
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
    publish_immediately(tonumber(payload and payload.player_id), "state_changed")
end

local function growth_changed(payload)
    local id = tonumber(payload and payload.player_id)
    if not valid_player(id) then return end
    if payload.reason ~= "attack_landed" and payload.reason ~= "damage_dealt" then
        changed(payload)
        return
    end
    local current = state(id)
    if current.removed then return end
    -- Only defer UI projection. Growth counters and combat attributes have
    -- already changed synchronously; read their newest values when flushing.
    schedule_publish(id, current, GROWTH_PUBLISH_INTERVAL)
end

local function hero_summoned(payload)
    local id = tonumber(payload and payload.player_id)
    if not valid_player(id) then return end
    local current = state(id)
    current.hero, current.removed = payload.unit, false
    publish_immediately(id, "hero_summoned")
end

local function hero_removed(payload)
    local current = states[tonumber(payload and payload.player_id)]
    if not current or (current.hero and current.hero ~= payload.unit) then return end
    cancel_pending(current)
    current.hero, current.removed, current.immediate_reason = nil, true, nil
    current.revision = current.revision + 1
end

function M.publish_player(player_id, reason)
    publish_immediately(tonumber(player_id), reason)
end

function M.init()
    for _, current in pairs(states) do cancel_pending(current) end
    states, generation = {}, generation + 1
    local active_generation = generation
    publish_catalog()
    for name, handler in pairs({
        [events.HERO_READY] = changed,
        [events.HERO_SUMMONED] = hero_summoned,
        [events.HERO_REMOVED] = hero_removed,
        [events.CONTENT_INVENTORY_CHANGED] = changed,
        [events.WEAPON_EQUIPPED_CHANGED] = changed,
        [events.WEAPON_GROWTH_CHANGED] = growth_changed,
        [events.EQUIPMENT_INSTANCE_CHANGED] = changed,
        [events.EQUIPMENT_GROWTH_CHANGED] = changed,
        [events.WEAPON_SYNTHESIZED] = changed,
    }) do
        local callback = handler
        event_bus.subscribe(name, function(payload)
            if generation == active_generation then callback(payload) end
        end)
    end
end

return M
