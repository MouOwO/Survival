-- Shared admission rules. Ongoing repair is allowed to finish to full health.
local M = {}
M.think_interval = 0.1
M.idle_interval = 1
M.start_health_ratio = 0.99

function M.needs_repair(building)
    local maximum, health = building:GetMaxHealth(), building:GetHealth()
    return maximum > 0 and health < maximum
        and health < maximum * M.start_health_ratio
end

function M.wall_at_order_position(keys)
    if tonumber(keys.order_type) ~= tonumber(DOTA_UNIT_ORDER_MOVE_TO_POSITION) then return nil end
    local x, y = tonumber(keys.position_x), tonumber(keys.position_y)
    if not x or not y or x ~= x or y ~= y or math.abs(x) == math.huge
        or math.abs(y) == math.huge then return nil end
    local grid = package.loaded["systems/grid_placement_system"]
    if not grid or not grid.occupant_at_position then return nil end
    -- Use the authoritative occupied cell, not a world-wide unit search or
    -- model tags. The order service still validates life, team and owner.
    local index = grid.occupant_at_position({ x = x, y = y })
    if not index or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, building = pcall(EntIndexToHScript, index)
    if ok and building and not building:IsNull()
        and building.survival_building_id == "wall" then return building end
    return nil
end

return M
