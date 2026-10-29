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
local function finite_position(position)
    if not position then return false end
    for _, axis in ipairs({"x", "y", "z"}) do
        local value = tonumber(position[axis])
        if not value or value ~= value or math.abs(value) > 32768 then return false end
    end
    return true
end
local function portal_ground(position)
    -- A portal system spawn must wait for real terrain data. Legacy marker
    -- placement below deliberately retains its original ground fallback.
    if not finite_position(position) or not GetGroundPosition then return nil end
    local ok, result = pcall(GetGroundPosition, position, nil)
    return ok and finite_position(result) and result or nil
end
local function portal_origin(unit)
    if not valid(unit) then return nil end
    local ok, position = pcall(unit.GetAbsOrigin, unit)
    return ok and portal_ground(position) or nil
end
local function portal_unit_overlap(position)
    if not FindUnitsInRadius then return true end
    local ok, units = pcall(FindUnitsInRadius, DOTA_TEAM_GOODGUYS, position, nil, 608,
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
        DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER, false)
    if not ok or type(units) ~= "table" then return true end
    for _, unit in ipairs(units) do
        if valid(unit) and (not unit.IsAlive or unit:IsAlive())
            and not unit.survival_is_grid_preview and not unit.survival_rebirth_scene_display then
            local origin = unit:GetAbsOrigin()
            local hull = tonumber(unit.survival_hull_radius)
                or (unit.GetHullRadius and unit:GetHullRadius()) or 0
            -- The hub's footprint is 128 square, matching the terrain samples.
            local dx = math.max(0, math.abs(origin.x - position.x) - 64)
            local dy = math.max(0, math.abs(origin.y - position.y) - 64)
            if dx * dx + dy * dy <= hull * hull then return true end
        end
    end
    return false
end
local function available(player_id, position, anchor, reserved, spacing, portal_spawn)
    local result
    if portal_spawn then result = portal_ground(position) else result = ground(position) end
    if not result then return nil end
    if portal_spawn and (not GridNav or not GridNav.IsTraversable or not GridNav.IsBlocked) then return nil end
    if GridNav and GridNav.IsTraversable and GridNav.IsBlocked then
        -- Water can be traversable; also reject a lower floor than this anchor.
        if math.abs(result.z - anchor.z) > 96 then return nil end
        -- Portal hubs are system spawns on the lower approach. Ordinary
        -- construction validation only allows the raised player building lawns.
        if not portal_spawn then
            local query = bus.request(events.GRID_CAN_PLACE_REQUEST, {
                player_id = player_id,
                position = result, footprint = { x = 2, y = 2 },
            })
            if query and not query.ok then return nil end
            if query and query.world_position then result = ground(query.world_position) end
        end
        if not result or math.abs(result.z - anchor.z) > 96 then return nil end
        for _, dx in ipairs({-64, 0, 64}) do
            for _, dy in ipairs({-64, 0, 64}) do
                local sample = Vector(result.x + dx, result.y + dy, result.z)
                if portal_spawn then
                    local walked, traversable = pcall(GridNav.IsTraversable, GridNav, sample)
                    local checked, blocked = pcall(GridNav.IsBlocked, GridNav, sample)
                    local landed = portal_ground(sample)
                    if not walked or traversable ~= true or not checked or blocked ~= false
                        or not landed or math.abs(landed.z - result.z) > 48 then return nil end
                elseif not GridNav:IsTraversable(sample) or GridNav:IsBlocked(sample)
                    or math.abs(ground(sample).z - result.z) > 48 then return nil end
            end
        end
        if portal_spawn and GridNav.IsNearbyTree then
            local checked, tree = pcall(GridNav.IsNearbyTree, GridNav, result, 96, true)
            if not checked or tree then return nil end
        end
    end
    if portal_spawn and portal_unit_overlap(result) then return nil end
    if not GridNav and not portal_spawn then return result end
    for _, entry in pairs(reserved or {}) do
        local p = entry.position
        if p and valid(entry.unit) then
            local dx, dy = result.x - p.x, result.y - p.y
            if dx * dx + dy * dy < (spacing * 0.8) ^ 2 then return nil end
        end
    end
    return result
