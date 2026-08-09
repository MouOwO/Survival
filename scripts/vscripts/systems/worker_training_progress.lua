local M = {}

local function maximum_for(row)
    return tonumber(row and row.max_count) or 0
end

local function training_rows(definitions, prefix)
    local rows = {}
    for _, row in ipairs(definitions.rows or {}) do
        if row.enabled ~= false
            and row.training_type == "unit"
            and string.match(row.training_id or "", "^" .. prefix) then
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(left, right)
        return (tonumber(left.level) or 0) < (tonumber(right.level) or 0)
    end)
    return rows
end

local function snapshot(state, row)
    local training_id = row and row.training_id or nil
    local count = training_id and (state.counts[training_id] or 0) or 0
    local maximum = maximum_for(row)
    local requires_city_level = row and tonumber(row.requires_city_level) or nil
    if requires_city_level == nil then
        requires_city_level = tonumber(string.match(
            tostring(row and row.prerequisite_text or ""),
            "LV(%d+)"
        )) or 1
    end
    local completed = maximum >= 0 and count >= maximum
    return {
        training_id = training_id,
        level = row and (tonumber(row.level) or 1) or 1,
        name = row and row.name or "农民LV1",
        count = count,
        max_count = maximum,
        unlimited = maximum < 0 and 1 or 0,
        completed = completed and 1 or 0,
        requires_city_level = requires_city_level,
        wood_cost = row and (tonumber(row.wood_cost) or 0) or 0,
        gold_cost = row and (tonumber(row.gold_cost) or 0) or 0,
        population_cost = row and (tonumber(row.population_cost) or 0) or 0,
        wood_per_hit = row and (tonumber(row.wood_per_hit) or 0) or 0,
        base_attack = row and (tonumber(row.base_attack) or 0) or 0,
    }
end

function M.create(definitions, prefix, error_prefix)
    prefix = tostring(prefix or "train_lumberjack_")
    error_prefix = tostring(error_prefix or "lumberjack")
    local rows = training_rows(definitions or {}, prefix)
    assert(#rows > 0, error_prefix .. " training definitions are required")

    local tracker = { rows = rows, states = {} }

    local function state_for(team)
        local key = tonumber(team) or team
        tracker.states[key] = tracker.states[key] or {
            current_index = 1,
            counts = {},
        }
        return tracker.states[key]
    end

    function tracker:reset()
        self.states = {}
    end

    function tracker:current(team)
        local state = state_for(team)
        return self.rows[state.current_index]
    end

    function tracker:get(team)
        local state = state_for(team)
        return snapshot(state, self.rows[state.current_index])
    end

    function tracker:record_success(team, training_id)
        local state = state_for(team)
        local row = self.rows[state.current_index]
        if not row or row.training_id ~= training_id then
            return nil, error_prefix .. "_training_not_current"
        end

        local count = (state.counts[training_id] or 0) + 1
        state.counts[training_id] = count
        local maximum = maximum_for(row)
        local advanced = false
        if maximum > 0 and count >= maximum
            and state.current_index < #self.rows then
            state.current_index = state.current_index + 1
            advanced = true
        end

        local result = snapshot(state, self.rows[state.current_index])
        result.completed_training_id = training_id
        result.completed_count = count
        result.advanced = advanced and 1 or 0
        return result
    end

    return tracker
end

return M