-- Independent final combat values for the recorded cold/scourge modes.
-- CSV values are already difficulty-adjusted; never multiply them again.
local M = {
    modes = {
        cold = { display_name = "极寒模式", difficulties = { "N1", "N2", "N3", "N4" } },
        scourge = { display_name = "天灾模式", difficulties = { "N1", "N2" } },
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

function M.has_difficulty(mode_id, difficulty_id)
    local mode = M.modes[mode_id]
    for _, id in ipairs(mode and mode.difficulties or {}) do
        if id == difficulty_id then return true end
    end
    return false
end

function M.build_waves(definition, mode_id)
    local difficulty_id = definition.difficulty_id
    if not M.has_difficulty(mode_id, difficulty_id) then
        return nil, "recorded_mode_difficulty_missing:" .. tostring(mode_id) .. ":" .. tostring(difficulty_id)
    end
    local result = { difficulty = definition, total_waves = definition.total_waves,
        rows = {}, waves = {}, mode_id = mode_id }
    local variants = {}
    for _, source in ipairs(require("config/generated/recorded_mode_wave_stat_variants").rows) do
        if source.enabled ~= false and source.mode_id == mode_id and source.difficulty_id == difficulty_id then
            local key = tostring(source.wave_number) .. ":" .. source.batch_id
            variants[key] = variants[key] or {}
            variants[key][#variants[key] + 1] = source
        end
    end
    for _, source in ipairs(require("config/generated/recorded_mode_wave_definitions").rows) do
        if source.enabled ~= false and source.mode_id == mode_id and source.difficulty_id == difficulty_id then
            local row = normalized(source)
            local selected = variants[tostring(row.wave_number) .. ":" .. row.batch_id]
            if selected then
                table.sort(selected, function(a,b) return a.variant_index < b.variant_index end)
                row.rich_stat_variants = {}
                for _, variant in ipairs(selected) do
                    row.rich_stat_variants[#row.rich_stat_variants + 1] = normalized(variant)
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
    for _, row in ipairs(require("config/generated/recorded_mode_challenge_combat_profiles").rows) do
        if row.enabled ~= false and row.mode_id == mode_id and row.difficulty_id == difficulty_id
            and row.member_id == member_id then return normalized(row), nil end
    end
    return nil, "recorded_mode_member_missing:" .. tostring(mode_id) .. ":"
        .. tostring(difficulty_id) .. ":" .. tostring(member_id)
end

return M
