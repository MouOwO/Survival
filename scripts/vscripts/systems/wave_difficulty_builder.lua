local difficulty_config = require("config/difficulty_config")

local M = {}
local SCALED_STATS = { "health", "attack", "war3_armor" }

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function source_waves(rows, difficulty_id)
    local waves = {}
    for _, row in ipairs(rows or {}) do
        if row.enabled ~= false and row.difficulty_id == difficulty_id then
            waves[row.wave_number] = waves[row.wave_number] or {}
            table.insert(waves[row.wave_number], row)
        end
    end
    for _, batches in pairs(waves) do
        table.sort(batches, function(a, b)
            return (a.spawn_order or 0) < (b.spawn_order or 0)
        end)
    end
    return waves
end

local function override_for(definition, wave_number)
    for _, rule in ipairs(definition.wave_overrides or {}) do
        if wave_number >= rule.target_start and wave_number <= rule.target_end then
            return rule
        end
    end
    return nil
end

local function scaled_row(template, definition, wave_number, multiplier)
    local row = clone(template)
    row.wave_id = string.format(
        "%s_wave_%02d_%s",
        string.lower(definition.difficulty_id),
        wave_number,
        string.lower(tostring(template.batch_id or "batch"))
    )
    row.difficulty_id = definition.difficulty_id
    row.wave_number = wave_number
    for _, field in ipairs(SCALED_STATS) do
        local value = tonumber(template[field])
        if value ~= nil then row[field] = value * multiplier end
    end
    return row
end

function M.build(rows, difficulty_id)
    local definition = difficulty_config.get(difficulty_id)
    if not definition then return nil, "difficulty_not_found" end

    local base = source_waves(rows, definition.source_difficulty_id)
    local waves = {}
    local flattened = {}
    for wave_number = 1, definition.total_waves do
        local rule = override_for(definition, wave_number)
        local templates
        local multiplier
        if rule then
            local source_number = rule.source_start
                + (wave_number - rule.target_start)
            templates = waves[source_number]
            multiplier = tonumber(rule.stat_multiplier) or 1
        else
            templates = base[wave_number]
            multiplier = tonumber(definition.stat_multiplier) or 1
        end
        if not templates or #templates == 0 then
            return nil, "source_wave_not_found:" .. tostring(wave_number)
        end

        local batches = {}
        for _, template in ipairs(templates) do
            local row = scaled_row(
                template,
                definition,
                wave_number,
                multiplier
            )
            batches[#batches + 1] = row
            flattened[#flattened + 1] = row
        end
        waves[wave_number] = batches
    end

    return {
        difficulty = definition,
        total_waves = definition.total_waves,
        rows = flattened,
        waves = waves,
    }
end

return M