local event_bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local technology_stat_manager = require("systems/technology_stat_manager")

local M = {}
local state_by_player = {}
local FORGING_HAMMER_ID = "item_forging_hammer"
local FORGING_HAMMER_LIMIT = 4

local function state(player_id)
    state_by_player[player_id] = state_by_player[player_id] or {
        content_id = "",
        series_id = "",
        stage_attack_count = 0,
        lifetime_attack_count = 0,
        growth_attack = 0,
        growth_strength = 0,
        growth_agility = 0,
        growth_intellect = 0,
    }
    return state_by_player[player_id]
end

local function snapshot(player_id)
    local current = state(player_id)
    local definition = weapons.by_id[current.content_id] or {}
    local target = tonumber(definition.progression_value) or 0
    local inventory = event_bus.request(
        events.CONTENT_INVENTORY_GET_REQUEST,
        { player_id = player_id }
    )
    local counts = inventory and inventory.snapshot
        and inventory.snapshot.counts or {}
    local hammer_count = math.min(FORGING_HAMMER_LIMIT, math.max(
        0,
        math.floor(tonumber(counts[FORGING_HAMMER_ID]) or 0)
    ))
    return {
        player_id = player_id,
        content_id = current.content_id,
        series_id = current.series_id,
        stage = tonumber(definition.stage) or 0,
        stage_attack_count = current.stage_attack_count,
        stage_attack_target = target,
        stage_attack_remaining = math.max(0, target - current.stage_attack_count),
        forging_hammer_count = hammer_count,
        progress_per_attack = 1 + hammer_count,
        lifetime_attack_count = current.lifetime_attack_count,
        growth_attack = current.growth_attack,
        growth_strength = current.growth_strength,
        growth_agility = current.growth_agility,
        growth_intellect = current.growth_intellect,
        attack_gain_per_attack =
            tonumber(definition.attack_gain_per_attack) or 0,
    }
end

local function publish(player_id, reason)
    event_bus.emit(events.WEAPON_GROWTH_CHANGED, {
        player_id = player_id,
        reason = reason or "changed",
        snapshot = snapshot(player_id),
    })
end

local function on_equipped(payload)
    if payload.slot ~= "main_hand" then
        return
    end
    local player_id = tonumber(payload.player_id)
    local current = state(player_id)
    local next_definition = weapons.by_id[payload.content_id] or {}
    local previous_definition = weapons.by_id[payload.previous_content_id] or {}
    local preserve = next_definition.preserve_growth_on_upgrade == true
        or (next_definition.series_id ~= ""
            and next_definition.series_id == previous_definition.series_id)
    if not preserve then
        current.growth_attack = 0
        current.growth_strength = 0
        current.growth_agility = 0
        current.growth_intellect = 0
        current.lifetime_attack_count = 0
    end
    if payload.content_id ~= payload.previous_content_id
        and payload.reason ~= "weapon_attack_upgrade" then
        current.stage_attack_count = 0
    end
    current.content_id = tostring(payload.content_id or "")
    current.series_id = tostring(next_definition.series_id or "")
    publish(player_id, "weapon_equipped")
end

local function upgrade_if_ready(player_id, current, definition)
    local target = tonumber(definition.progression_value) or 0
    local next_id = tostring(definition.next_content_id or "")
    if definition.progression_type ~= "normal_attack_count"
        or target <= 0 or next_id == ""
        or current.stage_attack_count < target then
        return false
    end
    current.stage_attack_count = current.stage_attack_count - target
    local result = event_bus.request(
        events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
        {
            player_id = player_id,
            consume = { [current.content_id] = 1 },
            grant = { [next_id] = 1 },
            reason = "weapon_attack_upgrade",
        }
    )
    if not result or not result.ok then
        current.stage_attack_count = current.stage_attack_count + target
        return false
    end
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "武器成长完成：" .. next_id,
        level = "info",
    })
    return true
end

