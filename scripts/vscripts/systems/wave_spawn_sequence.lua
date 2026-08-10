local M = {}

local function is_normal(row)
    local role = tostring(row and row.member_role or "")
    return role == "" or role == "normal"
end

local function count_for(row)
    return math.max(0, math.floor(tonumber(row and row.monster_count) or 0))
end

local function append_repeated(result, row)
    for _ = 1, count_for(row) do
        result[#result + 1] = row
    end
end

local function append_round_robin(result, rows)
    local remaining = {}
    local pending = 0
    for index, row in ipairs(rows) do
        remaining[index] = count_for(row)
        pending = pending + remaining[index]
    end

    while pending > 0 do
        for index, row in ipairs(rows) do
            if remaining[index] > 0 then
                result[#result + 1] = row
                remaining[index] = remaining[index] - 1
                pending = pending - 1
            end
        end
    end
end

local function group_queue(rows)
    local queue = {
        rows = rows,
        remaining = {},
        pending = 0,
        next_index = 1,
    }
    for index, row in ipairs(rows) do
        queue.remaining[index] = count_for(row)
        queue.pending = queue.pending + queue.remaining[index]
    end
    return queue
end

local function take_next(queue)
    if queue.pending <= 0 then return nil end
    for _ = 1, #queue.rows do
        local index = queue.next_index
        queue.next_index = index % #queue.rows + 1
        if queue.remaining[index] > 0 then
            queue.remaining[index] = queue.remaining[index] - 1
            queue.pending = queue.pending - 1
            return queue.rows[index]
        end
    end
    return nil
end

local function append_mixed_movement(result, rows, movement_type)
    local ground_rows = {}
    local flying_rows = {}
    for _, row in ipairs(rows) do
        if movement_type(row) == "flying" then
            flying_rows[#flying_rows + 1] = row
        else
            ground_rows[#ground_rows + 1] = row
        end
    end
    if #ground_rows == 0 or #flying_rows == 0 then
        append_round_robin(result, rows)
        return
    end

    local ground = group_queue(ground_rows)
    local flying = group_queue(flying_rows)
    while ground.pending > 0 or flying.pending > 0 do
        for _ = 1, 2 do
            local row = take_next(ground)
            if row then result[#result + 1] = row end
        end
        local row = take_next(flying)
        if row then result[#result + 1] = row end
    end
end

function M.build(batches, options)
    local result = {}
    local index = 1
    batches = batches or {}
    if type(options) ~= "table" then
        options = { enabled = options ~= false }
    end
    local enabled = options.enabled ~= false
    local movement_type = options.movement_type

    while index <= #batches do
        local row = batches[index]
        if enabled and is_normal(row) then
            local normal_rows = {}
            while index <= #batches and is_normal(batches[index]) do
                normal_rows[#normal_rows + 1] = batches[index]
                index = index + 1
            end
            if type(movement_type) == "function" then
                append_mixed_movement(result, normal_rows, movement_type)
            else
                append_round_robin(result, normal_rows)
            end
        else
            append_repeated(result, row)
            index = index + 1
        end
    end

    return result
end

function M.is_normal(row)
    return is_normal(row)
end

return M