local config = require("config/generated/rich_wave_profiles")
local recorded_config = require("config/generated/rich_monster_profiles")
local M = {}
local FIELDS = { "health", "attack", "war3_armor" }

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function role(row)
    if row.is_boss == true or row.member_role == "assault_boss" then return "boss" end
    if row.member_role == "wave_leader" then return "leader" end
    return "normal"
end

local function normal_profile(profile, row)
    return profile.batch_overrides[row.batch_id]
        or profile.archetype_overrides[row.archetype_id] or profile.normal
end

local function ordinary_reference(wave, row)
    for _, candidate in ipairs(wave) do
        if role(candidate) == "normal" and candidate.archetype_id == row.archetype_id then
            return candidate
        end
    end
    for _, candidate in ipairs(wave) do
        if role(candidate) == "normal" then return candidate end
    end
end

local function reference_row(wave, row)
    for _, candidate in ipairs(wave) do
        if candidate.batch_id == row.batch_id then return candidate end
    end
    for _, candidate in ipairs(wave) do
        if role(candidate) == role(row) and candidate.archetype_id == row.archetype_id then
            return candidate
        end
    end
    for _, candidate in ipairs(wave) do
        if role(candidate) == role(row) then return candidate end
    end
    return ordinary_reference(wave, row)
end

local function resolved_profile(profile, row, reference_wave)
    local kind = role(row)
    if kind == "boss" then return profile.boss, "boss" end
    if kind == "leader" and profile.leader then return profile.leader, "leader" end
    if kind == "normal" then return normal_profile(profile, row), "normal" end
    -- Unrecorded leader variants retain their existing ratio to the ordinary
    -- monster of that model; they are not presented as OCR observations.
    local ordinary = assert(ordinary_reference(reference_wave, row), "rich_normal_reference_missing")
    local base = normal_profile(profile, ordinary)
    local leader = reference_row(reference_wave, row)
    local result = { estimated = true, estimation_method = "existing_leader_ratio" }
    for _, field in ipairs(FIELDS) do
        result[field] = base[field] * (leader[field] / ordinary[field])
    end
    return result, "leader_ratio"
end

local function redistribute(batches)
    local ordinary, fixed, original_total = {}, 0, 0
    for index, row in ipairs(batches) do
        local count = math.max(0, math.floor(tonumber(row.monster_count) or 0))
        if role(row) == "normal" then
            ordinary[#ordinary + 1] = { row = row, weight = count, index = index }
            original_total = original_total + count
        else
            fixed = fixed + count
        end
    end
    local budget = config.total_count_per_wave - fixed
    assert(budget >= 0 and #ordinary > 0 and original_total > 0, "rich_wave_count_budget_invalid")
    local assigned = 0
    for _, entry in ipairs(ordinary) do
        local exact = budget * entry.weight / original_total
        entry.row.monster_count = math.floor(exact)
        entry.fraction = exact - entry.row.monster_count
        assigned = assigned + entry.row.monster_count
    end
    table.sort(ordinary, function(a, b)
        if a.fraction == b.fraction then return a.index < b.index end
        return a.fraction > b.fraction
    end)
    for index = 1, budget - assigned do
        ordinary[index].row.monster_count = ordinary[index].row.monster_count + 1
    end
end

function M.apply(built, source_rows)
    local difficulty_id = built.difficulty.difficulty_id
    local recorded = (recorded_config.difficulties or {})[difficulty_id]
    if recorded then
        -- These are final N2/N3 values, including explicitly marked estimates.
        -- Applying the old N1 difficulty ratio here would scale them twice.
        local result = { difficulty = built.difficulty, total_waves = built.total_waves,
            rows = {}, waves = {}, mode_id = config.mode_id }
        for wave_number = 1, built.total_waves do
            local profile = assert(recorded.waves[wave_number], "rich_recorded_wave_missing")
            local batches = {}
            for _, template in ipairs(built.waves[wave_number]) do
                local stats = assert(profile.batches[template.batch_id], "rich_recorded_batch_missing")
                local row = clone(template)
                for _, field in ipairs(FIELDS) do
                    assert(type(stats[field]) == "number", "rich_recorded_stat_missing:" .. field)
                    row[field] = stats[field]
                end
                row.rich_reference_wave = wave_number
                row.rich_difficulty_scaled = false
                row.rich_stats_source = stats.stats_source
                row.rich_stats_estimated = stats.estimated == true
                row.rich_estimation_method = stats.estimation_method
                row.rich_source_record_id = stats.source_record_id
                row.rich_field_sources = clone(stats.field_sources)
                row.rich_stat_variants = clone(stats.variants)
                batches[#batches + 1] = row
                result.rows[#result.rows + 1] = row
            end
            redistribute(batches)
            result.waves[wave_number] = batches
        end
        return result
    end
    local n1 = {}
    for _, row in ipairs(source_rows) do
        if row.enabled ~= false and row.difficulty_id == config.source_difficulty_id then
            n1[row.wave_number] = n1[row.wave_number] or {}
            n1[row.wave_number][#n1[row.wave_number] + 1] = row
        end
    end
    -- The ordinary builder can return references to its input rows. Clone all
    -- batches before the first override so mode selection never changes them.
    local result = { difficulty = built.difficulty, total_waves = built.total_waves,
        rows = {}, waves = {}, mode_id = config.mode_id }
    for wave_number = 1, built.total_waves do
        local reference_number = math.min(wave_number, config.last_recorded_wave)
        local profile = assert(config.waves[reference_number], "rich_wave_profile_missing")
        local reference_wave = assert(n1[reference_number], "rich_n1_reference_missing")
        local batches = {}
        for _, template in ipairs(built.waves[wave_number]) do
            local row = clone(template)
            local reference = assert(reference_row(reference_wave, row), "rich_batch_reference_missing")
            local stats, kind = resolved_profile(profile, row, reference_wave)
            assert(stats, "rich_stats_missing")
            local scaling_template = template
            if kind == "leader" and role(reference) == "normal" then
                -- Some higher difficulties contain a W4 leader absent from
                -- N1's batches. Its recorded leader profile already includes
                -- that strength: use the ordinary difficulty ratio only once.
                scaling_template = assert(ordinary_reference(built.waves[wave_number], row),
                    "rich_higher_normal_reference_missing")
                row.rich_difficulty_reference_role = "normal"
            end
            for _, field in ipairs(FIELDS) do
                local value = stats[field]
                if built.difficulty.difficulty_id ~= config.source_difficulty_id then
                    value = value * (scaling_template[field] / reference[field])
                end
                row[field] = math.floor(value + 0.5)
            end
            row.rich_reference_wave = reference_number
            row.rich_difficulty_scaled = built.difficulty.difficulty_id ~= config.source_difficulty_id
            row.rich_stats_source = kind == "leader_ratio" and "existing_leader_ratio"
                or (stats.estimated and "boss_interpolation" or "ocr")
            row.rich_stats_estimated = stats.estimated == true
            row.rich_estimation_method = stats.estimation_method
            row.rich_source_record_id = stats.source_record_id
            batches[#batches + 1] = row
            result.rows[#result.rows + 1] = row
        end
        redistribute(batches)
        result.waves[wave_number] = batches
    end
    return result
end

return M
