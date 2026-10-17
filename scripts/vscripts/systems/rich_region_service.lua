-- The Hammer navigation mask is authoritative. Discover only the four local
-- islands once while loading; normal orders and placement use cached cells.
local M = {}
local CELL, SEARCH_RADIUS, MAX_REGION_CELLS = 64, 6144, 8192
local GUARD_TASK = "rich_builder_region_guard"
local DIRECTIONS = {
    { id = "east", x = 1, y = 0 }, { id = "south", x = 0, y = -1 },
    { id = "west", x = -1, y = 0 }, { id = "north", x = 0, y = 1 },
}
local NEIGHBORS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local POINT_ORDERS = { "DOTA_UNIT_ORDER_MOVE_TO_POSITION", "DOTA_UNIT_ORDER_ATTACK_MOVE",
    "DOTA_UNIT_ORDER_CAST_POSITION", "DOTA_UNIT_ORDER_PATROL", "DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION" }
local TARGET_ORDERS = { "DOTA_UNIT_ORDER_MOVE_TO_TARGET", "DOTA_UNIT_ORDER_ATTACK_TARGET",
    "DOTA_UNIT_ORDER_CAST_TARGET", "DOTA_UNIT_ORDER_CAST_TARGET_TREE", "DOTA_UNIT_ORDER_PICKUP_ITEM",
    "DOTA_UNIT_ORDER_PICKUP_RUNE" }
local regions, labels, assignments, builders = nil, {}, {}, {}
local origin, initialization_error, guard_active = nil, nil, false

local function rich()
    local setup = package.loaded["systems/match_setup_service"]
    return setup and type(setup.get_mode) == "function" and setup.get_mode() == "rich"
end

local function number(value)
    value = tonumber(value)
    return value and value == value and value > -math.huge and value < math.huge and value or nil
end

local function valid(unit)
    return unit and (not unit.IsNull or not unit:IsNull())
end

local function vector(x, y, z)
    return Vector(x, y, z or 0)
end

local function copy(position)
    return vector(position.x, position.y, position.z)
end

local function cell(position)
    if not position or not number(position.x) or not number(position.y) then return nil end
    return math.floor(position.x / CELL), math.floor(position.y / CELL)
end

local function key(x, y)
    return x .. ":" .. y
end

local function point(x, y)
    return vector((x + 0.5) * CELL, (y + 0.5) * CELL, origin.z)
end

local function slot_for(player_id, slot_id)
    if slot_id then
        for _, direction in ipairs(DIRECTIONS) do if direction.id == slot_id then return slot_id end end
        return nil
    end
    if assignments[player_id] then return assignments[player_id] end
    local context = package.loaded["systems/player_context_service"]
    local slot = context and context.slot and context.slot(player_id)
    return slot and slot_for(player_id, slot.slot_id) or nil
end

local function traversable(position)
    if not GridNav or type(GridNav.IsTraversable) ~= "function"
        or type(GridNav.IsBlocked) ~= "function" then return false end
    local walked, walk = pcall(GridNav.IsTraversable, GridNav, position)
    local checked, blocked = pcall(GridNav.IsBlocked, GridNav, position)
    return walked and walk == true and checked and blocked == false
end

local function grounded(position)
    if type(GetGroundPosition) ~= "function" then return nil end
    local ok, result = pcall(GetGroundPosition, position, nil)
    if ok and result and number(result.z) then return vector(position.x, position.y, result.z) end
    return nil
end

