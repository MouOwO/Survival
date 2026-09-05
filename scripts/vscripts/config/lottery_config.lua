-- Server-authoritative lottery projection.
-- Source CSV lives in data/csv/抽奖系统. Never send weights or raw pity
-- counters to Panorama; the client receives only display metadata and the
-- remaining advertised guarantee count.
local currency_rows = require("config/generated/lottery_currency_definitions")
local pool_rows = require("config/generated/lottery_pool_definitions")
local weight_rows = require("config/generated/lottery_quality_weights")
local pity_rows = require("config/generated/lottery_pity_rules")
local item_rows = require("config/generated/lottery_item_definitions")
local membership_rows = require("config/generated/lottery_pool_items")
local gameplay_stat_rows = require("config/generated/player_gameplay_stats")

local M = {
    version = 5,
    default_pool_id = "map",
    starjoy_stat_id = "starjoy_points",
    quality_order = { "n", "r", "sr", "ssr", "ur" },
    -- Local map-lottery bootstrap retained for the current test phase. Paid
    -- special tickets are deliberately absent and must come from a verified
    -- backend grant (or the local mock profile during development).
    test_initial_tickets = { lottery_ticket = 1000 },
    currencies = {},
    pools = {},
    pool_order = {},
    items = {},
    by_id = {},
}

local quality_rank = {}
for index, quality in ipairs(M.quality_order) do quality_rank[quality] = index end
M.quality_rank = quality_rank

