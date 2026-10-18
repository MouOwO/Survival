local M = {}
local FIELDS = { "health", "attack", "war3_armor" }

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

function M.resolve(row, batch_ordinal)
    local variants = row.rich_stat_variants
    if type(variants) ~= "table" or #variants == 0 then return row end
    assert(type(batch_ordinal) == "number" and batch_ordinal >= 1
        and batch_ordinal == math.floor(batch_ordinal), "rich_variant_batch_ordinal_invalid")
    local index = (batch_ordinal - 1) % #variants + 1
    local variant = variants[index]
    local result = clone(row)
    for _, field in ipairs(FIELDS) do
        local value = variant[field]
        assert(type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge,
            "rich_variant_stat_invalid:" .. field)
        result[field] = value
    end
    result.rich_variant_index, result.rich_variant_count = index, #variants
    result.rich_field_sources = clone(variant.field_sources)
    result.rich_source_record_id = variant.source_record_id
    result.rich_stats_source = variant.stats_source
    result.rich_stats_estimated = variant.estimated == true
    result.rich_estimation_method = variant.estimation_method
    return result
end

return M
