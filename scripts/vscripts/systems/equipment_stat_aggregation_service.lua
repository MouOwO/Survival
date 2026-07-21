local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local snapshots = {}
local STATIC = {
    attack_flat = true, attack_speed_pct = true, health_flat = true,
    armor_flat = true, all_attributes_flat = true, lifesteal_pct = true,
}

local function combine(current, value, rule, source_id)
    if rule == "max" then return math.max(current or value, value) end
    if rule == "latest" then return value end
    if rule == "unique" then return current == nil and value or current end
    return (current or 0) + value
end

local function aggregate(payload)
    local source_snapshot = payload.snapshot or {}
    local values, sources, seen = {}, {}, {}
    if source_snapshot.enabled ~= false and source_snapshot.snapshot_complete == true then
        for _, source in ipairs(source_snapshot.sources or {}) do
            for _, effect in ipairs(source.effects or {}) do
                if STATIC[effect.effect_type] then
                    local key = effect.effect_type
                    local value = tonumber(effect.value) or 0
                    local quantity = math.max(1, tonumber(source.quantity) or 1)
                    if effect.stacking_rule == "sum" then value = value * quantity end
                    local unique_key = key .. ":" .. tostring(source.source_id)
                    local accept = effect.stacking_rule ~= "unique"
                        or (values[key] == nil and not seen[unique_key])
                    if accept then
                        values[key] = combine(values[key], value,
                            effect.stacking_rule, source.source_id)
                        seen[unique_key] = true
                        sources[key] = sources[key] or {}
                        sources[key][#sources[key] + 1] = {
                            source_id = source.source_id, value = value,
                            stacking_rule = effect.stacking_rule,
                        }
                    end
                end
            end
        end
    end
    local player_id = tonumber(payload.player_id or source_snapshot.player_id)
    local snapshot = { player_id = player_id, snapshot_complete = true,
        enabled = source_snapshot.enabled ~= false, values = values,
        sources = sources, reason = payload.reason or source_snapshot.reason }
    snapshots[player_id] = snapshot
    event_bus.emit(events.EQUIPMENT_STATS_CHANGED,
        { player_id = player_id, snapshot = snapshot, reason = snapshot.reason })
end

function M.init()
    snapshots = {}
    event_bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST,
        function(payload)
            local id = tonumber(payload.player_id)
            return { ok = id ~= nil, snapshot = id and snapshots[id] or nil }
        end)
    event_bus.subscribe(events.EQUIPMENT_EFFECT_SNAPSHOT_CHANGED, aggregate)
end

return M
