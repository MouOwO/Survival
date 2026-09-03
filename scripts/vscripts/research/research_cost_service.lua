local M = {}

local function percentage(value)
    return math.max(0, math.min(100, tonumber(value) or 0))
end

local function discounted_amount(amount, discount_pct)
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    local result = amount * (1 - discount_pct / 100)
    -- Resources are integers in the resource system. Round to the nearest
    -- whole unit so a small discount cannot accidentally make a 1-cost item
    -- free; a full 100% discount still correctly yields zero.
    return math.max(0, math.floor(result + 0.5))
end

function M.discount(cost, totals)
    cost = cost or {}
    totals = totals or {}
    local common = percentage(totals.technology_cost_refund_pct)
    local wood_discount = math.min(100,
        common + percentage(totals.technology_wood_cost_refund_pct))
    local gold_discount = math.min(100,
        common + percentage(totals.technology_gold_cost_refund_pct))
    return {
        wood = discounted_amount(cost.wood, wood_discount),
        gold = discounted_amount(cost.gold, gold_discount),
    }
end

function M.for_player(cost, event_bus, events, player_id)
    if not event_bus or type(event_bus.request) ~= "function" then
        return M.discount(cost, nil)
    end
    local result = event_bus.request(
        events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
        { player_id = player_id }
    )
    return M.discount(cost, result and result.totals or nil)
end

return M
