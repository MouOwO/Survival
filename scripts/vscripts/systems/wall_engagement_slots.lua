local global_rules = require("config/global_rules")

local M = {}
local states = {}

local function valid(entity)
    return entity ~= nil and (not entity.IsNull or not entity:IsNull())
end

local function alive(entity)
    return valid(entity) and (not entity.IsAlive or entity:IsAlive())
end

local function entindex(entity)
    return valid(entity) and tonumber(entity:entindex()) or nil
end

local function resolve(index)
    if not index or type(EntIndexToHScript) ~= "function" then return nil end
    local ok, entity = pcall(EntIndexToHScript, index)
    return ok and entity or nil
end

local function normalized_2d(vector, fallback)
    local length = math.sqrt(vector.x * vector.x + vector.y * vector.y)
    if length <= 0.001 then return fallback end
    return Vector(vector.x / length, vector.y / length, 0)
end

local function wall_axes(wall)
    local forward = wall.GetForwardVector and wall:GetForwardVector() or Vector(1, 0, 0)
    forward = normalized_2d(forward, Vector(1, 0, 0))
    return Vector(-forward.y, forward.x, 0), forward
end

local function engagement_axes(wall, unit)
    local right, forward = wall_axes(wall)
    local delta = unit:GetAbsOrigin() - wall:GetAbsOrigin()
    local right_dot = delta.x * right.x + delta.y * right.y
    local forward_dot = delta.x * forward.x + delta.y * forward.y
    if math.abs(right_dot) > math.abs(forward_dot) then
        local side = right_dot < 0 and -1 or 1
        return forward, right * side
    end
    local side = forward_dot < 0 and -1 or 1
    return right, forward * side
end

local function state_for(wall, unit)
    local wall_index = assert(entindex(wall), "wall entindex missing")
    local state = states[wall_index]
    if not state then
        local lateral, normal = engagement_axes(wall, unit)
        state = {
            lateral = lateral,
            normal = normal,
            slots = {},
            waiters = {},
            next_waiter_order = 0,
        }
        states[wall_index] = state
    end
    return state
end

local function clean(state)
    for slot, occupant_index in pairs(state.slots) do
        if not alive(resolve(occupant_index)) then state.slots[slot] = nil end
    end
    for unit_index in pairs(state.waiters) do
        if not alive(resolve(unit_index)) then state.waiters[unit_index] = nil end
    end
end

local function slot_offset(slot, count, spacing)
    return (slot - (count + 1) / 2) * spacing
end

function M.claim(wall, unit)
    if not alive(wall) or not alive(unit) then return nil end
    local state = state_for(wall, unit)
    clean(state)
    local unit_index = entindex(unit)
    local count = math.max(1, math.floor(global_rules.wall_engagement_slot_count))
    for slot = 1, count do
        if state.slots[slot] == unit_index then return slot end
    end

    local wall_position = wall:GetAbsOrigin()
    local unit_position = unit:GetAbsOrigin()
    local lateral = state.lateral
    local best_slot, best_distance = nil, nil
    for slot = 1, count do
        if state.slots[slot] == nil then
            local offset = slot_offset(slot, count, global_rules.wall_engagement_slot_spacing)
            local point = wall_position + lateral * offset
            local delta = unit_position - point
            local distance = delta.x * delta.x + delta.y * delta.y
            if best_distance == nil or distance < best_distance then
                best_slot, best_distance = slot, distance
            end
        end
    end
    if best_slot then
        state.slots[best_slot] = unit_index
        state.waiters[unit_index] = nil
    elseif state.waiters[unit_index] == nil then
        state.next_waiter_order = state.next_waiter_order + 1
        state.waiters[unit_index] = state.next_waiter_order
    end
    return best_slot
end

function M.release(wall_index, unit_index)
    local state = states[tonumber(wall_index)]
    if not state then return end
    for slot, occupant_index in pairs(state.slots) do
        if occupant_index == tonumber(unit_index) then state.slots[slot] = nil end
    end
    state.waiters[tonumber(unit_index)] = nil
    if not alive(resolve(tonumber(wall_index))) then states[tonumber(wall_index)] = nil end
end

function M.position(wall, slot, queue_index)
    if not valid(wall) then return nil end
    local state = states[entindex(wall)]
    if not state then return nil end
    local count = math.max(1, math.floor(global_rules.wall_engagement_slot_count))
    slot = math.max(1, math.min(count, tonumber(slot) or 1))
    local lateral, normal = state.lateral, state.normal
    local lateral_offset = slot_offset(
        slot,
        count,
        global_rules.wall_engagement_slot_spacing
    )
    local normal_offset = global_rules.wall_engagement_normal_offset
        + math.max(0, tonumber(queue_index) or 0)
            * global_rules.wall_engagement_queue_spacing
    return wall:GetAbsOrigin()
        + lateral * lateral_offset
        + normal * normal_offset
end

function M.queue_position(wall, unit)
    if not alive(wall) or not alive(unit) then return nil end
    local state = state_for(wall, unit)
    clean(state)
    local count = math.max(1, math.floor(global_rules.wall_engagement_slot_count))
    local unit_index = entindex(unit)
    if not unit_index then return nil end
    if state.waiters[unit_index] == nil then
        state.next_waiter_order = state.next_waiter_order + 1
        state.waiters[unit_index] = state.next_waiter_order
    end
    local ordered = {}
    for waiter_index, order in pairs(state.waiters) do
        ordered[#ordered + 1] = { unit_index = waiter_index, order = order }
    end
    table.sort(ordered, function(a, b)
        if a.order == b.order then return a.unit_index < b.unit_index end
        return a.order < b.order
    end)
    for queue_index, waiter in ipairs(ordered) do
        if waiter.unit_index == unit_index then
            local slot = (queue_index - 1) % count + 1
            local row = math.floor((queue_index - 1) / count) + 1
            return M.position(wall, slot, row), slot, row
        end
    end
    return nil
end

function M.reset()
    states = {}
end

return M