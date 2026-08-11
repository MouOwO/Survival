local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/grid_placement_config")
local region_service = require("systems/forbidden_region_service")

local M = {}
local occupied = {}
local marker_regions = {}

local function number(value, fallback)
    local result = tonumber(value)
    if result == nil then return fallback end
    return result
end

local function normalized_footprint(source)
    source = source or {}
    local minimum = config.minimum_footprint or { x = 2, y = 2 }
    local subdivision = math.max(1, math.floor(number(
        config.footprint_subdivision,
        1
    )))
    return {
        x = math.floor(math.max(
            number(source.x, minimum.x),
            number(minimum.x, 2)
        )) * subdivision,
        y = math.floor(math.max(
            number(source.y, minimum.y),
            number(minimum.y, 2)
        )) * subdivision,
    }
end

local function snap_anchor(position)
    local size = number(config.cell_size, 128)
    return math.floor(position.x / size + 0.5), math.floor(position.y / size + 0.5)
end

local function start_cell(anchor, footprint)
    return anchor - math.floor(footprint / 2)
end

local function cell_center(grid_x, grid_y, z)
    local size = number(config.cell_size, 128)
    return Vector((grid_x + 0.5) * size, (grid_y + 0.5) * size, z or 0)
end

local function ground_height(position)
    local height = number(position.z, 0)
    pcall(function()
        local ground = GetGroundPosition(position, nil)
        if ground then height = number(ground.z, height) end
    end)
    pcall(function() height = GetGroundHeight(position, nil) end)
    return height
end

local function anchor_world(anchor_x, anchor_y)
    local size = number(config.cell_size, 128)
    local point = Vector(anchor_x * size, anchor_y * size, 0)
    point.z = ground_height(point)
    return point
end

local function within_bounds(center)
    local bounds = config.build_bounds or {}
    local half = number(config.cell_size, 128) * 0.5
    return center.x - half >= number(bounds.min_x, -999999)
        and center.x + half <= number(bounds.max_x, 999999)
        and center.y - half >= number(bounds.min_y, -999999)
        and center.y + half <= number(bounds.max_y, 999999)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function in_region(center, region)
    local half = number(config.cell_size, 128) * 0.5
    if region.shape == "circle" then
        local circle_x = number(region.x, 0)
        local circle_y = number(region.y, 0)
        local nearest_x = clamp(circle_x, center.x - half, center.x + half)
        local nearest_y = clamp(circle_y, center.y - half, center.y + half)
        local dx = nearest_x - circle_x
        local dy = nearest_y - circle_y
        local radius = number(region.radius, 0)
        return dx * dx + dy * dy <= radius * radius
    end
    return center.x + half >= number(region.min_x, 0)
        and center.x - half <= number(region.max_x, 0)
        and center.y + half >= number(region.min_y, 0)
        and center.y - half <= number(region.max_y, 0)
end

local function forbidden_marker(center)
    for _, region in ipairs(marker_regions) do
        if in_region(center, {
            shape = "circle",
            x = region.x,
            y = region.y,
            radius = region.radius,
        }) then
            return true, "forbidden_marker:" .. tostring(region.id)
        end
    end
    return false, nil
end

local function terrain_clear(center)
    local size = number(config.cell_size, 128)
    local inset = size * 0.38
    local samples = {
        center,
        center + Vector(inset, inset, 0),
        center + Vector(inset, -inset, 0),
        center + Vector(-inset, inset, 0),
        center + Vector(-inset, -inset, 0),
    }
    local lowest, highest = nil, nil
    for _, sample in ipairs(samples) do
        local traversable_ok, traversable = pcall(function()
            return GridNav:IsTraversable(sample)
        end)
        local blocked_ok, blocked = pcall(function()
            return GridNav:IsBlocked(sample)
        end)
        if not traversable_ok or traversable ~= true
            or not blocked_ok or blocked ~= false then return false, "terrain_blocked" end
        local height = ground_height(sample)
        lowest = lowest and math.min(lowest, height) or height
        highest = highest and math.max(highest, height) or height
    end
    if highest - lowest > number(config.max_height_delta, 48) then
        return false, "terrain_too_steep"
    end
    return true, nil
end

local function has_tree(center)
    local found = false
    local radius = number(config.cell_size, 128)
        * number(config.tree_block_radius_scale, 0.42)
    pcall(function() found = GridNav:IsNearbyTree(center, radius, true) end)
    return found
end

