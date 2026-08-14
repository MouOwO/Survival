local M = {}

function M.clamp(origin, target, maximum_distance)
    local delta = target - origin
    delta.z = 0
    local distance = delta:Length2D()
    local maximum = math.max(0, tonumber(maximum_distance) or 0)
    if distance <= maximum or distance < 1 then
        return Vector(target.x, target.y, target.z), distance
    end
    local result = origin + delta:Normalized() * maximum
    result.z = target.z
    return result, maximum
end

return M