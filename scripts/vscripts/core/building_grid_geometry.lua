local config = require("config/grid_placement_config")
local M = {}

function M.footprint(source)
    source = source or {}
    local minimum = config.minimum_footprint or { x = 2, y = 2 }
    local subdivision = math.max(1, math.floor(tonumber(config.footprint_subdivision) or 1))
    local function axis(key)
        local low = tonumber(minimum[key]) or 2
        return math.floor(math.max(tonumber(source[key]) or low, low)) * subdivision
    end
    return { x = axis("x"), y = axis("y") }
end

-- Even footprints are centered on grid intersections; odd footprints on
-- cell centers. Re-snapping an already snapped point must not move it.
function M.snap_axis(value, cells)
    local size = tonumber(config.cell_size) or 64
    local offset = (cells % 2) * 0.5
    local anchor = math.floor(value / size + 0.5 - offset)
    return anchor, (anchor + offset) * size, anchor - math.floor(cells / 2)
end

function M.origin(position, source)
    local footprint = M.footprint(source)
    local _, _, x = M.snap_axis(position.x, footprint.x)
    local _, _, y = M.snap_axis(position.y, footprint.y)
    return x, y
end

return M
