-- Wall quadrant selects a physical portal; ownership stays with the player.
-- Recompute only when channels/walls change, never on a recurring scan.
local slots = require("config/generated/player_slots")
local rules = require("config/global_rules")
local M = {}
local sides = {"east", "south", "west", "north"}
local legacy_quadrant_sides = {
    northeast = "north", southeast = "east",
    southwest = "south", northwest = "west",
}
local quadrant_sides = legacy_quadrant_sides
if GetMapName and GetMapName() == "template_map" then
    quadrant_sides = require("config/map_layouts/template_map").wave_spawn_side_by_wall_quadrant
        or legacy_quadrant_sides
end

local function origin(entity)
    if not entity then return nil end
    local ok, position = pcall(function()
        if entity:IsNull() then return nil end
        return entity:GetAbsOrigin()
    end)
    if not ok or not position then return nil end
    for _, axis in ipairs({"x", "y", "z"}) do
        local value = tonumber(position[axis])
        if not value or value ~= value or math.abs(value) > 32768 then return nil end
    end
    return position
end

local function layout()
    local portals, x, y = {}, 0, 0
    for _, side in ipairs(sides) do
        local slot = (slots.by_id or {})[side]
        if not slot or slot.enabled == false or not Entities or not Entities.FindByName then return nil end
        local ok, marker = pcall(Entities.FindByName, Entities, nil, slot.wave_spawn_marker)
        local position = ok and origin(marker) or nil
        if not position then return nil end
        portals[side] = {marker = marker, name = slot.wave_spawn_marker, position = position}
        x, y = x + position.x, y + position.y
    end
    return portals, {x = x / 4, y = y / 4}
end

function M.side_for(position, center)
    local quadrant
    if position.x >= center.x then
        quadrant = position.y >= center.y and "northeast" or "southeast"
    else
        quadrant = position.y >= center.y and "northwest" or "southwest"
    end
    return quadrant_sides[quadrant]
end

local function space_groups(groups, hull_multiplier)
    local spacing = math.max(tonumber(rules.wave_shared_spawn_spacing) or 80,
        2 * (tonumber(rules.wave_ground_monster_hull_radius) or 32)
            * (tonumber(hull_multiplier) or 1))
    for _, group in pairs(groups) do
        table.sort(group, function(a, b) return a.player_id < b.player_id end)
        for index, channel in ipairs(group) do
            local offset = (index - (#group + 1) / 2) * spacing
            if channel.spawn_side == "north" or channel.spawn_side == "south" then
                channel.spawn_offset_x = offset
            else
                channel.spawn_offset_y = offset
            end
        end
    end
end

local function shared_base_route(player_id, wall_index, config, mode)
    if not config then return nil, "mode_spawn_config_missing:" .. mode end
    local function wall_position()
        if not wall_index or type(EntIndexToHScript) ~= "function" then return nil end
        local ok, wall = pcall(EntIndexToHScript, wall_index)
        return ok and origin(wall) or nil
    end
    -- Rich players can move their defensive wall to another court while the
    -- city stays put. Cold retains its established main-city-first routing.
    local position = mode == "rich" and wall_position() or nil
    if not position then
        local buildings = package.loaded["systems/building_system"]
        local city = buildings and buildings.main_city_for_player and buildings.main_city_for_player(player_id)
        position = origin(city) or wall_position()
    end
    if not position then return player_id end
    local mode_spawns = require("systems/mode_spawn_service")
    local courts = config.player_build_bounds or config.player_bounds
    for id = 0, 3 do
        if mode_spawns.contains(courts and courts[id], position) then return id end
    end
    return nil, mode .. "_wave_base_outside_courts"
end

function M.refresh(channels, wall_by_player, hull_multiplier)
    local setup = package.loaded["systems/match_setup_service"]
    local mode = setup and setup.get_mode and setup.get_mode()
    if mode == "rich" or mode == "cold" or mode == "scourge" or mode == "ruins" then
        local mode_spawns = require("systems/mode_spawn_service")
        local shared = mode == "cold" or mode == "rich"
        local config, groups = shared and mode_spawns.config() or nil, {}
        for player_id, channel in pairs(channels) do
            local route_id, route_error = player_id, nil
            if shared then route_id, route_error = shared_base_route(player_id, wall_by_player[player_id], config, mode) end
            local selected, reason
            if not route_error then selected, reason = mode_spawns.wave_marker(player_id, route_id) end
            channel.spawn_offset_x, channel.spawn_offset_y = 0, 0
            channel.mode = mode
            channel.route_id = route_id
            channel.spawn_side = nil
            if selected then
                channel.marker, channel.marker_name = selected.marker, selected.marker_name
                channel.spawn_position = selected.position
                channel.route_error = nil
                if shared then
                    if mode == "rich" then channel.spawn_side = sides[route_id + 1] end
                    groups[selected.marker_name] = groups[selected.marker_name] or {}
                    groups[selected.marker_name][#groups[selected.marker_name] + 1] = channel
                end
            else
                channel.marker, channel.spawn_position = nil, nil
                channel.route_error = route_error or reason or "mode_wave_spawn_missing"
            end
        end
        -- Snow arrows run along world X; rich entrances point toward their
        -- actual court. Only the formation axis changes, never wave ownership.
        if shared then space_groups(groups, hull_multiplier) end
        return
    end
    local portals, center = layout()
    local groups = {}
    for player_id, channel in pairs(channels) do
        channel.default_marker = channel.default_marker or channel.marker
        channel.default_marker_name = channel.default_marker_name or channel.marker_name
        channel.marker, channel.marker_name = channel.default_marker, channel.default_marker_name
        channel.mode, channel.spawn_position = nil, nil
        channel.spawn_side, channel.route_error, channel.route_id = nil, nil, nil
        channel.spawn_offset_x, channel.spawn_offset_y = 0, 0
        local wall_index = wall_by_player[player_id]
        local wall
        if wall_index and type(EntIndexToHScript) == "function" then
            local ok, unit = pcall(EntIndexToHScript, wall_index)
            if ok then wall = unit end
        end
        local wall_position = origin(wall)
        if wall_position then
            if not portals then
                channel.marker, channel.route_error = nil, "wave_spawn_layout_incomplete"
            else
                local side = M.side_for(wall_position, center)
                channel.marker, channel.marker_name = portals[side].marker, portals[side].name
                channel.spawn_side = side
            end
        end
        if channel.marker then
            local group_key = channel.marker_name or tostring(channel.marker)
            groups[group_key] = groups[group_key] or {}
            groups[group_key][#groups[group_key] + 1] = channel
            if not channel.spawn_side and portals then
                for _, side in ipairs(sides) do
                    if channel.marker_name == portals[side].name then channel.spawn_side = side end
                end
            end
        end
    end
    space_groups(groups, hull_multiplier)
end

function M.position(channel)
    if channel and channel.mode then
        local position = channel.marker and channel.spawn_position
        if not position or channel.route_error then return nil end
        return Vector(position.x + (channel.spawn_offset_x or 0),
            position.y + (channel.spawn_offset_y or 0), position.z)
    end
    local position = channel and origin(channel.marker)
    if not position then return nil end
    return Vector(position.x + (channel.spawn_offset_x or 0),
        position.y + (channel.spawn_offset_y or 0), position.z)
end

return M
