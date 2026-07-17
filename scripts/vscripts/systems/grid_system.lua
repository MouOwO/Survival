local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/grid_config")

local M = {}
local occupied = {}

local function world_to_grid(position)
    return math.floor(position.x / config.cell_size), math.floor(position.y / config.cell_size)
end

local function grid_to_world(grid_x, grid_y)
    return Vector(
        (grid_x + 0.5) * config.cell_size,
        (grid_y + 0.5) * config.cell_size,
        config.build_z
    )
end

local function within_bounds(position)
    local bounds = config.build_bounds
    return position.x >= bounds.min_x and position.x <= bounds.max_x
       and position.y >= bounds.min_y and position.y <= bounds.max_y
end

local function cell_is_occupied(x, y)
    return occupied[x] and occupied[x][y] ~= nil
end

local function can_place(payload)
    local position = payload.position
    local footprint = payload.footprint or { x = 1, y = 1 }
    if not position or not within_bounds(position) then
        return { ok = false, error = "build_out_of_bounds" }
    end

    local grid_x, grid_y = world_to_grid(position)
    for x = grid_x, grid_x + footprint.x - 1 do
        for y = grid_y, grid_y + footprint.y - 1 do
            if cell_is_occupied(x, y) then
                return { ok = false, error = "build_cell_occupied" }
            end
        end
    end

    return {
        ok = true,
        grid_x = grid_x,
        grid_y = grid_y,
        world_position = grid_to_world(grid_x, grid_y),
    }
end

local function occupy(payload)
    for x = payload.grid_x, payload.grid_x + payload.footprint.x - 1 do
        occupied[x] = occupied[x] or {}
        for y = payload.grid_y, payload.grid_y + payload.footprint.y - 1 do
            occupied[x][y] = payload.entindex
        end
    end
    return true
end

local function release(payload)
    for x = payload.grid_x, payload.grid_x + payload.footprint.x - 1 do
        if occupied[x] then
            for y = payload.grid_y, payload.grid_y + payload.footprint.y - 1 do
                occupied[x][y] = nil
            end
        end
    end
    return true
end

function M.init()
    occupied = {}
    event_bus.handle_request(events.GRID_CAN_PLACE_REQUEST, can_place)
    event_bus.handle_request(events.GRID_OCCUPY_REQUEST, occupy)
    event_bus.handle_request(events.GRID_RELEASE_REQUEST, release)
end

return M
