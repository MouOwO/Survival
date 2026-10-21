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

-- These checks belong to the dedicated-mode spawn transaction, not to the
-- marker cache. A white navigation cell alone does not prove that a complete
-- monster hull fits beside a tree, model edge or change in ground height.
local function spawn_bounds(config, channel)
    local authored = config.monster_bounds and config.monster_bounds[channel.player_id]
    if channel.mode == "scourge" and authored then return authored end
    local p = channel.spawn_position
    local radius = channel.mode == "scourge" and 256 or 192
    return { min_x = math.max(config.bounds.min_x, p.x - radius),
        max_x = math.min(config.bounds.max_x, p.x + radius),
        min_y = math.max(config.bounds.min_y, p.y - radius),
        max_y = math.min(config.bounds.max_y, p.y + radius) }
end

local function ground(position, bounds, radius, reference_z, unit)
    radius = math.max(0, tonumber(radius) or 0) + 16
    if not M.contains(bounds, position, radius, radius) then return nil end
    local center = M.landing(position, bounds)
    if not center or math.abs(center.z - reference_z) > 64 then return nil end
    -- Sample all of the disk at <= 32 world-unit intervals, including its
    -- outer edge. Center-only checks miss cliffs and solid decorative models.
    for ring = 0, math.ceil(radius / 32) do
        local extent = ring == 0 and 0 or math.min(radius, ring * 32)
        local count = extent == 0 and 1 or math.max(8, math.ceil(2 * math.pi * extent / 32))
        for index = 1, count do
            local angle = index / count * math.pi * 2
            local sample = Vector(center.x + math.cos(angle) * extent,
                center.y + math.sin(angle) * extent, center.z)
            local checked = M.landing(sample, bounds)
            if not checked or math.abs(checked.z - center.z) > 24 then return nil end
        end
    end
    if GridNav.IsNearbyTree then
        local ok, nearby = pcall(GridNav.IsNearbyTree, GridNav, center, radius, true)
        if not ok or nearby then return nil end
    end
    return center
end

local function attack_goals(config, channel)
    local _, player = M.marker(config.player_markers and config.player_markers[channel.player_id])
    if not player then return nil end
    local anchor, court = channel.spawn_position, config.player_bounds and config.player_bounds[channel.player_id]
    local x, y = player.x, player.y
    if court then
        x = math.max(court.min_x, math.min(court.max_x, anchor.x))
        y = math.max(court.min_y, math.min(court.max_y, anchor.y))
    end
    local dx, dy = anchor.x - x, anchor.y - y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then return nil end
    dx, dy = dx / length, dy / length
    -- Stay in front of the private court. Its original player marker may now
    -- be occupied by a main city or a wall, and is not a valid path endpoint.
    local goals = {}
    for _, offset in ipairs({0, -128, 128, -256, 256}) do
        local p = Vector(x + dx * 128 - dy * offset, y + dy * 128 + dx * offset, player.z)
        local checked = M.landing(p, config.bounds)
        if checked then goals[#goals + 1] = checked end
    end
    return goals
end

local function path_to_attack(position, goals)
    if not GridNav or not GridNav.CanFindPath or not goals then return false end
    for _, goal in ipairs(goals) do
        local ok, found = pcall(GridNav.CanFindPath, GridNav, position, goal)
        if ok and found == true then return true end
    end
    return false
end

local function spawn_context(channel)
    local config, reason = M.config()
    if not config then return nil, reason end
    if not channel or channel.mode ~= M.mode() or not channel.spawn_position or channel.route_error then
        return nil, "mode_wave_spawn_route_stale"
    end
    local goals = attack_goals(config, channel)
    if not goals or #goals == 0 then return nil, "mode_wave_attack_path_missing" end
    return { bounds = spawn_bounds(config, channel), reference_z = channel.spawn_position.z,
        goals = goals, anchor = channel.spawn_position }
end

local function safe(position, context, radius, unit)
    local checked = ground(position, context.bounds, radius, context.reference_z, unit)
    if checked and path_to_attack(checked, context.goals) then return checked end
end

local function candidates(context, mode, radius)
    local result, bounds, anchor = {}, context.bounds, context.anchor
    radius = math.max(0, tonumber(radius) or 0) + 16
    local function add(x, y) result[#result + 1] = Vector(x, y, anchor.z) end
    if mode == "scourge" then
        local x1, x2, y1, y2 = bounds.min_x + radius, bounds.max_x - radius,
            bounds.min_y + radius, bounds.max_y - radius
        if x1 > x2 or y1 > y2 then return result end
        for _ = 1, 12 do
            local function random_unit() return RandomFloat and RandomFloat(0, 1) or math.random() end
            add(x1 + random_unit() * (x2 - x1), y1 + random_unit() * (y2 - y1))
        end
    end
    add(anchor.x, anchor.y)
    -- Bounded deterministic recovery also handles repeated/randomly blocked
    -- draws. It never falls back to an unchecked or another player's court.
    for _, ring in ipairs({64, 128, 192, 256}) do
        for index = 1, 8 do
            local angle = index / 8 * math.pi * 2
            add(anchor.x + math.cos(angle) * ring, anchor.y + math.sin(angle) * ring)
        end
    end
    return result
end

function M.wave_position(channel, radius)
    local context, reason = spawn_context(channel)
    if not context then return nil, reason end
    for _, candidate in ipairs(candidates(context, channel.mode, radius)) do
        local checked = safe(candidate, context, radius)
        if checked then return checked end
    end
    return nil, "mode_wave_safe_spawn_missing"
end

function M.place_wave_unit(unit, channel, position, radius)
    local context, reason = spawn_context(channel)
    if not context then return false, reason end
    local choices = { position }
    for _, candidate in ipairs(candidates(context, channel.mode, radius)) do choices[#choices + 1] = candidate end
    local attempts = 0
    for _, candidate in ipairs(choices) do
        local checked = safe(candidate, context, radius, unit)
        if checked then
            attempts = attempts + 1
            local ok = pcall(FindClearSpaceForUnit, unit, checked, true)
            local read, actual = pcall(unit.GetAbsOrigin, unit)
            -- Native clear-space searches may slide around units/models. The
            -- resulting hull must pass the same range/ground/path checks.
            if ok and read and actual then
                local result = safe(actual, context, radius, unit)
                if result and math.abs(actual.z - result.z) <= 64 then return true end
            end
            if attempts >= 4 then break end
        end
    end
    return false, "mode_wave_native_landing_unsafe"
end

return M
