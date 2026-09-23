-- Resolve the four players' ordinary and 15x rooms without mutating CSV data.
-- Maps predating the private-room layout retain their original shared markers.
local locations = require("config/generated/challenge_locations")
local M = {}

local function prefix_for(name, player_id)
    if player_id == nil or not Entities or not name then return nil end
    local base = name:match("^(challenge_0[1-4])_")
        or (name:match("^endless_cycle_sanctum_") and "endless_cycle_sanctum")
    if not base then return nil end
    local prefix = "player_" .. tostring(player_id) .. "_"
    local entry = Entities:FindByName(nil, prefix .. base .. "_entry")
    return entry and not entry:IsNull() and prefix or nil
end

function M.marker_name(name, player_id)
    local prefix = prefix_for(name, player_id)
    return prefix and prefix .. name or name
end

function M.resolve(location_id, player_id)
    local row = locations.by_id[location_id]
    if not row or not prefix_for(row.entry_target_name, player_id) then return row end
    local result = {}
    for k, v in pairs(row) do result[k] = v end
    result.entry_target_name = M.marker_name(row.entry_target_name, player_id)
    result.home_target_name = M.marker_name(row.home_target_name, player_id)
    result.spawn_target_names = {}
    for i, name in ipairs(row.spawn_target_names or {}) do
        result.spawn_target_names[i] = M.marker_name(name, player_id)
    end
    -- The approved room floors are 900 x 900; keep targets in their own room.
    result.room_radius = 640
    return result
end

return M