local function add_attacks(player_id, amount, reason, income_multiplier)
    local current = state(player_id)
    local definition = weapons.by_id[current.content_id]
    if not definition or definition.enabled == false then
        return { ok = false, error = "weapon_not_equipped" }
    end
    local count = math.max(0, math.floor(tonumber(amount) or 0))
    if count <= 0 then
        return { ok = false, error = "attack_count_invalid" }
    end
    local attack_gain = tonumber(definition.attack_gain_per_attack) or 0
    local strength_gain = tonumber(definition.strength_gain_per_attack) or 0
    local agility_gain = tonumber(definition.agility_gain_per_attack) or 0
    local intellect_gain = tonumber(definition.intellect_gain_per_attack) or 0
    local multiplier = math.max(1, tonumber(income_multiplier) or 1)
    current.stage_attack_count = current.stage_attack_count + count
    current.lifetime_attack_count = current.lifetime_attack_count + count
    current.growth_attack = current.growth_attack + attack_gain * count * multiplier
    current.growth_strength = current.growth_strength + strength_gain * count * multiplier
    current.growth_agility = current.growth_agility + agility_gain * count * multiplier
    current.growth_intellect = current.growth_intellect + intellect_gain * count * multiplier
    publish(player_id, reason or "attack_landed")
    local guard = 0
    while upgrade_if_ready(player_id, current, definition) do
        guard = guard + 1
        if guard >= 20 then
            break
        end
        definition = weapons.by_id[current.content_id]
        if not definition then
            break
        end
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function on_attack_landed(payload)
    local player_id = tonumber(payload.player_id)
    local data = snapshot(player_id)
    if data.series_id == "epic_icefire" or data.series_id == "legend_abyss" then
        return
    end
    local multiplier = technology_stat_manager.training_room_multiplier(
        player_id,
        payload.target
    )
    add_attacks(player_id, data.progress_per_attack, "attack_landed", multiplier)
end

local function on_damage_dealt(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or (tonumber(payload.final_damage) or 0) <= 0 then return end
    local data = snapshot(player_id)
    if data.series_id ~= "epic_icefire" and data.series_id ~= "legend_abyss" then
        return
    end
    local multiplier = technology_stat_manager.training_room_multiplier(
        player_id,
        payload.target
    )
    local current = state(player_id)
    local definition = weapons.by_id[current.content_id]
    if not definition then return end
    -- Icefire/Abyss explicitly grow from every successful allied damage event,
    -- not only basic attacks. Keep these canonical values independent from the
    -- legacy CSV columns, where Abyss stages previously contained zeroes.
    local attack_gain = 20
    local attribute_gain = 5
    current.growth_attack = current.growth_attack
        + attack_gain * multiplier
    current.growth_strength = current.growth_strength
        + attribute_gain * multiplier
    current.growth_agility = current.growth_agility
        + attribute_gain * multiplier
    current.growth_intellect = current.growth_intellect
        + attribute_gain * multiplier
    publish(player_id, "damage_dealt")
end

local function on_hero_summoned(payload)
    if payload.unit and not payload.unit:IsNull() then
        payload.unit:AddNewModifier(
            payload.unit,
            nil,
            "modifier_weapon_attack_tracker",
            { player_id = payload.player_id }
        )
    end
end

local function get_growth(payload)
    return { ok = true, snapshot = snapshot(tonumber(payload.player_id)) }
end

local function on_inventory_changed(payload)
    if payload.changes and payload.changes[FORGING_HAMMER_ID] then
        publish(tonumber(payload.player_id), "forging_hammer_changed")
    end
end

local function debug_add(payload)
    return add_attacks(
        tonumber(payload.player_id),
        tonumber(payload.count) or 1,
        "debug_attack_growth"
    )
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(events.WEAPON_GROWTH_GET_REQUEST, get_growth)
    event_bus.handle_request(events.WEAPON_GROWTH_DEBUG_REQUEST, debug_add)
    event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, on_equipped)
    event_bus.subscribe(events.WEAPON_ATTACK_LANDED, on_attack_landed)
    event_bus.subscribe(events.COMBAT_DAMAGE_RESOLVED, on_damage_dealt)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_inventory_changed)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