end
local function around_portal(player_id, index, rule, wave, reserved)
    local channel = wave.get_player_spawn_marker(player_id)
    local anchor = portal_origin(channel)
    if not anchor then return nil end
    local spacing = math.max(192, tonumber(rule.building_spacing) or 240)
    local radius = math.max(360, tonumber(rule.building_offset_y) or 360)
    local diagonal = 1 / math.sqrt(2)
    -- Keep the four original cardinal preferences, then use diagonals to
    -- support four owners sharing one entrance (four hubs each).
    local directions = {{0, 1}, {1, 0}, {0, -1}, {-1, 0},
        {diagonal, diagonal}, {diagonal, -diagonal},
        {-diagonal, -diagonal}, {-diagonal, diagonal}}
    local mode_spawns = require("systems/mode_spawn_service")
    local mode_bounds
    if mode_spawns.active() then
        local config = mode_spawns.config()
        if not config then return nil end
        mode_bounds = config.bounds
        if not mode_spawns.contains(mode_bounds, anchor) then return nil end
    end
    local portals = {anchor}
    for id = 0, 3 do
        if id ~= player_id then
            local other = portal_origin(wave.get_player_spawn_marker(id))
            if other then portals[#portals + 1] = other end
        end
    end
    -- At most 24 candidates, all within radius + 2 * spacing of this actual
    -- routed entrance (840 with production rules). Never borrow wall/old-map
    -- markers or extend an unsuccessful search into a different region.
    for ring = 0, 2 do
        for step = 0, 7 do
            local direction = directions[(index - 1 + step) % 8 + 1]
            local distance = radius + ring * spacing
            local position = Vector(anchor.x + direction[1] * distance,
                anchor.y + direction[2] * distance, anchor.z)
            local clear = not mode_bounds or mode_spawns.contains(mode_bounds, position, 64, 64)
            for _, portal in ipairs(portals) do
                local dx, dy = position.x - portal.x, position.y - portal.y
                if dx * dx + dy * dy < 288 ^ 2 then clear = false; break end
            end
            if clear then
                position = available(player_id, position, anchor, reserved, spacing, true)
                if position then return position end
            end
        end
    end
end
local function nearby(player_id, anchor, index, rule, reserved)
    local spacing = tonumber(rule.building_spacing) or 240
    local offset = tonumber(rule.building_offset_y) or 360
    local function try(dx, dy)
        return available(player_id, Vector(anchor.x + (index - 2) * spacing + dx,
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
    if rule.building_anchor == "wave_portal" then
        local position = around_portal(player_id, index, rule, wave, reserved)
        return position, position and "wave_portal" or "safe_hub_position_missing"
    end
    if rule.building_anchor == "player_wall" then
        local buildings = package.loaded["systems/building_system"]
        local wall = buildings and buildings.wall_for_player and buildings.wall_for_player(player_id)
        if valid(wall) then
            local position = nearby(player_id, wall:GetAbsOrigin(), index, rule, reserved)
            if position then return position, "player_wall" end
        end
        -- Dedicated modes resolve their own Hammer lawn; an absent mode marker
        -- must never send this player's hubs back to the ordinary island.
        local origin
        if context.resolve_builder_spawn then
            local spawn = context.resolve_builder_spawn(player_id)
            origin = spawn and spawn.position
        else
            local slot = context.slot and context.slot(player_id)
            origin = slot and marker(slot.builder_spawn_marker)
        end
        if origin then
            local position = nearby(player_id, ground(origin), index, rule, reserved)
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
        local position = available(player_id, dedicated, dedicated, reserved,
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
        local position = nearby(player_id, ground(origin), index, rule, reserved)
        if position then return position, "wave_marker" end
    end
    return nil, "safe_hub_position_missing"
end
return M
