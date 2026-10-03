-- Deterministic account progression shared by local and HTTP settlements.
-- Balance is spendable; earned points and granted tiers never decrease on exchange.
local levels = require('config/generated/archive_starjoy_levels')
local definitions = require('config/generated/player_gameplay_stats')
local M = {}
local function nonnegative(value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, math.floor(value))
end
function M.score(stats)
    stats = stats or {}
    return math.max(nonnegative(stats.starjoy_points_earned), nonnegative(stats.starjoy_points))
end
function M.level(stats)
    return math.min(24, nonnegative((stats or {}).starjoy_reward_level))
end
function M.reconcile(stats)
    local score, old = M.score(stats), M.level(stats)
    stats.starjoy_points_earned = score
    for _, row in ipairs(levels.rows) do
        if row.enabled and row.level > old and score >= row.required_points then
            assert(#row.effect_ids == #row.effect_values, 'starjoy_effect_array_mismatch')
            for i, field in ipairs(row.effect_ids) do
                local spec = assert(definitions.by_id[field], 'starjoy_unknown_stat:' .. field)
                local value = (tonumber(stats[field]) or tonumber(spec.default_value) or 0) + assert(tonumber(row.effect_values[i]))
                if spec.min_value then value = math.max(value, spec.min_value) end
                if spec.max_value then value = math.min(value, spec.max_value) end
                stats[field] = value
            end
            stats.starjoy_reward_level = row.level
        end
    end
    -- Existing LV17+ accounts may have claimed the tier while Judgment was pending.
    -- Backfill only this newly implemented entitlement, never replay the tier's stats.
    if M.level(stats) >= 17 and (tonumber(stats.hero_execute_health_threshold_pct) or 0) < 15 then
        stats.hero_execute_health_threshold_pct = 15
    end
    return M.level(stats)
end
function M.needs_reconcile(stats)
    local score, level = M.score(stats), M.level(stats)
    if level >= 17 and (tonumber((stats or {}).hero_execute_health_threshold_pct) or 0) < 15 then return true end
    for _, row in ipairs(levels.rows) do
        if row.enabled and row.level > level and score >= row.required_points then return true end
    end
    return false
end
function M.change(stats, old_balance, new_balance, refund)
    local earned = math.max(nonnegative(stats.starjoy_points_earned), nonnegative(old_balance))
    if not refund then earned = earned + math.max(0, new_balance - old_balance) end
    stats.starjoy_points, stats.starjoy_points_earned = new_balance, earned
    M.reconcile(stats)
end
function M.project(profile)
    local stats = profile and profile.save and profile.save.gameplay_stats or {}
    local score, level, rows = M.score(stats), M.level(stats), {}
    for _, row in ipairs(levels.rows) do
        if row.enabled then
            local active = level >= row.level
            rows[#rows + 1] = {
                id = row.tier_id, name = row.display_name, description = row.description,
                count = score, target = row.required_points, level = row.level,
                unlocked = active and 1 or 0, completed = active and 1 or 0,
                unlock_condition = '累计获得星悦积分达到 ' .. row.required_points .. '，自动解锁；不消耗积分',
                pending_effect = row.pending_effect, quality = 'gold',
                icon_type = 'image', icon = 's2r://panorama/images/custom_game/starjoy_v1/starjoy.vtex',
            }
        end
    end
    return rows
end
function M.info(profile)
    local stats = profile and profile.save and profile.save.gameplay_stats or {}
    return { earned = M.score(stats), balance = nonnegative(stats.starjoy_points), level = M.level(stats) }
end
return M
