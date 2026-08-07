local M = {}

local function valid_entity(unit)
    return unit ~= nil and (not unit.IsNull or not unit:IsNull())
end

local function valid_multiplier(value)
    local multiplier = tonumber(value)
    if not multiplier or multiplier ~= multiplier
        or multiplier == math.huge or multiplier == -math.huge
        or multiplier <= 0 then
        return nil
    end
    return multiplier
end

function M.apply(unit, value, configured_base_radius)
    local multiplier = valid_multiplier(value)
    if not multiplier then return false, "monster_scale_must_be_positive" end
    if not valid_entity(unit) or type(unit.GetHullRadius) ~= "function"
        or type(unit.SetHullRadius) ~= "function" then
        return false, "monster_hull_unavailable"
    end

    local base_radius = tonumber(unit.survival_base_monster_hull_radius)
    if not base_radius then
        base_radius = tonumber(configured_base_radius)
        if base_radius == nil then
            local ok, radius = pcall(unit.GetHullRadius, unit)
            if not ok then return false, "monster_base_hull_read_failed" end
            base_radius = tonumber(radius)
        end
        if not base_radius or base_radius < 0 then
            return false, "monster_base_hull_missing"
        end
        unit.survival_base_monster_hull_radius = base_radius
    end

    local radius = base_radius * multiplier
    local ok, error_message = pcall(unit.SetHullRadius, unit, radius)
    if not ok then
        return false, "monster_hull_apply_failed:" .. tostring(error_message)
    end
    unit.survival_monster_hull_multiplier = multiplier
    unit.survival_monster_hull_radius = radius
    return true, radius, base_radius
end

function M.apply_all(enemies, value)
    local multiplier = valid_multiplier(value)
    if not multiplier then
        return false, "monster_scale_must_be_positive"
    end
    local result = {
        multiplier = multiplier,
        applied = 0,
        failed = 0,
        base_min = nil,
        base_max = nil,
        radius_min = nil,
        radius_max = nil,
    }
    for _, meta in pairs(enemies or {}) do
        local unit = meta and meta.unit
        local ok, radius, base_radius = M.apply(unit, multiplier,
            meta and meta.base_hull_radius)
        if ok then
            result.applied = result.applied + 1
            result.base_min = math.min(result.base_min or base_radius, base_radius)
            result.base_max = math.max(result.base_max or base_radius, base_radius)
            result.radius_min = math.min(result.radius_min or radius, radius)
            result.radius_max = math.max(result.radius_max or radius, radius)
        else
            result.failed = result.failed + 1
        end
    end
    return true, result
end

return M