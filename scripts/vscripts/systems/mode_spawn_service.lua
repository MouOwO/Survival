-- Named Hammer markers are authoritative. Dedicated modes never borrow a
-- normal-island marker or clamp their coordinates to its building bounds.
local M = {}
local dedicated = { rich = true, cold = true, scourge = true }

function M.mode()
    local setup = package.loaded["systems/match_setup_service"]
    return setup and setup.get_mode and setup.get_mode() or nil
end

function M.active() return dedicated[M.mode()] == true end

function M.config()
    local mode = M.mode()
    if not dedicated[mode] then return nil, "mode_spawn_inactive" end
    local config = require("config/mode_spawn_config")
    if type(GetMapName) == "function" and GetMapName() ~= config.map_name then
        return nil, "mode_spawn_map_mismatch:" .. tostring(mode)
    end
    local row = config.modes and config.modes[mode]
    if not row then return nil, "mode_spawn_config_missing:" .. tostring(mode) end
    return row
end

local function finite(value)
    value = tonumber(value)
    return value and value == value and math.abs(value) < math.huge and value or nil
end

function M.contains(bounds, position, half_x, half_y)
    if not bounds or not position or not finite(position.x) or not finite(position.y) then return false end
    for _, name in ipairs({ "min_x", "max_x", "min_y", "max_y" }) do
        if not finite(bounds[name]) then return false end
    end
    half_x, half_y = half_x or 0, half_y or 0
    return position.x - half_x >= bounds.min_x and position.x + half_x <= bounds.max_x
        and position.y - half_y >= bounds.min_y and position.y + half_y <= bounds.max_y
end

function M.marker(name)
    if type(name) ~= "string" or name == "" or not Entities or not Entities.FindByName then
        return nil, nil, "mode_spawn_marker_missing:" .. tostring(name)
    end
    local ok, entity = pcall(Entities.FindByName, Entities, nil, name)
    if not ok or not entity or (entity.IsNull and entity:IsNull()) or not entity.GetAbsOrigin then
        return nil, nil, "mode_spawn_marker_missing:" .. name
    end
    local located, position = pcall(entity.GetAbsOrigin, entity)
    if not located or not position or not finite(position.x) or not finite(position.y)
        or not finite(position.z) then return nil, nil, "mode_spawn_marker_invalid:" .. name end
    return entity, Vector(position.x, position.y, position.z)
end

function M.landing(position, bounds)
    if not M.contains(bounds, position) then return nil, "mode_spawn_outside_bounds" end
    if not GridNav or not GridNav.IsTraversable or not GridNav.IsBlocked then
        return nil, "mode_spawn_navigation_unavailable"
    end
    local walked, open = pcall(GridNav.IsTraversable, GridNav, position)
    local checked, blocked = pcall(GridNav.IsBlocked, GridNav, position)
    if not walked or open ~= true or not checked or blocked ~= false then
        return nil, "mode_spawn_not_traversable"
    end
    if not GetGroundPosition then return nil, "mode_spawn_ground_unavailable" end
    local ok, ground = pcall(GetGroundPosition, position, nil)
    if not ok or not ground or not finite(ground.z) then return nil, "mode_spawn_ground_invalid" end
    return Vector(position.x, position.y, ground.z)
end

function M.wave_marker(player_id)
    local config, reason = M.config()
    if not config then return nil, reason end
    player_id = tonumber(player_id)
    local name = config.monster_markers and config.monster_markers[player_id]
    local marker, position, missing = M.marker(name)
    if not marker then return nil, missing end
    local landing, invalid = M.landing(position, config.bounds)
    if not landing then return nil, invalid .. ":" .. tostring(name) end
    return { player_id = player_id, marker = marker, marker_name = name,
        mode = M.mode(), position = landing }
end

function M.validate_position(position)
    local config, reason = M.config()
    if not config then return false, reason end
    if not M.contains(config.bounds, position) then return false, "mode_destination_outside_region" end
    return true
end

return M
