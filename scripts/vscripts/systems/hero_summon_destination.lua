local destination_validation = require("systems/destination_validation_service")
local placement = require("config/grid_placement_config")
local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local SEARCH_RADIUS, STEP, HERO_RADIUS, MAX_HEIGHT_DELTA = 640, 64, 32, 64
local NO_DESTINATION = "主城周围没有安全落点，请清理附近障碍后重试"
local clearance = {}
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
local function player_main_city(player_id)
    local id = tonumber(player_id)
    if not id or id < 0 or id ~= math.floor(id) then return nil end
    -- Query live building state instead of a map marker or cached position.
    -- Filtering ownership here also protects games with shared player teams.
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, {player_id = id})
    for _, building in ipairs(result and result.ok and result.buildings or {}) do
        local unit = building.unit
        if building.building_id == "main_city" and tonumber(building.player_id) == id
            and not building.constructing and valid(unit)
            and type(unit.IsAlive) == "function" and unit:IsAlive() then
            return unit
        end
    end
    return nil
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
local function nearby_obstacles(origin, anchor)
    if type(FindUnitsInRadius) ~= "function" then return nil, "occupancy_unavailable" end
    local team = valid(anchor) and anchor:GetTeamNumber() or DOTA_TEAM_GOODGUYS
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
    -- Compare with the live city height, not potentially underwater ground
    -- directly beneath a rejected candidate at the edge of the player island.
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
    local city = player_main_city(player_id)
    if not city then
        rejected("main_city_not_found")
        return nil, "玩家主城尚未建造，无法召唤英雄", metadata
    end
    metadata.source = "main_city"
    local origin = copied_position(city:GetAbsOrigin())
    if not origin then rejected("spawn_anchor_unavailable"); return nil, NO_DESTINATION, metadata end
    local obstacles, reason = nearby_obstacles(origin, city)
    if not obstacles then rejected(reason); return nil, NO_DESTINATION, metadata end
    local hull = tonumber(city.survival_hull_radius)
        or (type(city.GetHullRadius) == "function" and tonumber(city:GetHullRadius())) or 0
    if not finite(hull) or hull < 0 then hull = 0 end
    -- Keep the hero visibly outside the city. Expand concentric rings on all
    -- sides, starting in front; never spill into a distant altar/training room.
    local first_radius = math.ceil(math.max(256, hull + HERO_RADIUS + STEP) / STEP) * STEP
    local forward = type(city.GetForwardVector) == "function" and city:GetForwardVector() or nil
    local fx, fy = 1, 0
    if forward and finite(forward.x) and finite(forward.y) then
        local length = math.sqrt(forward.x * forward.x + forward.y * forward.y)
        if length > 0 then fx, fy = forward.x / length, forward.y / length end
    end
    for radius = first_radius, SEARCH_RADIUS, STEP do
        for index = 0, 15 do
            local angle = index * math.pi / 8
            local c, s = math.cos(angle), math.sin(angle)
            local offset = {x = (fx * c - fy * s) * radius, y = (fy * c + fx * s) * radius}
            metadata.attempts = metadata.attempts + 1
            local position, failure = candidate(origin, offset, origin.z, obstacles)
            if position then
                metadata.grounded, metadata.distance = true, radius
                return position, nil, metadata
            end
            rejected(failure)
        end
    end
    metadata.last_reason = metadata.last_reason or "main_city_clearance_exceeds_search"
    return nil, NO_DESTINATION, metadata
end

return M
