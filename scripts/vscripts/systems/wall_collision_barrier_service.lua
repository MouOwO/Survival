local M = {}
local barriers_by_wall = {}
local COLUMN_COUNT = 3
local SEGMENT_COUNT = 10
local COLUMN_SPACING = 38
local SEGMENT_SPACING = 10
local HULL_RADIUS = 8
local NORMAL_OFFSET = 188
local SHARED_OFFSET_X = 0
local SHARED_OFFSET_Y = 0
local SIDE_OFFSETS = {
    up = { 0, 0 },
    down = { 100, 100 },
    left = { 100, -100 },
    right = { 0, 0 },
}

local function valid(entity)
    return entity ~= nil and (not entity.IsNull or not entity:IsNull())
end

local function normalized(vector, fallback)
    local length = math.sqrt(vector.x * vector.x + vector.y * vector.y)
    if length <= 0.001 then return fallback end
    return Vector(vector.x / length, vector.y / length, 0)
end

local function axes(wall)
    local forward = wall.GetForwardVector and wall:GetForwardVector() or Vector(1, 0, 0)
    forward = normalized(forward, Vector(1, 0, 0))
    return Vector(-forward.y, forward.x, 0), forward
end

local function remove_list(list)
    for _, barrier in ipairs(list or {}) do
        if valid(barrier) then UTIL_Remove(barrier) end
    end
end

function M.clear(wall)
    local index = type(wall) == "number"
        and tonumber(wall)
        or (valid(wall) and wall:entindex() or nil)
    if not index then return end
    remove_list(barriers_by_wall[index])
    barriers_by_wall[index] = nil
end

function M.create(wall)
    if not valid(wall) then return {}, "wall_invalid" end
    local index = wall:entindex()
    M.clear(index)
    local lateral, forward = axes(wall)
    local origin = wall:GetAbsOrigin()
    local column_count = COLUMN_COUNT
    local segment_count = SEGMENT_COUNT
    local column_spacing = COLUMN_SPACING
    local segment_spacing = SEGMENT_SPACING
    local radius = HULL_RADIUS
    local base_normal_offset = NORMAL_OFFSET
    local shared_x = SHARED_OFFSET_X
    local shared_y = SHARED_OFFSET_Y
    local result = {}
    local sides = {
        { id = "up", normal = forward, tangent = lateral },
        { id = "down", normal = forward * -1, tangent = lateral * -1 },
        { id = "right", normal = lateral, tangent = forward * -1 },
        { id = "left", normal = lateral * -1, tangent = forward },
    }
    for _, side in ipairs(sides) do
        local side_offset = SIDE_OFFSETS[side.id]
        local side_x, side_y = side_offset[1], side_offset[2]
        for column = 1, column_count do
            local tangent_offset =
                (column - (column_count + 1) / 2) * column_spacing
                + shared_x + side_x
            for segment = 1, segment_count do
                local normal_offset = base_normal_offset
                    + shared_y + side_y
                    + (segment - (segment_count + 1) / 2) * segment_spacing
                local position = origin
                    + side.tangent * tangent_offset
                    + side.normal * normal_offset
                position.z = GetGroundHeight(position, wall)
                local barrier = CreateUnitByName(
                    "npc_survival_wall_collision_barrier",
                    position,
                    true,
                    wall,
                    wall,
                    wall:GetTeamNumber()
                )
                if not valid(barrier) then
                    M.clear(index)
                    return {}, "barrier_create_failed"
                end
                barrier:SetHullRadius(radius)
                barrier:SetAbsOrigin(position)
                barrier.survival_wall_collision_barrier = true
                barrier.survival_wall_entindex = index
                barrier.survival_wall_collision_side = side.id
                barrier.survival_wall_collision_column = column
                barrier.survival_wall_collision_segment = segment
                barrier:AddNoDraw()
                barrier:AddNewModifier(
                    barrier,
                    nil,
                    "modifier_wall_collision_barrier",
                    {}
                )
                result[#result + 1] = barrier
            end
        end
    end
    barriers_by_wall[index] = result
    return result
end

function M.count(wall)
    local index = type(wall) == "number"
        and tonumber(wall)
        or (valid(wall) and wall:entindex() or nil)
    return #(barriers_by_wall[index] or {})
end

M._barriers_by_wall_for_test = barriers_by_wall
return M