local function parse_effect_arrays(item_id, effect_ids, effect_values)
    effect_ids = type(effect_ids) == "table" and effect_ids or {}
    effect_values = type(effect_values) == "table" and effect_values or {}
    assert(#effect_ids == #effect_values,
        "lottery effect array length mismatch: " .. tostring(item_id))
    local totals = {}
    local effects = {}
    for index, raw_field_id in ipairs(effect_ids) do
        local field_id = tostring(raw_field_id or "")
        local raw_value = effect_values[index]
        local row = gameplay_stat_rows.by_id[field_id]
        assert(row and row.enabled ~= false,
            "lottery unknown gameplay stat: " .. tostring(item_id)
                .. ":" .. tostring(field_id))
        local value = tonumber(raw_value)
        assert(value and value == value and value ~= math.huge
                and value ~= -math.huge,
            "lottery invalid effect value: " .. tostring(item_id)
                .. ":" .. tostring(raw_value))
        assert(value ~= 0, "lottery zero gameplay stat delta: "
            .. tostring(item_id) .. ":" .. tostring(field_id))
        totals[field_id] = (tonumber(totals[field_id]) or 0) + value
        effects[#effects + 1] = { field_id = field_id, value = value }
    end
    return totals, effects
end

for _, row in ipairs(currency_rows.rows or {}) do
    if row.enabled ~= false then M.currencies[row.currency_id] = row end
end

for _, row in ipairs(item_rows.rows or {}) do
    if row.enabled ~= false then
        assert(quality_rank[row.quality], "lottery invalid quality: " .. tostring(row.quality))
        local effect_values, effects = parse_effect_arrays(row.item_id,
            row.effect_ids, row.effect_values)
        local item = {
            id = row.item_id,
            name = row.display_name,
            item_type = row.item_type,
            duration_type = row.duration_type,
            duration_text = row.duration_text,
            description = row.description,
            quality = row.quality,
            icon_type = row.icon_type,
            icon = row.icon,
            effect_values = effect_values,
            effects = effects,
            effect_status = tostring(row.effect_status or "implemented"),
            source_row = tonumber(row.source_row),
            duplicate_points = math.max(0, math.floor(tonumber(row.duplicate_points) or 0)),
            exchange_points = math.max(0, math.floor(tonumber(row.exchange_points) or 0)),
            exchange_enabled = row.exchange_enabled ~= false,
        }
        assert(item.id ~= "" and M.by_id[item.id] == nil,
            "lottery duplicate or empty item id: " .. tostring(item.id))
        M.items[#M.items + 1] = item
        M.by_id[item.id] = item
    end
end

for _, row in ipairs(pool_rows.rows or {}) do
    if row.enabled ~= false then
        local pool = {
            id = row.pool_id,
            display_name = row.display_name,
            description = row.description,
            ticket_content_id = row.ticket_content_id,
            single_cost = math.max(1, math.floor(tonumber(row.single_cost) or 1)),
            ten_cost = math.max(1, math.floor(tonumber(row.ten_cost) or 10)),
            pool_group = row.pool_group,
            ui_order = tonumber(row.ui_order) or 999,
            quality_weights = {},
            pity_rules = {},
            items = {},
            by_id = {},
            by_quality = {},
        }
        assert(pool.id ~= "" and M.pools[pool.id] == nil,
            "lottery duplicate or empty pool id: " .. tostring(pool.id))
        assert(M.currencies[pool.ticket_content_id],
            "lottery pool currency missing: " .. tostring(pool.ticket_content_id))
        M.pools[pool.id] = pool
        M.pool_order[#M.pool_order + 1] = pool
    end
end

table.sort(M.pool_order, function(left, right)
    if left.ui_order == right.ui_order then return left.id < right.id end
    return left.ui_order < right.ui_order
end)

for _, row in ipairs(weight_rows.rows or {}) do
    if row.enabled ~= false then
        local pool = assert(M.pools[row.pool_id],
            "lottery weight pool missing: " .. tostring(row.pool_id))
        assert(quality_rank[row.quality],
            "lottery weight quality invalid: " .. tostring(row.quality))
        pool.quality_weights[row.quality] = math.max(0, tonumber(row.weight) or 0)
    end
end

for _, row in ipairs(pity_rows.rows or {}) do
    if row.enabled ~= false then
        local pool = assert(M.pools[row.pool_id],
            "lottery pity pool missing: " .. tostring(row.pool_id))
        assert(quality_rank[row.target_quality],
            "lottery pity quality invalid: " .. tostring(row.target_quality))
        pool.pity_rules[#pool.pity_rules + 1] = {
            id = row.rule_id,
            target_quality = row.target_quality,
            threshold = math.max(1, math.floor(tonumber(row.threshold) or 1)),
            trigger_mode = tostring(row.trigger_mode or "batch_only"),
            priority = tonumber(row.priority) or 0,
        }
    end
end

local function add_member(pool, source, item_weight)
    local member = {
        id = source.id,
        name = source.name,
        item_type = source.item_type,
        duration_type = source.duration_type,
        duration_text = source.duration_text,
        description = source.description,
        quality = source.quality,
        icon_type = source.icon_type,
        icon = source.icon,
        effect_values = source.effect_values,
        effects = source.effects,
        effect_status = source.effect_status,
        source_row = source.source_row,
        duplicate_points = source.duplicate_points,
        exchange_points = source.exchange_points,
        exchange_enabled = source.exchange_enabled,
        item_weight = math.max(0, tonumber(item_weight) or 0),
    }
    assert(pool.by_id[member.id] == nil,
        "lottery duplicate pool item: " .. pool.id .. ":" .. member.id)
    pool.items[#pool.items + 1] = member
    pool.by_id[member.id] = member
    pool.by_quality[member.quality] = pool.by_quality[member.quality] or {}
    table.insert(pool.by_quality[member.quality], member)
end

for _, row in ipairs(membership_rows.rows or {}) do
    if row.enabled ~= false then
        local pool = assert(M.pools[row.pool_id],
            "lottery membership pool missing: " .. tostring(row.pool_id))
        if row.item_id == "*" then
            for _, source in ipairs(M.items) do
                add_member(pool, source, row.item_weight)
            end
        else
            local source = assert(M.by_id[row.item_id],
                "lottery membership item missing: " .. tostring(row.item_id))
            add_member(pool, source, row.item_weight)
        end
    end
end

for _, pool in ipairs(M.pool_order) do
    local total = 0
    for _, quality in ipairs(M.quality_order) do
        local weight = tonumber(pool.quality_weights[quality]) or 0
        total = total + weight
        if weight > 0 then
            assert(#(pool.by_quality[quality] or {}) > 0,
                "lottery pool has weighted empty quality: " .. pool.id .. ":" .. quality)
        end
    end
    assert(total == 10000,
        "lottery pool quality weights must total 10000: " .. pool.id .. "=" .. tostring(total))
    table.sort(pool.pity_rules, function(left, right)
        if left.priority == right.priority then return left.id < right.id end
        return left.priority < right.priority
    end)
end

return M
