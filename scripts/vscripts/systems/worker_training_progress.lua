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
        train_duration = row and (tonumber(row.training_duration_seconds) or 1) or 1,
        wood_per_hit = row and (tonumber(row.wood_per_hit) or 0) or 0,
        base_attack = row and (tonumber(row.base_attack) or 0) or 0,
        repair_max_health_pct_per_second = row
            and (tonumber(row.repair_max_health_pct_per_second) or 0) or 0,
        repair_range = row and (tonumber(row.repair_range) or 0) or 0,
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

    function tracker:get_for(team, training_id)
        local state = state_for(team)
        for _, row in ipairs(self.rows) do
            if row.training_id == training_id then
                return snapshot(state, row)
            end
        end
        return nil
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

    function tracker:get_all(owner_key)
        local state = state_for(owner_key)
        local result = {}
        for _, row in ipairs(self.rows) do result[#result + 1] = snapshot(state, row) end
        return result
    end

    function tracker:record_explicit(team, training_id)
        local state = state_for(team)
        for _, row in ipairs(self.rows) do
            if row.training_id == training_id then
                local count = (state.counts[training_id] or 0) + 1
                state.counts[training_id] = count
                local result = snapshot(state, row)
                result.completed_training_id = training_id
                result.completed_count = count
                result.advanced = 0
                return result
            end
        end
        return nil, error_prefix .. "_training_not_found"
    end

    -- Independent entrances can finish in any order. Keep the legacy current
    -- tier on the first unfinished tier, without changing repairer tracking.
    function tracker:record_independent(owner_key, training_id)
        local result, error_code = self:record_explicit(owner_key, training_id)
        if not result then return nil, error_code end
        local state = state_for(owner_key)
        local previous_index = state.current_index
        while state.current_index < #self.rows do
            local current = self.rows[state.current_index]
            local maximum = maximum_for(current)
            if maximum < 0 or (state.counts[current.training_id] or 0) < maximum then break end
            state.current_index = state.current_index + 1
        end
        result.advanced = state.current_index ~= previous_index and 1 or 0
        return result
    end

    return tracker
end

return M