local function build_regions()
    if not Entities or type(Entities.FindByName) ~= "function" then return nil, "rich_start_missing" end
    local found, marker = pcall(Entities.FindByName, Entities, nil, "rich_start")
    if not found or not valid(marker) or not marker.GetAbsOrigin then return nil, "rich_start_missing" end
    local located, position = pcall(marker.GetAbsOrigin, marker)
    if not located or not cell(position) or not number(position.z) then return nil, "rich_start_invalid" end
    origin = copy(position)
    if not GridNav or type(GridNav.IsTraversable) ~= "function"
        or type(GridNav.IsBlocked) ~= "function" then return nil, "rich_navigation_unavailable" end
    if type(GetGroundPosition) ~= "function" then return nil, "rich_ground_unavailable" end

    local checked, result, compiled = {}, {}, {}
    local function open(x, y)
        local id = key(x, y)
        if checked[id] == nil then checked[id] = traversable(point(x, y)) end
        return checked[id]
    end
    local function in_bounds(x, y)
        local p = point(x, y)
        return math.abs(p.x - origin.x) <= SEARCH_RADIUS and math.abs(p.y - origin.y) <= SEARCH_RADIUS
    end
    for _, direction in ipairs(DIRECTIONS) do
        local seed_x, seed_y
        -- The marker is in the red central hub. Each cardinal ray intersects
        -- exactly one of the four separate buildable lawns authored in Hammer.
        for distance = CELL, SEARCH_RADIUS - CELL, CELL do
            local x, y = cell(vector(origin.x + direction.x * distance, origin.y + direction.y * distance))
            if open(x, y) then seed_x, seed_y = x, y; break end
        end
        if not seed_x then return nil, "rich_region_missing:" .. direction.id end
        if compiled[key(seed_x, seed_y)] then return nil, "rich_regions_connected:" .. direction.id end
        local queue, head, sum_x, sum_y = { { seed_x, seed_y } }, 1, 0, 0
        local region = { id = direction.id, cells = queue, min_x = math.huge,
            min_y = math.huge, max_x = -math.huge, max_y = -math.huge }
        compiled[key(seed_x, seed_y)] = direction.id
        while head <= #queue do
            local current = queue[head]; head = head + 1
            local x, y = current[1], current[2]
            if not in_bounds(x, y) then return nil, "rich_region_unbounded:" .. direction.id end
            sum_x, sum_y = sum_x + x, sum_y + y
            region.min_x, region.max_x = math.min(region.min_x, x), math.max(region.max_x, x)
            region.min_y, region.max_y = math.min(region.min_y, y), math.max(region.max_y, y)
            for _, offset in ipairs(NEIGHBORS) do
                local nx, ny = x + offset[1], y + offset[2]
                local id = key(nx, ny)
                if not compiled[id] and open(nx, ny) then
                    compiled[id] = direction.id
                    queue[#queue + 1] = { nx, ny }
                    if #queue > MAX_REGION_CELLS then return nil, "rich_region_too_large:" .. direction.id end
                end
            end
        end
        local cx, cy, nearest, score = sum_x / #queue, sum_y / #queue, nil, math.huge
        for _, candidate in ipairs(queue) do
            local distance = (candidate[1] - cx) ^ 2 + (candidate[2] - cy) ^ 2
            if distance < score then nearest, score = candidate, distance end
        end
        region.position = grounded(point(nearest[1], nearest[2]))
        if not region.position then return nil, "rich_ground_invalid:" .. direction.id end
        region.cell_count = #queue
        result[direction.id] = region
    end
    labels = compiled
    return result
end

local function ensure_regions()
    if regions then return true end
    if initialization_error then return false, initialization_error end
    local result, reason = build_regions()
    if not result then initialization_error = reason; return false, reason end
    regions = result
    return true
end

function M.center()
    if not rich() then return nil, "rich_mode_inactive" end
    local ok, reason = ensure_regions()
    return ok and copy(origin) or nil, reason
end

function M.region(player_id, slot_id)
    if not rich() then return nil, "rich_mode_inactive" end
    player_id = number(player_id)
    if not player_id or player_id < 0 or player_id ~= math.floor(player_id) then return nil, "rich_invalid_player" end
    local id = slot_for(player_id, slot_id)
    if not id then return nil, "rich_player_slot_missing" end
    if assignments[player_id] and assignments[player_id] ~= id then return nil, "rich_player_slot_changed" end
    local ok, reason = ensure_regions()
    if not ok then return nil, reason end
    assignments[player_id] = id
    return regions[id]
end

function M.resolve_spawn(player_id, slot_id)
    local region, reason = M.region(player_id, slot_id)
    if not region then return nil, reason end
    -- Reuse the cached discovery; only this landing is checked against live
    -- obstacles. A building must never make a later player flood a new region.
    local position = traversable(region.position) and grounded(region.position) or nil
    if not position then
        for _, candidate in ipairs(region.cells) do
            local sample = point(candidate[1], candidate[2])
            if traversable(sample) then position = grounded(sample) end
            if position then break end
        end
    end
    if not position then return nil, "rich_spawn_not_traversable" end
    return { position = position, marker = "rich_start", source = "rich_region_navigation",
        slot_id = region.id, mode = "rich" }
end

function M.wave_spawn(player_id)
    if not rich() then return nil, "rich_mode_inactive" end
    local region, reason = M.region(player_id)
    if not region then return nil, reason end
    if region.wave_position and traversable(region.wave_position) then return copy(region.wave_position) end
    if not region.wave_candidates then
        local candidates = {}
        for _, candidate in ipairs(region.cells) do
            local x, y = candidate[1], candidate[2]
            local position, padding = point(x, y), 2
            for dx = -2, 2 do
                for dy = -2, 2 do
                    if labels[key(x + dx, y + dy)] ~= region.id then
                        padding = math.min(padding, math.max(math.abs(dx), math.abs(dy)) - 1)
                    end
                end
            end
            local separate = (position.x - region.position.x) ^ 2 + (position.y - region.position.y) ^ 2 >= 512 ^ 2
            candidates[#candidates + 1] = { position = position, padding = padding,
                separate = separate, distance = (position.x - origin.x) ^ 2 + (position.y - origin.y) ^ 2 }
        end
        table.sort(candidates, function(left, right)
            if left.separate ~= right.separate then return left.separate end
            if left.padding ~= right.padding then return left.padding > right.padding end
            if left.distance ~= right.distance then return left.distance < right.distance end
            if left.position.x ~= right.position.x then return left.position.x < right.position.x end
            return left.position.y < right.position.y
        end)
        region.wave_candidates = candidates
    end
    -- There are no entity blockers or navigation edits: monsters enter the
    -- player's own island on its inner edge and use normal combat afterwards.
    for _, candidate in ipairs(region.wave_candidates) do
        if traversable(candidate.position) then
            local position = grounded(candidate.position)
            if position then region.wave_position = position; return copy(position) end
        end
    end
    return nil, "rich_wave_spawn_not_traversable"
end

function M.validate_position(player_id, position)
    if not rich() then return true end
    local region, reason = M.region(player_id)
    if not region then return false, reason end
    local x, y = cell(position)
    if not x then return false, "rich_invalid_destination" end
    if labels[key(x, y)] ~= region.id then return false, "rich_destination_outside_own_region" end
    return true
end

M.validate_cell = M.validate_position

function M.validate_building_footprint(player_id, min_x, min_y, max_x, max_y)
    if not rich() then return true end
    local region, reason = M.region(player_id)
    if not region then return false, reason end
    min_x, min_y, max_x, max_y = number(min_x), number(min_y), number(max_x), number(max_y)
    if not min_x or not min_y or not max_x or not max_y or min_x >= max_x or min_y >= max_y then
        return false, "rich_invalid_footprint"
    end
    -- Include every cell touched by the footprint, not just four corners: an
    -- interior red navigation hole must remain unbuildable as well.
    local first_x, first_y = math.floor(min_x / CELL), math.floor(min_y / CELL)
    local last_x, last_y = math.ceil(max_x / CELL) - 1, math.ceil(max_y / CELL) - 1
    if first_x < region.min_x or first_y < region.min_y or last_x > region.max_x or last_y > region.max_y then
        return false, "rich_building_outside_own_region"
    end
    for x = first_x, last_x do
        for y = first_y, last_y do
            if labels[key(x, y)] ~= region.id then return false, "rich_building_outside_own_region" end
        end
    end
    return true
end

local function builder_owner(unit)
    if not valid(unit) or unit.survival_builder_id == nil then return nil end
    local id = number(unit.survival_player_id)
    return id and id >= 0 and id or nil
end

local function order_is(value, names)
    for _, name in ipairs(names) do if _G[name] ~= nil and value == tonumber(_G[name]) then return true end end
    return false
end

function M.validate_order(keys, units)
    if not rich() then return true end
    local has_builder = false
    for _, unit in ipairs(units or {}) do
        if unit.survival_builder_id ~= nil then has_builder = true; break end
    end
    -- Monster AI and ordinary units never need destination/target queries here.
    if not has_builder then return true end
    local order = tonumber(keys.order_type)
    local point_order = order_is(order, POINT_ORDERS)
    local target_order = order_is(order, TARGET_ORDERS)
    local target, destination
    if point_order then
        destination = number(keys.position_x) and number(keys.position_y)
            and vector(tonumber(keys.position_x), tonumber(keys.position_y), number(keys.position_z) or 0) or nil
    elseif target_order and EntIndexToHScript and tonumber(keys.entindex_target) then
        local ok, entity = pcall(EntIndexToHScript, tonumber(keys.entindex_target))
        if ok and valid(entity) and entity.GetAbsOrigin then target, destination = entity, entity:GetAbsOrigin() end
    end
    for _, unit in ipairs(units or {}) do
        local player_id = builder_owner(unit)
        if player_id then
            if point_order or target_order then
                local ok, reason = M.validate_position(player_id, destination)
                if not ok then return false, reason end
            end
            local record = builders[player_id]
            if record and record.unit == unit then record.follow_target = target end
        end
    end
    return true
end

function M.guard()
    if not rich() then guard_active = false; return false end
    local count = 0
    for player_id, record in pairs(builders) do
        local unit = record.unit
        if not valid(unit) then builders[player_id] = nil
        else
            count = count + 1
            if record.follow_target then
                if not valid(record.follow_target) then record.follow_target = nil
                elseif not M.validate_position(player_id, record.follow_target:GetAbsOrigin()) then
                    if unit.Stop then unit:Stop() end
                    record.follow_target = nil
                end
            end
            local position = unit:GetAbsOrigin()
            if M.validate_position(player_id, position) then record.last_safe = copy(position)
            else
                if unit.Stop then unit:Stop() end
                if unit.SetOrigin then unit:SetOrigin(copy(record.last_safe))
                else unit:SetAbsOrigin(copy(record.last_safe)) end
            end
        end
    end
    if count == 0 then guard_active = false; return false end
    return true
end

function M.attach_builder(player_id, unit, slot_id)
    if not rich() then return true end
    player_id = number(player_id)
    if not valid(unit) or builder_owner(unit) ~= player_id then return false, "rich_builder_owner_mismatch" end
    local region, reason = M.region(player_id, slot_id)
    if not region then return false, reason end
    local allowed = M.validate_position(player_id, unit:GetAbsOrigin())
    if not allowed then return false, "rich_builder_spawn_outside_own_region" end
    builders[player_id] = { unit = unit, last_safe = copy(unit:GetAbsOrigin()) }
    if not guard_active then
        require("core/scheduler").every(0.10, M.guard, GUARD_TASK)
        guard_active = true
    end
    return true
end

function M.detach_builder(player_id, unit)
    player_id = tonumber(player_id)
    local record = player_id and builders[player_id]
    if record and (not unit or record.unit == unit) then builders[player_id] = nil end
end

function M.init()
    local scheduler = package.loaded["core/scheduler"]
    if scheduler and scheduler.cancel then scheduler.cancel(GUARD_TASK) end
    regions, labels, assignments, builders = nil, {}, {}, {}
    origin, initialization_error, guard_active = nil, nil, false
end

return M
