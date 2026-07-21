local event_bus = require("core/event_bus")
local events = require("core/events")
local dictionary = require("config/effect_dictionary")

local M = {}
local handlers = {}
local STATIC = {
    attack_flat = true, attack_speed_pct = true, health_flat = true,
    armor_flat = true, all_attributes_flat = true, lifesteal_pct = true,
}

local function numeric(effect)
    local value = tonumber(effect.value)
    if value == nil then return nil, "effect_value_not_number" end
    return value
end

local function object(effect)
    if type(effect.value) ~= "table" then return nil, "effect_value_not_object" end
    return effect.value
end

for effect_type in pairs(STATIC) do
    handlers[effect_type] = { kind = "static", validate = numeric }
end
handlers.critical_chance_pct = { kind = "proc_stat", validate = numeric }
handlers.critical_multiplier = { kind = "proc_stat", validate = numeric }
handlers.attack_gain_on_attack = { kind = "growth", validate = numeric }
handlers.attack_gain_on_player_kill = { kind = "growth", validate = numeric }
handlers.attributes_gain_on_attack = { kind = "growth", validate = numeric }
handlers.aura_attribute_damage = { kind = "periodic", validate = object }
handlers.proc_attribute_damage = { kind = "proc", validate = function(effect)
    local value, err = object(effect)
    if not value then return nil, err end
    local chance = tonumber(value.probability or value.chance_pct or value.chance)
    local radius = tonumber(value.range or value.radius)
    local multiplier = tonumber(value.multiplier)
    local cooldown = tonumber(value.internal_cooldown or value.cooldown or 0)
    if not chance or chance < 0 or chance > 100 then return nil, "proc_chance_invalid" end
    if not radius or radius <= 0 then return nil, "proc_radius_invalid" end
    if not multiplier or multiplier < 0 then return nil, "proc_multiplier_invalid" end
    if cooldown < 0 then return nil, "proc_cooldown_invalid" end
    return value
end }

function M.get(effect_type) return handlers[effect_type] end

function M.validate(effect)
    if type(effect) ~= "table" then return nil, "effect_not_table" end
    local effect_type = tostring(effect.effect_type or "")
    if effect_type == "" then return nil, "effect_type_missing" end
    if not dictionary.is_supported(effect_type) then return nil, "unknown_effect_type" end
    local handler = handlers[effect_type]
    if not handler then return nil, "effect_handler_missing" end
    local value, err = handler.validate(effect)
    if value == nil then return nil, err end
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
        kind = handler.kind }
end

function M.coverage()
    local missing = {}
    for effect_type in pairs(dictionary.definitions or {}) do
        if not handlers[effect_type] then missing[#missing + 1] = effect_type end
    end
    table.sort(missing)
    return #missing == 0, missing
end

function M.init()
    event_bus.handle_request(events.EQUIPMENT_EFFECT_HANDLER_GET_REQUEST,
        function(payload) return { ok = handlers[tostring(payload.effect_type or "")] ~= nil,
            handler = handlers[tostring(payload.effect_type or "")] } end)
end

return M
