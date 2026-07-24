local event_bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local items = require("config/generated/item_definitions")
local legacy_levels = require("config/equipment_level_definitions")

local M = {}
local snapshots = {}
local definitions = {}
local legacy_stats = {}
local FIELD_MAP = {
    attack_flat = "base_attack_flat",
    attack_speed_pct = "base_attack_speed_pct",
    health_flat = "base_health",
    armor_flat = "base_armor",
    all_attributes_flat = "base_all_attributes",
    lifesteal_pct = "base_lifesteal_pct",
}

local function rebuild_definitions()
    definitions = {}
    legacy_stats = {}
    for _, definition in ipairs(weapons.rows or {}) do
        definitions[tostring(definition.content_id or "")] = definition
    end
    for _, definition in ipairs(items.rows or {}) do
        definitions[tostring(definition.content_id or "")] = definition
    end
    for _, level in ipairs(legacy_levels.rows or {}) do
        local values = {}
        for _, effect in ipairs(level.effects or {}) do
            if FIELD_MAP[tostring(effect.effect_type or "")] then
                values[tostring(effect.effect_type)] = tonumber(effect.value) or 0
            end
        end
        legacy_stats[tostring(level.content_id or "")] = values
    end
end

local function build(player_id, counts, reason)
    local values = {
        attack_flat = 0,
        attack_speed_pct = 0,
        health_flat = 0,
        armor_flat = 0,
        all_attributes_flat = 0,
        lifesteal_pct = 0,
    }
    local sources = {}
    local equipped = event_bus.request(
        events.WEAPON_EQUIPMENT_GET_REQUEST,
        { player_id = player_id }
    )
    local main_hand = equipped and equipped.snapshot
        and equipped.snapshot.main_hand_content_id or ""
    for content_id, quantity in pairs(counts or {}) do
        if (tonumber(quantity) or 0) > 0 then
            content_id = tostring(content_id)
            local definition = definitions[content_id]
            local active = not definition
                or tostring(definition.equipment_slot or "") ~= "main_hand"
                or tostring(content_id) == tostring(main_hand)
            if definition and definition.enabled ~= false and active then
                for stat, field in pairs(FIELD_MAP) do
                    local configured = definition[field]
                    local amount = tonumber(configured)
                    local legacy = tonumber((legacy_stats[content_id] or {})[stat])
                    if amount == nil or (stat ~= "attack_flat"
                        and amount == 0 and legacy and legacy ~= 0) then
                        amount = legacy or 0
                    end
                    if amount ~= 0 then
                        values[stat] = values[stat] + amount
                        sources[stat] = sources[stat] or {}
                        sources[stat][#sources[stat] + 1] = {
                            source_id = content_id,
                            value = amount,
                            stacking_rule = "unique",
                        }
                    end
                end
            end
        end
    end
    local snapshot = {
        player_id = player_id,
        snapshot_complete = true,
        enabled = true,
        values = values,
        sources = sources,
        reason = reason or "changed",
    }
    snapshots[player_id] = snapshot
    event_bus.emit(events.EQUIPMENT_STATS_CHANGED,
        { player_id = player_id, snapshot = snapshot, reason = snapshot.reason })
    return snapshot
end

local function refresh(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    local counts = payload.snapshot and payload.snapshot.counts
    if not counts then
        local inventory = event_bus.request(
            events.CONTENT_INVENTORY_GET_REQUEST,
            { player_id = player_id }
        )
        counts = inventory and inventory.snapshot
            and inventory.snapshot.counts or {}
    end
    build(player_id, counts, payload.reason)
end

function M.init()
    snapshots = {}
    rebuild_definitions()
    event_bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST,
        function(payload)
            local id = tonumber(payload.player_id)
            if id == nil then return { ok = false, snapshot = nil } end
            if not snapshots[id] then
                local inventory = event_bus.request(
                    events.CONTENT_INVENTORY_GET_REQUEST,
                    { player_id = id }
                )
                build(id, inventory and inventory.snapshot
                    and inventory.snapshot.counts or {}, "request")
            end
            return { ok = true, snapshot = snapshots[id] }
        end)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, refresh)
    event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, refresh)
end

return M
