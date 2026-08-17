local player_context = require("systems/player_context_service")

local M = {}
local predicates = {}

predicates.always = function() return true end

predicates.owner_matches = function(instance, payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id ~= nil then return player_id == instance.player_id end
    local unit = payload and (payload.unit or payload.target)
    return unit ~= nil and player_context.is_owned_by(instance.player_id, unit)
end

predicates.base_tower_below_level = function(instance, payload)
    if not predicates.owner_matches(instance, payload) then return false end
    return tostring(payload and payload.building_id or "") == "arrow_tower"
        and (tonumber(payload and payload.level) or 0)
            < (tonumber(instance.params.level_exclusive_max) or 0)
end

predicates.target_is_boss = function(_, payload)
    return payload and (payload.is_boss == true or payload.is_boss == 1)
end

predicates.target_is_slowed = function(_, payload)
    return payload and (payload.target_is_slowed == true
        or payload.target_is_slowed == 1)
end

function M.get(predicate)
    return predicates[tostring(predicate or "")]
end

function M.register_for_test(predicate, handler)
    predicates[predicate] = handler
end

return M