local function unit_hull_radius(unit)
    local hull = number(unit and unit.survival_hull_radius, nil)
    if hull == nil and unit and unit.GetHullRadius then
        local ok, value = pcall(unit.GetHullRadius, unit)
        if ok then hull = number(value, 0) end
    end
    return math.max(0, hull or 0)
end

local function unit_overlaps_cell(unit, center, half)
    local origin = unit:GetAbsOrigin()
    local nearest_x = clamp(origin.x, center.x - half, center.x + half)
    local nearest_y = clamp(origin.y, center.y - half, center.y + half)
    local dx = origin.x - nearest_x
    local dy = origin.y - nearest_y
    local hull = unit_hull_radius(unit)
    return dx * dx + dy * dy <= hull * hull
end

local function construction_building_is_logical_only(unit, payload)
    if unit.survival_is_building ~= true or not unit.HasModifier then return false end
    local ok, constructing = pcall(
        unit.HasModifier,
        unit,
        "modifier_building_under_construction"
    )
    if not ok or not constructing then return false end
    return not unit.GetTeamNumber
        or unit:GetTeamNumber() == number(payload.team, DOTA_TEAM_GOODGUYS)
end

local function has_unit(center, payload)
    local size = number(config.cell_size, 128)
    local half = size * 0.5
    local radius = half * math.sqrt(2)
        + number(config.max_unit_hull_radius, size * 4)
    local units = payload.nearby_units
    if not units then
        units = FindUnitsInRadius(
            number(payload.team, DOTA_TEAM_GOODGUYS),
            center,
            nil,
            radius,
            DOTA_UNIT_TARGET_TEAM_BOTH,
            DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC
                + DOTA_UNIT_TARGET_BUILDING,
            DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
            FIND_ANY_ORDER,
            false
        ) or {}
    end
    local ignored = number(payload.ignore_entindex, -1)
    local ignored_set = payload.ignore_entindexes or {}
    for _, unit in ipairs(units) do
        if unit and not unit:IsNull()
            and unit:entindex() ~= ignored
            and ignored_set[unit:entindex()] ~= true
            and not unit.survival_is_grid_preview
            and not construction_building_is_logical_only(unit, payload)
            and unit_overlaps_cell(unit, center, half) then
            return true
        end
    end
    return false
end

local function nearby_units_for_footprint(payload, footprint, world_position)
    if payload.nearby_units then return payload.nearby_units end
    local size = number(config.cell_size, 128)
    local half_width = footprint.x * size * 0.5
    local half_height = footprint.y * size * 0.5
    local radius = math.sqrt(half_width * half_width + half_height * half_height)
        + number(config.max_unit_hull_radius, size * 4)
    return FindUnitsInRadius(
        number(payload.team, DOTA_TEAM_GOODGUYS),
        world_position,
        nil,
        radius,
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC
            + DOTA_UNIT_TARGET_BUILDING,
        DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
        FIND_ANY_ORDER,
        false
    ) or {}
end

local function occupied_by_other(grid_x, grid_y, ignored)
    local occupant = occupied[grid_x] and occupied[grid_x][grid_y] or nil
    return occupant ~= nil and occupant ~= ignored
end

local function cell_corners(grid_x, grid_y)
    local size = number(config.cell_size, 128)
    local points = {
        Vector(grid_x * size, grid_y * size, 0),
        Vector((grid_x + 1) * size, grid_y * size, 0),
        Vector((grid_x + 1) * size, (grid_y + 1) * size, 0),
        Vector(grid_x * size, (grid_y + 1) * size, 0),
    }
    local result = {}
    for _, point in ipairs(points) do
        table.insert(result, {
            x = point.x,
            y = point.y,
            z = ground_height(point),
        })
    end
    return result
end

local function validate_cell(grid_x, grid_y, payload)
    local center = cell_center(grid_x, grid_y, 0)
    center.z = ground_height(center)
    local result = {
        grid_x = grid_x,
        grid_y = grid_y,
        x = center.x,
        y = center.y,
        z = center.z,
        corners = payload.compact and nil or cell_corners(grid_x, grid_y),
        ok = true,
        reason = "",
    }
    if not within_bounds(center) then
        result.ok, result.reason = false, "build_out_of_bounds"
        return result
    end
    if payload.region_policy_error then
        result.ok, result.reason = false, payload.region_policy_error
        return result
    end
    local is_forbidden, forbidden_reason = forbidden_marker(center)
    if is_forbidden then
        result.ok, result.reason = false, forbidden_reason
        return result
    end
    local terrain_ok, terrain_error = terrain_clear(center)
    if not terrain_ok then
        result.ok, result.reason = false, terrain_error
        return result
    end
    if occupied_by_other(grid_x, grid_y, number(payload.ignore_entindex, -1)) then
        result.ok, result.reason = false, "build_cell_occupied"
        return result
    end
    if has_tree(center) then
        result.ok, result.reason = false, "tree_blocked"
        return result
    end
    if has_unit(center, payload) then
        result.ok, result.reason = false, "unit_blocked"
        return result
    end
    return result
