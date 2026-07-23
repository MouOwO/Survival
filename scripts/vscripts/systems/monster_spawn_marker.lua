local spawn_points = require("config/generated/monster_spawn_points")

local M = {}
local LEGACY_NAME = "monsterorn"

local function valid(entity)
    return entity and not entity:IsNull()
end

function M.configured_name()
    local row = spawn_points.by_id and spawn_points.by_id.spawn_wild_boss
    return row and row.hammer_target_name or "monsterborn"
end

function M.find()
    local configured = M.configured_name()
    local marker = Entities:FindByName(nil, configured)
    if valid(marker) then return marker, configured end

    marker = Entities:FindByName(nil, LEGACY_NAME)
    if valid(marker) then
        print("[MonsterSpawnMarker] using legacy marker " .. LEGACY_NAME
            .. "; rebuild map for " .. configured)
        return marker, LEGACY_NAME
    end

    print("[MonsterSpawnMarker] missing marker map="
        .. tostring(GetMapName and GetMapName() or "unknown")
        .. " expected=" .. configured
        .. " legacy=" .. LEGACY_NAME
        .. " hint=compiled_map_may_be_older_than_hammer_source")
    return nil, configured
end

return M