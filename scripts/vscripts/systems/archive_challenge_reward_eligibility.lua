-- Pure reward eligibility. A failed condition never blocks the summon itself.
local items = require("config/generated/archive_social_items")
local M = {}
local prerequisites = {ex="beast", friend="ex", wife="friend", concubine="friend"}
local names = {beast="瑞兽赐福", ex="前女友", friend="好基友", wife="老婆", concubine="侍妾"}
local function counter(value)
    local number = tonumber(value)
    if not number or number ~= number or number < 0 or number == math.huge
        or number ~= math.floor(number) then return 0 end
    return number
end
function M.total_draws(save, pool)
    if type(save) ~= "table" then return 0 end
    -- Historical collection counts only ever increased on a successful draw.
    -- They are a safe lower bound for old profiles with no explicit cursor.
    local observed = 0
    for _, item in ipairs(items.rows) do
        if item.pool_id == pool then observed = observed + counter((save.social_counts or {})[item.item_id]) end
    end
    return math.max(observed, counter((save.social_draw_counts or {})[pool]))
end
function M.migrate(save, pool)
    save.social_draw_counts = save.social_draw_counts or {}
    save.social_draw_counts[pool] = M.total_draws(save, pool)
    return save.social_draw_counts[pool]
end
function M.pool_requirement(pool)
    return prerequisites[pool], 100
end
function M.check(save, definition)
    if type(save) ~= "table" then return false, "存档尚未就绪", "archive_profile_unavailable" end
    definition = definition or {}
    local pool, threshold = definition.reward_requirement_pool, tonumber(definition.reward_requirement_count)
    if (not pool or pool == "") and definition.reward_kind == "social_ticket" then
        pool, threshold = M.pool_requirement(definition.reward_key)
    end
    if not pool or pool == "" then return true end
    threshold = threshold or 100
    local total = M.total_draws(save, pool)
    if total <= threshold then
        return false, (names[pool] or "前置奖池") .. "累计抽奖次数需大于" .. tostring(threshold)
            .. "（当前" .. tostring(total) .. "次）", "archive_reward_draws_required"
    end
    return true
end
return M
