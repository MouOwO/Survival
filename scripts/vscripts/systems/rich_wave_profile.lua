local definitions = require("config/generated/rich_wave_definitions")
local stat_variants = require("config/generated/rich_wave_stat_variants")

local M = {}
local VARIANT_FIELDS = { "health", "attack", "war3_armor", "estimated",
    "stats_source", "source_record_id", "estimation_method", "field_sources" }

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function variant_key(row)
    return tostring(row.wave_number) .. ":" .. tostring(row.batch_id)
end

local function variants_for(difficulty_id)
    local indexed = {}
    for _, row in ipairs(stat_variants.rows or {}) do
        if row.enabled ~= false and row.difficulty_id == difficulty_id then
            local key = variant_key(row)
            indexed[key] = indexed[key] or {}
            indexed[key][#indexed[key] + 1] = row
        end
    end
    for _, rows in pairs(indexed) do
        table.sort(rows, function(a, b) return a.variant_index < b.variant_index end)
    end
    return indexed
end

function M.build(definition)
    local difficulty_id = definition.difficulty_id
    local variants = variants_for(difficulty_id)
    local result = { difficulty = definition, total_waves = definition.total_waves,
        rows = {}, waves = {}, mode_id = "rich" }
    for _, source in ipairs(definitions.rows or {}) do
        if source.enabled ~= false and source.difficulty_id == difficulty_id then
            local row = {}
            for key, value in pairs(source) do
                if value ~= "" then row[key] = clone(value) end
            end
            local selected = variants[variant_key(row)]
            if selected then
                row.rich_stat_variants = {}
                for _, source_variant in ipairs(selected) do
                    local variant = {}
                    for _, field in ipairs(VARIANT_FIELDS) do
                        local value = source_variant[field]
                        if value ~= "" then variant[field] = clone(value) end
                    end
                    row.rich_stat_variants[#row.rich_stat_variants + 1] = variant
                end
            end
            local number = row.wave_number
            result.waves[number] = result.waves[number] or {}
            result.waves[number][#result.waves[number] + 1] = row
        end
    end
    for number = 1, result.total_waves do
        local batches = result.waves[number]
        if not batches or #batches == 0 then
            return nil, "rich_source_wave_not_found:" .. tostring(difficulty_id) .. ":" .. tostring(number)
        end
        table.sort(batches, function(a, b) return (a.spawn_order or 0) < (b.spawn_order or 0) end)
        for _, row in ipairs(batches) do result.rows[#result.rows + 1] = row end
    end
    return result
end

return M
