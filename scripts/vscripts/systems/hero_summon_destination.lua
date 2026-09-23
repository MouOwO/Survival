local destination_validation = require("systems/destination_validation_service")
local placement = require("config/grid_placement_config")

local M = {}
local SEARCH_RADIUS, STEP, HERO_RADIUS, MAX_HEIGHT_DELTA = 384, 64, 32, 64
local NO_DESTINATION = "英雄出生点和祭坛周围没有安全落点，请清理附近障碍后重试"
local offsets, clearance = {}, {}
for x = -SEARCH_RADIUS, SEARCH_RADIUS, STEP do
    for y = -SEARCH_RADIUS, SEARCH_RADIUS, STEP do
        local squared = x * x + y * y
        if squared <= SEARCH_RADIUS * SEARCH_RADIUS then
            offsets[#offsets + 1] = {x = x, y = y, squared = squared}
        end
    end
end
table.sort(offsets, function(a, b)
    if a.squared ~= b.squared then return a.squared < b.squared end
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
end)
for index = 0, 7 do
    local angle = index * math.pi / 4
    clearance[#clearance + 1] = {x = math.cos(angle) * HERO_RADIUS, y = math.sin(angle) * HERO_RADIUS}
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function valid(entity)
    return entity and type(entity.IsNull) == "function" and not entity:IsNull()
end
local function copied_position(position)
    if not position or not finite(position.x) or not finite(position.y) or not finite(position.z) then return nil end
    return Vector(position.x, position.y, position.z)
end
local function method_true(unit, method)
    if type(unit[method]) ~= "function" then return false end
    local ok, value = pcall(unit[method], unit)
    return ok and value == true
end
local function phased(unit)
    if method_true(unit, "IsPhased") then return true end
    if type(unit.HasModifier) == "function" then
        -- The hidden native-hero anchor deliberately has NO_UNIT_COLLISION.
        -- Hidden wall collision barriers are NOT skipped merely for NoDraw.
        for _, name in ipairs({"modifier_phased", "modifier_survival_placeholder_anchor"}) do
            local ok, value = pcall(unit.HasModifier, unit, name)
            if ok and value == true then return true end
        end
    end
    return false
end
local function nearby_obstacles(origin, altar)
    if type(FindUnitsInRadius) ~= "function" then return nil, "occupancy_unavailable" end
    local team = valid(altar) and altar:GetTeamNumber() or DOTA_TEAM_GOODGUYS
    local ok, units = pcall(FindUnitsInRadius, team, origin, nil,
        SEARCH_RADIUS + HERO_RADIUS + (tonumber(placement.max_unit_hull_radius) or 512),
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
        DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER, false)
    if not ok or type(units) ~= "table" then return nil, "occupancy_query_failed" end
    local result = {}
    for _, unit in ipairs(units) do
        if valid(unit) and not unit.survival_is_grid_preview
            and (not unit.IsAlive or method_true(unit, "IsAlive")) and not phased(unit) then
            local hull = tonumber(unit.survival_hull_radius)
            if hull == nil and type(unit.GetHullRadius) == "function" then
                local hull_ok, value = pcall(unit.GetHullRadius, unit)
                if hull_ok then hull = tonumber(value) end
            end
            if finite(hull) and hull > 0 then
                local position_ok, position = pcall(unit.GetAbsOrigin, unit)
                position = position_ok and copied_position(position) or nil
                if position then result[#result + 1] = {position = position, radius = hull + HERO_RADIUS} end
            end
        end
    end
    return result
end
local function grounded(position, anchor_height)
    if type(GetGroundHeight) ~= "function" then return nil, "ground_height_unavailable" end
    local ok, height = pcall(GetGroundHeight, position, nil)
    if not ok or not finite(height) then return nil, "ground_height_unavailable" end
    position.z = height
    local validation_ok, accepted, reason = pcall(destination_validation.validate_hero_position, position)
    if not validation_ok then return nil, "destination_validation_failed" end
    if not accepted then return nil, reason or "invalid_destination" end
    -- Compare with the authored anchor height, not the potentially underwater
    -- ground directly beneath an invalid marker or altar-front candidate.
    if math.abs(height - anchor_height) > MAX_HEIGHT_DELTA then return nil, "destination_height_mismatch" end
    return position
end
local function candidate(origin, offset, anchor_height, obstacles)
    local position, reason = grounded(Vector(origin.x + offset.x, origin.y + offset.y, origin.z), anchor_height)
    if not position then return nil, reason end
    for _, sample in ipairs(clearance) do
        local edge, edge_reason = grounded(Vector(position.x + sample.x, position.y + sample.y, position.z), anchor_height)
        if not edge then return nil, "clearance_" .. tostring(edge_reason) end
        if math.abs(edge.z - position.z) > MAX_HEIGHT_DELTA then return nil, "clearance_height_mismatch" end
    end
    for _, obstacle in ipairs(obstacles) do
        local other = obstacle.position
        if math.abs(other.z - position.z) <= MAX_HEIGHT_DELTA then
            local dx, dy = position.x - other.x, position.y - other.y
            if dx * dx + dy * dy < obstacle.radius * obstacle.radius then return nil, "destination_occupied" end
        end
    end
    return position
end

function M.resolve(altar, definition, player_id)
    local metadata = {attempts = 0, rejected = {}, grounded = false}
    local function rejected(reason)
        metadata.last_reason = reason
        metadata.rejected[reason] = (metadata.rejected[reason] or 0) + 1
    end
    local function search(origin, anchor_height, source)
        local obstacles, reason = nearby_obstacles(origin, altar)
        if not obstacles then rejected(reason); return nil end
        for _, offset in ipairs(offsets) do
            metadata.attempts = metadata.attempts + 1
            local position, failure = candidate(origin, offset, anchor_height, obstacles)
            if position then
                metadata.source, metadata.grounded = source, true
                metadata.distance = math.sqrt(offset.squared)
                return position
            end
            rejected(failure)
        end
    end
    local id = tonumber(player_id)
    if id and id >= 0 and id == math.floor(id) and Entities and type(Entities.FindByName) == "function" then
        local ok, marker = pcall(Entities.FindByName, Entities, nil, "player_" .. tostring(id) .. "_hero_spawn")
        if ok and valid(marker) then
            local origin = copied_position(marker:GetAbsOrigin())
            if origin then
                local position = search(origin, origin.z, "marker")
                if position then return position, nil, metadata end
            end
        end
    end
    if valid(altar) then
        local origin = copied_position(altar:GetAbsOrigin())
        local forward = altar:GetForwardVector()
        if origin and forward and finite(forward.x) and finite(forward.y) then
            local length = math.sqrt(forward.x * forward.x + forward.y * forward.y)
            local offset = tonumber(definition and definition.spawn_offset) or 260
            if length > 0 and finite(offset) and offset >= 0 then
                local position = search(Vector(origin.x + forward.x / length * offset,
                    origin.y + forward.y / length * offset, origin.z), origin.z, "altar")
                if position then return position, nil, metadata end
            end
        end
    end
    metadata.last_reason = metadata.last_reason or "spawn_anchor_unavailable"
    return nil, NO_DESTINATION, metadata
end

return M
