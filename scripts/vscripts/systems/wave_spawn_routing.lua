-- Wall quadrant selects a physical portal; ownership stays with the player.
-- Recompute only when channels/walls change, never on a recurring scan.
local slots = require("config/generated/player_slots")
local rules = require("config/global_rules")
local M = {}
local sides = {"east", "south", "west", "north"}

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
    if position.x >= center.x then
        return position.y >= center.y and "north" or "east"
    end
    return position.y >= center.y and "west" or "south"
end

function M.refresh(channels, wall_by_player, hull_multiplier)
    local portals, center = layout()
    local groups = {}
    for player_id, channel in pairs(channels) do
        channel.default_marker = channel.default_marker or channel.marker
        channel.default_marker_name = channel.default_marker_name or channel.marker_name
        channel.marker, channel.marker_name = channel.default_marker, channel.default_marker_name
        channel.spawn_side, channel.route_error = nil, nil
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

function M.position(channel)
    local position = channel and origin(channel.marker)
    if not position then return nil end
    return Vector(position.x + (channel.spawn_offset_x or 0),
        position.y + (channel.spawn_offset_y or 0), position.z)
end

return M
