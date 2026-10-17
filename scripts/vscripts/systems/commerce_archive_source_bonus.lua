-- P151 grants 20% more of the owner's shadow/cage archive item effects.
-- Read the authenticated mode-projected save only. Never write back totals or
-- consult an account baseline: pure matches may use only newly earned sources.
local shadow = require("config/generated/archive_shadow_items")
local cage = require("config/generated/archive_cage_items")
local M = {}
local MARKER = "commerce_p151"
local MULTIPLIER = 0.2
local function table_value(value)
    return type(value) == "table" and value or {}
end
local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function count(value, maximum)
    if not finite(value) or value < 1 or value ~= math.floor(value) then return 0 end
    if not finite(maximum) or maximum < 1 then return 0 end
    return math.min(value, math.floor(maximum))
end
function M.project(save)
    save = table_value(save)
    local inventory = table_value(save.content_inventory)
    if count(inventory[MARKER], 1) == 0 then return {} end
    local archive, result = table_value(save.archive), {}
    local function add_source(config, source_counts)
        source_counts = table_value(source_counts)
        for _, item in ipairs(config.rows or {}) do
            local owned = item.enabled ~= false
                and count(source_counts[item.item_id], tonumber(item.max_owned)) or 0
            if owned > 0 then
                for index, field in ipairs(item.effect_ids or {}) do
                    local amount = tonumber((item.effect_values or {})[index])
                    if type(field) == "string" and field ~= "" and finite(amount) then
                        local value = (result[field] or 0) + amount * owned * MULTIPLIER
                        if finite(value) then result[field] = value end
                    end
                end
            end
        end
    end
    add_source(shadow, archive.shadow_counts)
    add_source(cage, archive.cage_counts)
    return result
end
return M
