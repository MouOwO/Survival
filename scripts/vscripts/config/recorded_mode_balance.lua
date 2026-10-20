-- Independent final combat values for the recorded cold/scourge modes.
-- CSV values are already difficulty-adjusted; never multiply them again.
local M = {
    modes = {
        cold = { display_name = "极寒模式", difficulties = { "N1", "N2", "N3", "N4" }, temporary_source_difficulty_id = "N4" },
        scourge = { display_name = "天灾模式", difficulties = { "N1", "N2" }, temporary_source_difficulty_id = "N2" },
    },
}

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function normalized(row)
    local result = {}
    for key, value in pairs(row) do if value ~= "" then result[key] = clone(value) end end
    return result
end

function M.has_mode(mode_id) return M.modes[mode_id] ~= nil end

-- Explicit temporary configuration: missing N1-N10 targets reuse this mode's
-- highest recorded tier. Recorded CSVs and observed values remain unchanged.
function M.source_difficulty(mode_id, difficulty_id)
    local mode = M.modes[mode_id]
    local number = type(difficulty_id) == "string" and tonumber(difficulty_id:match("^N([1-9]%d*)$")) or nil
    if not mode or not number or number > 10 then return nil end
    for _, id in ipairs(mode and mode.difficulties or {}) do
        if id == difficulty_id then return id end
    end
    local temporary = mode.temporary_source_difficulty_id
    local source_number = temporary and tonumber(temporary:match("^N(%d+)$"))
    if source_number and number > source_number then return temporary end
    return nil
end

function M.has_difficulty(mode_id, difficulty_id)
    return M.source_difficulty(mode_id, difficulty_id) ~= nil
end

function M.configuration_note(mode_id, difficulty_id)
    local source_id = M.source_difficulty(mode_id, difficulty_id)
    if source_id and source_id ~= difficulty_id then
        return "临时配置：沿用" .. M.modes[mode_id].display_name .. " " .. source_id .. " 的波次与怪物属性。"
    end
    return ""
end

local function selected_row(source, mode_id, difficulty_id, source_id)
    local row = normalized(source)
    if source_id == difficulty_id then return row end
    row.difficulty_id, row.source_difficulty_id = difficulty_id, source_id
    row.temporary_config, row.balance_fallback = true, true
    row.balance_configuration_note = M.configuration_note(mode_id, difficulty_id)
    row.source_data_status, row.data_status = row.data_status, "temporary_inherited"
    for _, key in ipairs({"wave_id", "variant_id", "profile_id"}) do
        if type(row[key]) == "string" then
            row["source_" .. key] = row[key]
            row[key] = row[key]:gsub("^" .. mode_id .. "_" .. source_id:lower() .. "_",
                mode_id .. "_" .. difficulty_id:lower() .. "_", 1)
        end
    end
    return row
end

function M.build_waves(definition, mode_id)
    local difficulty_id = definition.difficulty_id
    local source_id = M.source_difficulty(mode_id, difficulty_id)
    if not source_id then
        return nil, "recorded_mode_difficulty_missing:" .. tostring(mode_id) .. ":" .. tostring(difficulty_id)
    end
    local result = { difficulty = definition, total_waves = definition.total_waves,
        rows = {}, waves = {}, mode_id = mode_id, source_difficulty_id = source_id,
        temporary_config = source_id ~= difficulty_id, configuration_note = M.configuration_note(mode_id, difficulty_id) }
    local variants = {}
    for _, source in ipairs(require("config/generated/recorded_mode_wave_stat_variants").rows) do
        if source.enabled ~= false and source.mode_id == mode_id and source.difficulty_id == source_id then
            local key = tostring(source.wave_number) .. ":" .. source.batch_id
            variants[key] = variants[key] or {}
            variants[key][#variants[key] + 1] = source
        end
    end
    for _, source in ipairs(require("config/generated/recorded_mode_wave_definitions").rows) do
        if source.enabled ~= false and source.mode_id == mode_id and source.difficulty_id == source_id then
            local row = selected_row(source, mode_id, difficulty_id, source_id)
            local selected = variants[tostring(row.wave_number) .. ":" .. row.batch_id]
            if selected then
                table.sort(selected, function(a,b) return a.variant_index < b.variant_index end)
                row.rich_stat_variants = {}
                for _, variant in ipairs(selected) do
                    row.rich_stat_variants[#row.rich_stat_variants + 1] = selected_row(variant, mode_id, difficulty_id, source_id)
                end
            end
            result.waves[row.wave_number] = result.waves[row.wave_number] or {}
            result.waves[row.wave_number][#result.waves[row.wave_number] + 1] = row
        end
    end
    for number = 1, result.total_waves do
        local rows = result.waves[number]
        if not rows or #rows == 0 then
            return nil, "recorded_mode_wave_missing:" .. mode_id .. ":" .. difficulty_id .. ":" .. number
        end
        table.sort(rows, function(a,b) return (a.spawn_order or 0) < (b.spawn_order or 0) end)
        for _, row in ipairs(rows) do result.rows[#result.rows + 1] = row end
    end
    return result
end

function M.resolve_member(member_id, difficulty_id, mode_id)
    local source_id = M.source_difficulty(mode_id, difficulty_id)
    for _, row in ipairs(require("config/generated/recorded_mode_challenge_combat_profiles").rows) do
        if row.enabled ~= false and row.mode_id == mode_id and row.difficulty_id == source_id
            and row.member_id == member_id then return selected_row(row, mode_id, difficulty_id, source_id), nil end
    end
    return nil, "recorded_mode_member_missing:" .. tostring(mode_id) .. ":"
        .. tostring(difficulty_id) .. ":" .. tostring(member_id)
end

return M
