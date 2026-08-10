local definitions = require("config/generated/build_forbidden_regions")

local M = {}
local EPSILON = 0.000001
local hero_movable_regions = {}
local building_forbidden_regions = {}

local function number(value)
    local result = tonumber(value)
    if result == nil then error("missing numeric region coordinate") end
    return result
end

local function point(x, y)
    return { x = x, y = y }
end

local function cross(a, b, c)
    return (b.x - a.x) * (c.y - a.y)
        - (b.y - a.y) * (c.x - a.x)
end

local function point_in_polygon(x, y, points)
    local direction = 0
    local target = point(x, y)
    for index = 1, #points do
        local value = cross(points[index], points[index % #points + 1], target)
        if math.abs(value) > EPSILON then
            local sign = value > 0 and 1 or -1
            if direction ~= 0 and sign ~= direction then return false end
            direction = sign
        end
    end
    return true
end

local function orientation(a, b, c)
    local value = cross(a, b, c)
    if math.abs(value) <= EPSILON then return 0 end
    return value > 0 and 1 or -1
end

local function on_segment(a, b, target)
    return target.x >= math.min(a.x, b.x) - EPSILON
        and target.x <= math.max(a.x, b.x) + EPSILON
        and target.y >= math.min(a.y, b.y) - EPSILON
        and target.y <= math.max(a.y, b.y) + EPSILON
end

local function segments_intersect(a, b, c, d)
    local ab_c, ab_d = orientation(a, b, c), orientation(a, b, d)
    local cd_a, cd_b = orientation(c, d, a), orientation(c, d, b)
    if ab_c ~= ab_d and cd_a ~= cd_b then return true end
    return (ab_c == 0 and on_segment(a, b, c))
        or (ab_d == 0 and on_segment(a, b, d))
        or (cd_a == 0 and on_segment(c, d, a))
        or (cd_b == 0 and on_segment(c, d, b))
end

local function compile(row)
    if row.enabled ~= true then return nil end
    local region = {
        id = tostring(row.region_id or "unnamed"),
        region_type = tostring(row.region_type or ""),
        shape = tostring(row.shape or ""),
    }
    if region.region_type ~= "hero_movable"
        and region.region_type ~= "building_forbidden" then
        error("unsupported region type: " .. region.region_type)
    end
    if region.shape == "circle" then
        region.x = number(row.center_x)
        region.y = number(row.center_y)
        region.radius = number(row.radius)
        if region.radius <= 0 then error("circle radius must be positive") end
        return region
    end
    if region.shape ~= "quadrilateral" then
        error("unsupported region shape: " .. region.shape)
    end
    region.points = {}
    for index = 1, 4 do
        region.points[index] = point(
            number(row["p" .. index .. "_x"]),
            number(row["p" .. index .. "_y"])
        )
    end
    local direction = 0
    for index = 1, 4 do
        local value = cross(
            region.points[index],
            region.points[index % 4 + 1],
            region.points[(index + 1) % 4 + 1]
        )
        if math.abs(value) <= EPSILON then
            error("quadrilateral points must be non-degenerate")
        end
        local sign = value > 0 and 1 or -1
        if direction ~= 0 and sign ~= direction then
            error("quadrilateral points must form a convex boundary")
        end
        direction = sign
    end
    return region
end

local function point_in_region(x, y, region)
    if region.shape == "circle" then
        local dx, dy = x - region.x, y - region.y
        return dx * dx + dy * dy <= region.radius * region.radius + EPSILON
    end
    return point_in_polygon(x, y, region.points)
end

local function intersects_aabb(region, min_x, min_y, max_x, max_y)
    if region.shape == "circle" then
        local x = math.max(min_x, math.min(max_x, region.x))
        local y = math.max(min_y, math.min(max_y, region.y))
        local dx, dy = x - region.x, y - region.y
        return dx * dx + dy * dy <= region.radius * region.radius + EPSILON
    end
    local corners = {
        point(min_x, min_y), point(max_x, min_y),
        point(max_x, max_y), point(min_x, max_y),
    }
    for _, item in ipairs(region.points) do
        if item.x >= min_x and item.x <= max_x
            and item.y >= min_y and item.y <= max_y then return true end
    end
    for _, item in ipairs(corners) do
        if point_in_region(item.x, item.y, region) then return true end
    end
    for index = 1, 4 do
        local a, b = region.points[index], region.points[index % 4 + 1]
        for edge = 1, 4 do
            if segments_intersect(a, b, corners[edge], corners[edge % 4 + 1]) then
                return true
            end
        end
    end
    return false
end

local function contains_aabb(region, min_x, min_y, max_x, max_y)
    return point_in_region(min_x, min_y, region)
        and point_in_region(max_x, min_y, region)
        and point_in_region(max_x, max_y, region)
        and point_in_region(min_x, max_y, region)
end

local function vertical_interval(region, x, min_y, max_y)
    if region.shape == "circle" then
        local dx = x - region.x
        local squared = region.radius * region.radius - dx * dx
        if squared < -EPSILON then return nil end
        local height = math.sqrt(math.max(0, squared))
        local bottom = math.max(min_y, region.y - height)
        local top = math.min(max_y, region.y + height)
        if bottom <= top + EPSILON then return bottom, top end
        return nil
    end
    local values = {}
    for index = 1, #region.points do
        local a = region.points[index]
        local b = region.points[index % #region.points + 1]
        if math.abs(a.x - b.x) <= EPSILON then
            if math.abs(x - a.x) <= EPSILON then
                values[#values + 1] = a.y
                values[#values + 1] = b.y
            end
        elseif x >= math.min(a.x, b.x) - EPSILON
            and x <= math.max(a.x, b.x) + EPSILON then
            local ratio = (x - a.x) / (b.x - a.x)
            values[#values + 1] = a.y + (b.y - a.y) * ratio
        end
    end
    if #values == 0 then return nil end
    local bottom, top = values[1], values[1]
    for index = 2, #values do
        bottom = math.min(bottom, values[index])
        top = math.max(top, values[index])
    end
    bottom, top = math.max(min_y, bottom), math.min(max_y, top)
    if bottom <= top + EPSILON then return bottom, top end
    return nil
end

local function add_x(values, x, min_x, max_x)
    if x and x >= min_x - EPSILON and x <= max_x + EPSILON then
        values[#values + 1] = math.max(min_x, math.min(max_x, x))
    end
end

local function line_circle_x_values(values, a, b, circle, min_x, max_x)
    local dx, dy = b.x - a.x, b.y - a.y
    local fx, fy = a.x - circle.x, a.y - circle.y
    local quadratic = dx * dx + dy * dy
    if quadratic <= EPSILON then return end
    local linear = 2 * (fx * dx + fy * dy)
    local constant = fx * fx + fy * fy - circle.radius * circle.radius
    local discriminant = linear * linear - 4 * quadratic * constant
    if discriminant < -EPSILON then return end
    local root = math.sqrt(math.max(0, discriminant))
    for _, ratio in ipairs({
        (-linear - root) / (2 * quadratic),
        (-linear + root) / (2 * quadratic),
    }) do
        if ratio >= -EPSILON and ratio <= 1 + EPSILON then
            add_x(values, a.x + dx * ratio, min_x, max_x)
        end
    end
end

local function circle_circle_x_values(values, left, right, min_x, max_x)
    local dx, dy = right.x - left.x, right.y - left.y
    local distance_sq = dx * dx + dy * dy
    if distance_sq <= EPSILON then return end
    local distance = math.sqrt(distance_sq)
    if distance > left.radius + right.radius + EPSILON
        or distance < math.abs(left.radius - right.radius) - EPSILON then return end
    local along = (left.radius * left.radius - right.radius * right.radius
        + distance_sq) / (2 * distance)
    local height_sq = left.radius * left.radius - along * along
    if height_sq < -EPSILON then return end
    local base_x = left.x + along * dx / distance
    local offset_x = math.sqrt(math.max(0, height_sq)) * -dy / distance
    add_x(values, base_x - offset_x, min_x, max_x)
    add_x(values, base_x + offset_x, min_x, max_x)
end

local function region_edges(region)
    if region.shape == "circle" then return {} end
    local result = {}
    for index = 1, #region.points do
        result[#result + 1] = {
            a = region.points[index],
            b = region.points[index % #region.points + 1],
        }
    end
    return result
end

local function horizontal_intersections(values, region, y, min_x, max_x)
    if region.shape == "circle" then
        local dy = y - region.y
        local squared = region.radius * region.radius - dy * dy
        if squared >= -EPSILON then
            local width = math.sqrt(math.max(0, squared))
            add_x(values, region.x - width, min_x, max_x)
            add_x(values, region.x + width, min_x, max_x)
        end
        return
    end
    for _, edge in ipairs(region_edges(region)) do
        local a, b = edge.a, edge.b
        if math.abs(a.y - b.y) <= EPSILON then
            if math.abs(y - a.y) <= EPSILON then
                add_x(values, a.x, min_x, max_x)
                add_x(values, b.x, min_x, max_x)
            end
        elseif y >= math.min(a.y, b.y) - EPSILON
            and y <= math.max(a.y, b.y) + EPSILON then
            add_x(values, a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y),
                min_x, max_x)
        end
    end
end

local function coverage_x_values(min_x, min_y, max_x, max_y, movable_regions)
    local values = { min_x, max_x }
    for _, region in ipairs(movable_regions) do
        if region.shape == "circle" then
            add_x(values, region.x - region.radius, min_x, max_x)
            add_x(values, region.x + region.radius, min_x, max_x)
        else
            for _, item in ipairs(region.points) do
                add_x(values, item.x, min_x, max_x)
            end
        end
        horizontal_intersections(values, region, min_y, min_x, max_x)
        horizontal_intersections(values, region, max_y, min_x, max_x)
    end
    for left_index = 1, #movable_regions do
        local left = movable_regions[left_index]
        for right_index = left_index + 1, #movable_regions do
            local right = movable_regions[right_index]
            if left.shape == "circle" and right.shape == "circle" then
                circle_circle_x_values(values, left, right, min_x, max_x)
            elseif left.shape == "circle" then
                for _, edge in ipairs(region_edges(right)) do
                    line_circle_x_values(values, edge.a, edge.b, left, min_x, max_x)
                end
            elseif right.shape == "circle" then
                for _, edge in ipairs(region_edges(left)) do
                    line_circle_x_values(values, edge.a, edge.b, right, min_x, max_x)
                end
            else
                for _, left_edge in ipairs(region_edges(left)) do
                    for _, right_edge in ipairs(region_edges(right)) do
                        if segments_intersect(
                            left_edge.a, left_edge.b, right_edge.a, right_edge.b
                        ) then
                            local x1, y1 = left_edge.a.x, left_edge.a.y
                            local x2, y2 = left_edge.b.x, left_edge.b.y
                            local x3, y3 = right_edge.a.x, right_edge.a.y
                            local x4, y4 = right_edge.b.x, right_edge.b.y
                            local denominator = (x1 - x2) * (y3 - y4)
                                - (y1 - y2) * (x3 - x4)
                            if math.abs(denominator) > EPSILON then
                                add_x(values, ((x1 * y2 - y1 * x2) * (x3 - x4)
                                    - (x1 - x2) * (x3 * y4 - y3 * x4))
                                    / denominator, min_x, max_x)
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(values)
    local unique = {}
    for _, value in ipairs(values) do
        if #unique == 0 or math.abs(value - unique[#unique]) > EPSILON then
            unique[#unique + 1] = value
        end
    end
    local samples = {}
    for index, value in ipairs(unique) do
        samples[#samples + 1] = value
        if index < #unique then samples[#samples + 1] = (value + unique[index + 1]) * 0.5 end
    end
    return samples
end

local function vertical_line_covered(x, min_y, max_y, movable_regions)
    local intervals = {}
    for _, region in ipairs(movable_regions) do
        local bottom, top = vertical_interval(region, x, min_y, max_y)
        if bottom then intervals[#intervals + 1] = { bottom = bottom, top = top } end
    end
    table.sort(intervals, function(left, right) return left.bottom < right.bottom end)
    local covered_to = min_y
    for _, interval in ipairs(intervals) do
        if interval.bottom > covered_to + EPSILON then return false end
        covered_to = math.max(covered_to, interval.top)
        if covered_to >= max_y - EPSILON then return true end
    end
    return covered_to >= max_y - EPSILON
end

local function compile_regions()
    hero_movable_regions = {}
    building_forbidden_regions = {}
    for _, row in ipairs(definitions.rows or {}) do
        local region = compile(row)
        if region then
            if region.region_type == "hero_movable" then
                table.insert(hero_movable_regions, region)
            else
                table.insert(building_forbidden_regions, region)
            end
        end
    end
end

local function any_region_contains(x, y, regions)
    for _, region in ipairs(regions) do
        if point_in_region(x, y, region) then return true, region.id end
    end
    return false, nil
end

function M.contains(position)
    if not position then return false, nil end
    return any_region_contains(position.x, position.y, hero_movable_regions)
end

function M.validate_hero_position(position)
    if not position then return false, "invalid_destination" end
    -- An empty movable list means the map has not opted into the new policy.
    -- Preserve the legacy playable map until Hammer supplies authoritative data.
    if #hero_movable_regions == 0 then return true, nil end
    local inside = M.contains(position)
    if not inside then return false, "hero_destination_outside_movable_region" end
    return true, nil
end

function M.intersects_aabb(min_x, min_y, max_x, max_y)
    for _, region in ipairs(building_forbidden_regions) do
        if intersects_aabb(region, min_x, min_y, max_x, max_y) then
            return true, region.id
        end
    end
    return false, nil
end

local function validate_building_footprint_for_regions(
    min_x, min_y, max_x, max_y, movable_regions, forbidden_regions
)
    -- No movable regions means the whitelist is disabled, so the existing Grid
    -- bounds/terrain/occupancy checks remain authoritative during migration.
    if #movable_regions > 0 then
        for _, x in ipairs(coverage_x_values(
            min_x, min_y, max_x, max_y, movable_regions
        )) do
            if not vertical_line_covered(x, min_y, max_y, movable_regions) then
                return false, "hero_movable_coverage_missing"
            end
        end
    end
    for _, region in ipairs(forbidden_regions) do
        if intersects_aabb(region, min_x, min_y, max_x, max_y) then
            return false, "building_forbidden_region:" .. tostring(region.id)
        end
    end
    return true, nil
end

function M.validate_building_footprint(min_x, min_y, max_x, max_y)
    return validate_building_footprint_for_regions(
        min_x, min_y, max_x, max_y,
        hero_movable_regions, building_forbidden_regions
    )
end

function M.counts()
    return #hero_movable_regions, #building_forbidden_regions
end

function M.is_movable_policy_enabled()
    return #hero_movable_regions > 0
end

function M.init()
    compile_regions()
    local movable, forbidden = M.counts()
    print(string.format(
        "[SURVIVAL_REGIONS] hero_movable=%d building_forbidden=%d movable_policy_enabled=%s",
        movable, forbidden, tostring(movable > 0)
    ))
end

compile_regions()

M._test = {
    point_in_region = point_in_region,
    intersects_aabb = intersects_aabb,
    contains_aabb = contains_aabb,
    validate_building_footprint_for_regions =
        validate_building_footprint_for_regions,
    validate_building_footprint = M.validate_building_footprint,
    validate_hero_position = M.validate_hero_position,
}

return M