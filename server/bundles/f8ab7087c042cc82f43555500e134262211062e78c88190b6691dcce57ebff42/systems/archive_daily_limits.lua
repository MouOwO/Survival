-- Shared account quotas. The reducer changes these counters in the same
-- revision as rewards; spending a reward never releases acquisition quota.
local definitions = require("config/generated/archive_daily_limits")
local calendar = require("systems/archive_calendar")
local M = {}
local function integer(value)
    local number = tonumber(value)
    assert(number and number == number and number >= 0 and number < math.huge
        and number == math.floor(number), "archive_daily_counter_invalid")
    return number
end
local function day(value)
    local result = tostring(value == nil and calendar.day() or value)
    assert(#result > 0 and #result <= 128, "archive_daily_day_invalid")
    return result
end
function M.definition(key)
    return assert(definitions.by_id[key], "archive_daily_limit_unknown:" .. tostring(key))
end
function M.limit(key, pass)
    local definition = M.definition(key)
    return integer(pass == true and definition.pass_daily_limit or definition.daily_limit)
end
function M.earned(archive, key, day_key)
    archive = archive or {}
    local definition, date = M.definition(key), day(day_key)
    local bucket = type(archive.daily) == "table" and archive.daily[date] or nil
    local count = type(bucket) == "table" and bucket[definition.storage_key] or nil
    count = count == nil and 0 or integer(count)
    if key == "faith" then
        local previous = archive.buildings and archive.buildings.earned_by_day
        count = math.max(count, previous and previous[date] and integer(previous[date]) or 0)
    end
    return count
end
function M.remaining(archive, key, day_key, pass)
    return math.max(0, M.limit(key, pass) - M.earned(archive, key, day_key))
end
function M.grant(archive, key, amount, day_key, pass)
    assert(type(archive) == "table", "archive_daily_state_invalid")
    local requested, date = integer(amount), day(day_key)
    local accepted = math.min(requested, M.remaining(archive, key, date, pass))
    if accepted > 0 then
        local earned = M.earned(archive, key, date)
        archive.daily = archive.daily or {}
        archive.daily[date] = archive.daily[date] or {}
        archive.daily[date][M.definition(key).storage_key] = earned + accepted
    end
    return accepted
end
function M.challenge_key(definition)
    if not definition then return nil end
    if definition.reward_kind == "fragment" then return definition.reward_key end
    if definition.reward_kind == "shadow" then return "shadow" end
    if definition.reward_kind == "cage" then return "cage" end
    if definition.reward_kind == "social_ticket" then
        return definition.reward_key == "concubine" and "salary" or "social_" .. tostring(definition.reward_key)
    end
    if definition.reward_kind == "challenge_points" then return definition.reward_key end
    return nil
end
function M.snapshot(profile, day_key)
    profile = profile or {}
    local save = profile.save or {}
    local archive = save.archive or (profile.daily and profile) or {}
    local date = day(day_key)
    local pass = calendar.has_pass(profile)
    local result = {day_key=date, rows={}, by_key={}}
    local external = save.daily_limits
    for _, definition in ipairs(definitions.rows) do
        local key = definition.limit_id
        local earned = M.earned(archive, key, date)
        -- Fishing grants do not pass through the archive reducer. Only the
        -- database profile projection is authoritative for their daily count.
        if key == "fishing" and type(external) == "table" and tostring(external.day_key) == date then
            local row = external.by_key and external.by_key.fishing
            if type(row) == "table" and row.earned ~= nil then earned = integer(row.earned) end
        end
        local limit = M.limit(key, pass)
        local row = {key=key, name=definition.display_name, earned=earned, limit=limit,
            remaining=math.max(0, limit-earned), capped=earned >= limit and 1 or 0,
            implemented=definition.implemented == true and 1 or 0,
            sort_order=definition.sort_order or 0}
        result.rows[#result.rows+1], result.by_key[key] = row, row
    end
    table.sort(result.rows, function(a,b) return a.sort_order < b.sort_order end)
    return result
end
return M
