local grid_config = require("config/grid_placement_config")
local geometry = require("core/building_grid_geometry")
local placement = require("systems/grid_placement_system")
local destination = require("systems/destination_validation_service")
local M = {}
local CLEARANCE = 32
local ARRIVAL_DISTANCE = 16
local EXTRA_SEARCH = 192

local function valid(unit)
    return unit and not unit:IsNull() and (not unit.IsAlive or unit:IsAlive())
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function squared_distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy
end
local function half_size(definition)
    local size = tonumber(grid_config.cell_size) or 64
    local footprint = geometry.footprint(definition.footprint)
    local hull = math.max(0, tonumber(definition.hull_radius) or 0)
    return math.max(footprint.x * size * 0.5, hull),
        math.max(footprint.y * size * 0.5, hull)
end
local function outside_building(position, definition, origin, padding)
    local x, y = half_size(definition)
    return math.abs(position.x - origin.x) > x + (padding or 0)
        or math.abs(position.y - origin.y) > y + (padding or 0)
end
local function unit_hull(unit)
    return math.max(0, tonumber(unit.survival_hull_radius)
        or unit.GetHullRadius and tonumber(unit:GetHullRadius()) or 0)
end
local function near_units(caster, origin, radius)
    local ok, units = pcall(FindUnitsInRadius, caster:GetTeamNumber(), origin,
        nil, radius + (tonumber(grid_config.max_unit_hull_radius) or 512),
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING,
        DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER, false)
    return ok and units or nil
end
local function grounded_clear(caster, candidate, reference_height, units)
    local bounds = grid_config.build_bounds
    local margin = math.max(16, unit_hull(caster))
    if bounds and (candidate.x - margin < bounds.min_x or candidate.x + margin > bounds.max_x
        or candidate.y - margin < bounds.min_y or candidate.y + margin > bounds.max_y) then return nil end
    local current_height
    for _, offset in ipairs({{0, 0}, {margin, 0}, {-margin, 0}, {0, margin}, {0, -margin}}) do
        local sample = Vector(candidate.x + offset[1], candidate.y + offset[2], candidate.z)
        local ok, height = pcall(GetGroundHeight, sample, caster)
        if not ok or not finite(height) or math.abs(height - reference_height) > 48 then return nil end
        if current_height and math.abs(height - current_height) > 32 then return nil end
        current_height = current_height or height
        sample.z = height
        local checked, allowed = pcall(destination.validate, sample, caster)
        if not checked or not allowed or placement.is_position_occupied(sample) then return nil end
    end
    candidate.z = current_height
    for _, unit in ipairs(units or {}) do
        if unit ~= caster and valid(unit) and not unit.survival_is_grid_preview then
            local other = unit:GetAbsOrigin()
            if math.abs(other.z - candidate.z) <= 48 then
                local radius = unit_hull(unit) + margin
                if squared_distance(other, candidate) <= radius * radius then return nil end
                local footprint = unit.survival_grid_footprint
                if footprint then
                    local size = tonumber(grid_config.cell_size) or 64
                    if math.abs(other.x - candidate.x) <= (tonumber(footprint.x) or 2) * size * 0.5 + margin
                        and math.abs(other.y - candidate.y) <= (tonumber(footprint.y) or 2) * size * 0.5 + margin then return nil end
                end
            end
        end
    end
    return candidate
end

function M.find(caster, definition, origin)
    if not valid(caster) or not origin then return nil end
    local source = caster:GetAbsOrigin()
    local ok, height = pcall(GetGroundHeight, origin, caster)
    if not ok or not finite(height) then return nil end
    local x, y = half_size(definition)
    local clearance = CLEARANCE + unit_hull(caster)
    local candidates, seen = {}, {}
    local function add(dx, dy)
        local key = string.format("%.3f:%.3f", dx, dy)
        if seen[key] then return end
        seen[key] = true
        local point = Vector(origin.x + dx, origin.y + dy, height)
        candidates[#candidates + 1] = {point = point, distance = squared_distance(source, point)}
    end
    local function clamp(value, extent) return math.max(-extent, math.min(extent, value)) end
    for ring = 0, EXTRA_SEARCH, 64 do
        local ex, ey = x + clearance + ring, y + clearance + ring
        -- The nearest projections on all four edges are considered before the
        -- evenly spaced alternatives; ties are stable for repeat orders.
        local dx, dy = clamp(source.x - origin.x, ex), clamp(source.y - origin.y, ey)
        add(dx, ey); add(dx, -ey); add(ex, dy); add(-ex, dy)
        local count = math.max(1, math.ceil(math.max(ex, ey) * 2 / 64))
        for index = 0, count do
            local ratio = index / count * 2 - 1
            add(ex * ratio, ey); add(ex * ratio, -ey)
            add(ex, ey * ratio); add(-ex, ey * ratio)
        end
    end
    table.sort(candidates, function(left, right)
        if math.abs(left.distance - right.distance) > 0.001 then return left.distance < right.distance end
        if left.point.x ~= right.point.x then return left.point.x < right.point.x end
        return left.point.y < right.point.y
    end)
    local units = near_units(caster, origin, math.max(x, y) + clearance + EXTRA_SEARCH)
    if not units then return nil end
    for _, candidate in ipairs(candidates) do
        local point = grounded_clear(caster, candidate.point, height, units)
        if point then
            local path_ok, reachable = pcall(function() return GridNav:CanFindPath(source, point) end)
            if path_ok and reachable == true then return point end
        end
    end
    return nil -- No unchecked fallback into water, buildings or a disconnected island.
end

function M.ready(caster, definition, origin, work_position)
    if not valid(caster) or not work_position then return false end
    local position = caster:GetAbsOrigin()
    if squared_distance(position, work_position) > ARRIVAL_DISTANCE * ARRIVAL_DISTANCE
        or not outside_building(position, definition, origin, unit_hull(caster) + 8) then return false end
    local units = near_units(caster, position, CLEARANCE)
    if not units then return false end
    return grounded_clear(caster, Vector(position.x, position.y, position.z), work_position.z, units) ~= nil
end

return M