end

local function can_place(payload)
    local position = payload and payload.position
    if not position then return { ok = false, error = "invalid_position", cells = {} } end
    local footprint = normalized_footprint(payload.footprint)
    local anchor_x, anchor_y = snap_anchor(position)
    local grid_x = start_cell(anchor_x, footprint.x)
    local grid_y = start_cell(anchor_y, footprint.y)
    local world_position = anchor_world(anchor_x, anchor_y)
    local size = number(config.cell_size, 128)
    local policy_ok, policy_error = region_service.validate_building_footprint(
        grid_x * size,
        grid_y * size,
        (grid_x + footprint.x) * size,
        (grid_y + footprint.y) * size
    )
    if payload.policy_only == true then
        return {
            ok = policy_ok,
            error = policy_error,
            anchor_x = anchor_x,
            anchor_y = anchor_y,
            grid_x = grid_x,
            grid_y = grid_y,
            footprint = footprint,
            world_position = world_position,
            cells = {},
        }
    end
    local validation_payload = {}
    for key, value in pairs(payload) do validation_payload[key] = value end
    if not policy_ok then validation_payload.region_policy_error = policy_error end
    if policy_ok then
        validation_payload.nearby_units = nearby_units_for_footprint(
            payload,
            footprint,
            world_position
        )
    end
    local cells, all_valid, first_error = {}, true, nil
    for x = grid_x, grid_x + footprint.x - 1 do
        for y = grid_y, grid_y + footprint.y - 1 do
            local cell = validate_cell(x, y, validation_payload)
            table.insert(cells, cell)
            if not cell.ok then
                all_valid = false
                first_error = first_error or cell.reason
            end
        end
    end
    return {
        ok = all_valid,
        error = first_error,
        anchor_x = anchor_x,
        anchor_y = anchor_y,
        grid_x = grid_x,
        grid_y = grid_y,
        footprint = footprint,
        world_position = world_position,
        cells = cells,
    }
end

local function occupy(payload)
    local footprint = normalized_footprint(payload.footprint)
    for x = payload.grid_x, payload.grid_x + footprint.x - 1 do
        occupied[x] = occupied[x] or {}
        for y = payload.grid_y, payload.grid_y + footprint.y - 1 do
            occupied[x][y] = payload.entindex
        end
    end
    return true
end

local function release(payload)
    local footprint = normalized_footprint(payload.footprint)
    local entindex = number(payload.entindex, nil)
    for x = payload.grid_x, payload.grid_x + footprint.x - 1 do
        if occupied[x] then
            for y = payload.grid_y, payload.grid_y + footprint.y - 1 do
                if entindex == nil or occupied[x][y] == entindex then
                    occupied[x][y] = nil
                end
            end
        end
    end
    return true
end

local function load_marker_regions()
    marker_regions = {}
    for _, row in ipairs(config.forbidden_markers or {}) do
        local marker = nil
        pcall(function() marker = Entities:FindByName(nil, row.marker_name) end)
        if marker and not marker:IsNull() then
            local origin = marker:GetAbsOrigin()
            table.insert(marker_regions, {
                id = row.id or row.marker_name,
                x = origin.x,
                y = origin.y,
                radius = number(row.radius, 128),
            })
        else
            print("[GridPlacement] optional marker missing: " .. tostring(row.marker_name))
        end
    end
end

function M.init()
    occupied = {}
    load_marker_regions()
    event_bus.handle_request(events.GRID_CAN_PLACE_REQUEST, can_place)
    event_bus.handle_request(events.GRID_OCCUPY_REQUEST, occupy)
    event_bus.handle_request(events.GRID_RELEASE_REQUEST, release)
    print("[GridPlacement] server grid validation initialized")
end

M._unit_overlaps_cell_for_test = unit_overlaps_cell
M._has_unit_for_test = has_unit
M._nearby_units_for_footprint_for_test = nearby_units_for_footprint
M._occupied_for_test = function() return occupied end
M._can_place_for_test = can_place

return M
