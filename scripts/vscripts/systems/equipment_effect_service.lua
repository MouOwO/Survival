local event_bus = require("core/event_bus")
local events = require("core/events")
local dictionary = require("config/effect_dictionary")
local level_effects = require("config/item_level_effects")
local equipment_definitions = require("config/equipment_definitions")

local M = {}
local snapshots = {}
local invalid_by_content = {}
local inventory_by_player = {}

local function validate_effect(effect)
    if type(effect) ~= "table" then return nil, "effect_not_table" end
    local effect_type = tostring(effect.effect_type or "")
    if not dictionary.is_supported(effect_type) then return nil, "unknown_effect_type" end
    local response = event_bus.request(events.EQUIPMENT_EFFECT_HANDLER_GET_REQUEST,
        { effect_type = effect_type })
    if not response or not response.ok or not response.handler then
        return nil, "effect_handler_missing"
    end
    local value = effect.value
    local expected = dictionary.get(effect_type).value_type
    if (expected == "number" or expected == "percent") and tonumber(value) == nil then
        return nil, "effect_value_not_number"
    end
    if expected == "object" and type(value) ~= "table" then
        return nil, "effect_value_not_object"
    end
    local validated, validation_error = response.handler.validate(effect)
    if validated == nil then return nil, validation_error or "effect_value_invalid" end
    local raw_rule = effect.stacking_rule
        or (type(effect.value) == "table" and effect.value.stacking)
        or dictionary.get(effect_type).stacking or "sum"
    local aliases = { replace_by_source = "unique", add_per_event = "sum",
        single_aura_per_source = "unique", independent_proc_per_source = "unique" }
    local rule = aliases[tostring(raw_rule)] or tostring(raw_rule)
    if rule ~= "sum" and rule ~= "max" and rule ~= "unique" and rule ~= "latest" then
        return nil, "stacking_rule_invalid"
    end
    return { effect_type = effect_type, value = value, stacking_rule = rule,
        mode = dictionary.get(effect_type).mode }
end

local function validate_configs()
    invalid_by_content = {}
    for content_id, snapshot in pairs(level_effects.by_content_id or {}) do
        local errors = {}
        if type(snapshot) ~= "table" or snapshot.snapshot_complete ~= true
            or tostring(snapshot.content_id or "") ~= tostring(content_id)
            or type(snapshot.effects) ~= "table" then
            errors[#errors + 1] = "effect_snapshot_incomplete"
        else
            for index, effect in ipairs(snapshot.effects) do
                local _, err = validate_effect(effect)
                if err then errors[#errors + 1] = tostring(index) .. ":" .. err end
            end
        end
        if #errors > 0 then
            invalid_by_content[content_id] = errors
            print("[EQUIPMENT_EFFECT_REJECT] content_id=" .. tostring(content_id)
                .. " errors=" .. table.concat(errors, ","))
        end
    end
    for _, row in ipairs(level_effects.invalid or {}) do
        local id = tostring(row.content_id or "unknown")
        invalid_by_content[id] = invalid_by_content[id] or {}
        invalid_by_content[id][#invalid_by_content[id] + 1] = "unknown_effect_type:"
            .. tostring(row.effect_type or "")
        print("[EQUIPMENT_EFFECT_UNKNOWN] content_id=" .. id
            .. " effect_type=" .. tostring(row.effect_type or "") .. " enabled=false")
    end
end

local function build(player_id, instances, reason)
    local sources, errors = {}, {}
    local equipped = event_bus.request(events.WEAPON_EQUIPMENT_GET_REQUEST,
        { player_id = player_id })
    local main_hand = equipped and equipped.snapshot
        and equipped.snapshot.main_hand_content_id or ""
    for content_id, instance in pairs(instances or {}) do
        local quantity = math.max(0, math.floor(tonumber(instance.quantity) or 0))
        local configured = level_effects.by_content_id[content_id]
        local metadata = equipment_definitions.by_content_id[content_id]
        local active = not metadata or metadata.slot ~= "main_hand" or content_id == main_hand
        if quantity > 0 and configured and active then
            if invalid_by_content[content_id] then
                errors[content_id] = invalid_by_content[content_id]
            else
                local effects, valid = {}, true
                for _, raw in ipairs(configured.effects or {}) do
                    local effect, err = validate_effect(raw)
                    if not effect then valid = false; errors[content_id] = { err }; break end
                    effects[#effects + 1] = effect
                end
                if valid then sources[#sources + 1] = {
                    source_id = content_id, content_id = content_id,
                    quantity = quantity, effects = effects,
                } end
            end
        end
    end
    table.sort(sources, function(a, b) return a.source_id < b.source_id end)
    local snapshot = { player_id = player_id, snapshot_complete = true,
        enabled = next(errors) == nil, sources = sources, errors = errors,
        reason = reason or "changed" }
    snapshots[player_id] = snapshot
    event_bus.emit(events.EQUIPMENT_EFFECT_SNAPSHOT_CHANGED,
        { player_id = player_id, snapshot = snapshot, reason = snapshot.reason })
    return snapshot
end

local function refresh(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    if payload.snapshot and payload.snapshot.counts then
        local instances = {}
        for content_id, quantity in pairs(payload.snapshot.counts) do
            instances[content_id] = { content_id = content_id, quantity = quantity }
        end
        inventory_by_player[player_id] = instances
    elseif payload.instances then
        inventory_by_player[player_id] = payload.instances
    end
    build(player_id, inventory_by_player[player_id] or {}, payload.reason)
end

function M.init()
    snapshots, inventory_by_player = {}, {}
    validate_configs()
    event_bus.handle_request(events.EQUIPMENT_EFFECT_SNAPSHOT_GET_REQUEST,
        function(payload)
            local id = tonumber(payload.player_id)
            return { ok = id ~= nil, snapshot = id and snapshots[id] or nil }
        end)
    event_bus.subscribe(events.EQUIPMENT_INSTANCE_CHANGED, refresh)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, refresh)
    event_bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, refresh)
    print("[EQUIPMENT_EFFECT_INIT] validated_fail_closed")
end

return M
