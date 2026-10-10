-- Resolve a bounded, grounded landing site before creating an immobile hub.
-- Never delegate placement to the engine's unbounded clear-space search.
local bus = require("core/event_bus")
local events = require("core/events")
local M = {}
local function valid(unit) return unit and not unit:IsNull() end
local function marker(name)
    if not Entities or not Entities.FindByName then return nil end
    local ok, unit = pcall(Entities.FindByName, Entities, nil, name)
    return ok and valid(unit) and unit:GetAbsOrigin() or nil
end
local function ground(position)
    if not GetGroundPosition then return position end
    local ok, value = pcall(GetGroundPosition, position, nil)
    return ok and value or position
end
local function available(position, anchor, reserved, spacing)
    local result = ground(position)
    if not result then return nil end
    if GridNav and GridNav.IsTraversable and GridNav.IsBlocked then
        -- Water can be traversable; also reject a lower floor than this anchor.
        if math.abs(result.z - anchor.z) > 96 then return nil end
        local query = bus.request(events.GRID_CAN_PLACE_REQUEST, {
            position = result, footprint = { x = 2, y = 2 },
        })
        if query and not query.ok then return nil end
        if query and query.world_position then result = ground(query.world_position) end
        if not result or math.abs(result.z - anchor.z) > 96 then return nil end
        for _, dx in ipairs({-64, 0, 64}) do
            for _, dy in ipairs({-64, 0, 64}) do
                local sample = Vector(result.x + dx, result.y + dy, result.z)
                if not GridNav:IsTraversable(sample) or GridNav:IsBlocked(sample)
                    or math.abs(ground(sample).z - result.z) > 48 then return nil end
            end
        end
    end
    if not GridNav then return result end
    for _, entry in pairs(reserved or {}) do
        local p = entry.position
        if p and valid(entry.unit) then
            local dx, dy = result.x - p.x, result.y - p.y
            if dx * dx + dy * dy < (spacing * 0.8) ^ 2 then return nil end
        end
    end
    return result
end
local function nearby(anchor, index, rule, reserved)
    local spacing = tonumber(rule.building_spacing) or 240
    local offset = tonumber(rule.building_offset_y) or 360
    local function try(dx, dy)
        return available(Vector(anchor.x + (index - 2) * spacing + dx,
            anchor.y + offset + dy, anchor.z), anchor, reserved, spacing)
    end
    local position = try(0, 0)
    if position then return position end
    -- At most 25 candidates, once at creation (or a failed creation retry).
    for ring = 1, 3 do
        for _, offset_pair in ipairs({{0,1},{1,0},{0,-1},{-1,0},{1,1},{1,-1},{-1,1},{-1,-1}}) do
            position = try(offset_pair[1] * spacing * ring, offset_pair[2] * spacing * ring)
            if position then return position end
        end
    end
end
function M.resolve(player_id, index, rule, context, wave, reserved)
    if rule.building_anchor == "player_wall" then
        local buildings = package.loaded["systems/building_system"]
        local wall = buildings and buildings.wall_for_player and buildings.wall_for_player(player_id)
        if valid(wall) then
            local position = nearby(wall:GetAbsOrigin(), index, rule, reserved)
            if position then return position, "player_wall" end
        end
        local slot = context.slot and context.slot(player_id)
        local origin = slot and marker(slot.builder_spawn_marker)
        if origin then
            local position = nearby(ground(origin), index, rule, reserved)
            if position then return position, "builder_spawn" end
        end
        -- A wall-area hub must wait for a safe point in this player's base.
        -- Old platform and wave markers belong to the former map layout;
        -- the wave markers now host portals, so they are not base fallbacks.
        return nil, "safe_hub_position_missing"
    end
    local dedicated = marker("player_" .. player_id .. "_archive_hub_" .. index)
    if dedicated then
        -- Reject a former raised-platform marker if its floor is now water.
        local position = available(dedicated, dedicated, reserved,
            tonumber(rule.building_spacing) or 240)
        if position then return position, "archive_marker" end
    end
    local channel = wave.get_player_spawn_marker(player_id)
    if valid(channel) then
        -- Preserve exact legacy offsets where the navigation API is absent.
        local origin = channel:GetAbsOrigin()
        if not GridNav then
            return Vector(origin.x + (index - 2) * rule.building_spacing,
                origin.y + rule.building_offset_y, origin.z), "legacy_wave_marker"
        end
        local position = nearby(ground(origin), index, rule, reserved)
        if position then return position, "wave_marker" end
    end
    return nil, "safe_hub_position_missing"
end
return M
