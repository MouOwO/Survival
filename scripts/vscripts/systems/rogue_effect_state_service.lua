local M = {}
local wall_damage_cap_by_player = {}
local wall_health_flat_by_player = {}
local active_effects_by_player = {}
local tower_projection_by_player = {}
local numeric_effects_by_player = {}

function M.reset()
    wall_damage_cap_by_player = {}
    wall_health_flat_by_player = {}
    active_effects_by_player = {}
    tower_projection_by_player = {}
    numeric_effects_by_player = {}
end

function M.add_numeric(player_id, effect_type, value)
    player_id = tonumber(player_id)
    if player_id == nil then return false end
    numeric_effects_by_player[player_id] = numeric_effects_by_player[player_id] or {}
    local key = tostring(effect_type)
    numeric_effects_by_player[player_id][key] =
        (tonumber(numeric_effects_by_player[player_id][key]) or 0)
            + (tonumber(value) or 0)
    return true
end

function M.set_numeric(player_id, effect_type, value)
    player_id = tonumber(player_id)
    if player_id == nil then return false end
    numeric_effects_by_player[player_id] = numeric_effects_by_player[player_id] or {}
    numeric_effects_by_player[player_id][tostring(effect_type)] = tonumber(value) or 0
    return true
end

function M.numeric(player_id, effect_type)
    local values = numeric_effects_by_player[tonumber(player_id)] or {}
    return tonumber(values[tostring(effect_type)]) or 0
end

function M.consume_numeric(player_id, effect_type, value)
    player_id = tonumber(player_id)
    value = math.max(0, tonumber(value) or 0)
    local current = M.numeric(player_id, effect_type)
    if player_id == nil or current < value then return false end
    numeric_effects_by_player[player_id][tostring(effect_type)] = current - value
    return true
end

function M.take_numeric(player_id, effect_type)
    local value = M.numeric(player_id, effect_type)
    if numeric_effects_by_player[tonumber(player_id)] then
        numeric_effects_by_player[tonumber(player_id)][tostring(effect_type)] = 0
    end
    return value
end

function M.add_effect(player_id, effect_type)
    player_id = tonumber(player_id)
    if player_id == nil then return false end
    active_effects_by_player[player_id] = active_effects_by_player[player_id] or {}
    active_effects_by_player[player_id][tostring(effect_type)] = true
    return true
end

function M.has_effect(player_id, effect_type)
    return active_effects_by_player[tonumber(player_id)]
        and active_effects_by_player[tonumber(player_id)][tostring(effect_type)] == true
end

function M.set_tower_projection(player_id, effect_type, value)
    player_id = tonumber(player_id)
    if player_id == nil then return false end
    tower_projection_by_player[player_id] = tower_projection_by_player[player_id] or {}
    tower_projection_by_player[player_id][tostring(effect_type)] = tonumber(value) or 0
    return true
end

function M.tower_projection(player_id, effect_type)
    local values = tower_projection_by_player[tonumber(player_id)] or {}
    return tonumber(values[tostring(effect_type)]) or 0
end

function M.set_wall_damage_cap(player_id, value)
    player_id = tonumber(player_id)
    if player_id == nil then return false end
    wall_damage_cap_by_player[player_id] = math.max(0, math.min(100, tonumber(value) or 0))
    return true
end

function M.wall_damage_cap(unit)
    local player_id = tonumber(unit and unit.survival_player_id)
    return player_id and wall_damage_cap_by_player[player_id] or nil
end

function M.add_wall_health_flat(player_id, value)
    player_id = tonumber(player_id)
    value = tonumber(value)
    if player_id == nil or value == nil or value < 0 then return false end
    wall_health_flat_by_player[player_id] =
        (wall_health_flat_by_player[player_id] or 0) + value
    return true
end

function M.wall_health_flat(player_or_unit)
    local player_id = tonumber(player_or_unit)
        or tonumber(player_or_unit and player_or_unit.survival_player_id)
    return player_id and (wall_health_flat_by_player[player_id] or 0) or 0
end

return M