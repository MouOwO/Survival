local M = {}

local function valid(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

function M.is_flying(unit)
    if not valid(unit) then return false end
    if unit.HasFlyMovementCapability then
        local ok, result = pcall(function()
            return unit:HasFlyMovementCapability()
        end)
        if ok and result then return true end
    end
    if unit.GetMoveCapability then
        local ok, capability = pcall(function()
            return unit:GetMoveCapability()
        end)
        return ok and capability == DOTA_UNIT_CAP_MOVE_FLY
    end
    return false
end

function M.enemies_in_circle(caster, position, radius)
    if not valid(caster) or not position then return {} end
    return FindUnitsInRadius(
        caster:GetTeamNumber(), position, nil, math.max(1, radius or 1),
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,
        FIND_ANY_ORDER, false
    ) or {}
end

local function distance_to_segment(point, start_pos, end_pos)
    local dx = end_pos.x - start_pos.x
    local dy = end_pos.y - start_pos.y
    local length_squared = dx * dx + dy * dy
    if length_squared <= 0.001 then
        local px = point.x - start_pos.x
        local py = point.y - start_pos.y
        return math.sqrt(px * px + py * py), 0
    end
    local projection = ((point.x - start_pos.x) * dx
        + (point.y - start_pos.y) * dy) / length_squared
    local clamped = math.max(0, math.min(1, projection))
    local nearest_x = start_pos.x + dx * clamped
    local nearest_y = start_pos.y + dy * clamped
    local px = point.x - nearest_x
    local py = point.y - nearest_y
    return math.sqrt(px * px + py * py), projection
end

function M.enemies_in_path(caster, start_pos, end_pos, half_width, excluded)
    if not valid(caster) or not start_pos or not end_pos then return {} end
    local center = (start_pos + end_pos) * 0.5
    local length = (end_pos - start_pos):Length2D()
    local search_radius = length * 0.5 + math.max(1, half_width or 1) + 96
    local candidates = M.enemies_in_circle(caster, center, search_radius)
    local result = {}
    local excluded_index = excluded and excluded:entindex() or -1
    for _, unit in ipairs(candidates) do
        if valid(unit) and unit:entindex() ~= excluded_index then
            local distance, projection = distance_to_segment(
                unit:GetAbsOrigin(), start_pos, end_pos
            )
            local hull = unit.GetHullRadius and unit:GetHullRadius() or 0
            if projection >= 0 and projection <= 1
                and distance <= math.max(1, half_width or 1) + hull then
                result[#result + 1] = unit
            end
        end
    end
    return result
end

return M
