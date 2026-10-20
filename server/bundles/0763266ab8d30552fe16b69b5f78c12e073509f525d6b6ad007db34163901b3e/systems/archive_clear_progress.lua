-- Mode identity is supplied by the authenticated match session, never by UI.
-- Historical mixed counters remain readable but are not migrated into modes.
local achievements = require("config/generated/archive_achievements")
local M = {}
local names = { pure = "纯净模式", standard = "常规模式", rich = "丰饶模式",
    cold = "极寒模式", scourge = "天灾模式" }

local function integer(value)
    return type(value) == "number" and value == value and value < math.huge
        and value >= 0 and value == math.floor(value)
end

local function count(value) return integer(value) and value or 0 end
local function mode_of(row)
    if row.mode_id == nil or row.mode_id == "" then return "standard" end
    return row.mode_id
end
local function difficulty_number(value)
    return type(value) == "string" and tonumber(value:match("^[nN]([1-9]%d*)$")) or nil
end
local function progress(archive, mode, difficulty)
    local maps = type(archive.mode_clear_counts) == "table" and archive.mode_clear_counts or {}
    local values = type(maps[mode]) == "table" and maps[mode] or {}
    return count(values[difficulty])
end
local function legacy_progress(archive, mode, difficulty)
    if mode == "pure" then return 0 end
    local values = archive[mode .. "_clear_counts"]
    if mode == "standard" and values == nil then values = archive.clear_counts end
    return type(values) == "table" and count(values[difficulty]) or 0
end
local function receipt(mode, item) return mode .. ":" .. tostring(item.achievement_id) end
local function legacy_completed(archive, mode, item)
    if mode ~= "standard" then return false end
    local completed = type(archive.completed) == "table" and archive.completed or {}
    -- Older standard IDs were stable difficulty/count pairs. Preserve them
    -- even if new mode-aware CSV rows use a more explicit identifier.
    local old_id = "clear_" .. tostring(item.difficulty_id) .. "_" .. tostring(item.required_count)
    return completed[item.achievement_id] == true or completed[old_id] == true
end
local function reward_limit(item)
    if item.reward_mode ~= "per_clear" then return 1 end
    local limit = item.reward_limit or 1
    return integer(limit) and limit > 0 and limit or 1
end
local function earned_count(item, total)
    if item.reward_mode == "counter" then return 0 end
    if item.reward_mode == "per_clear" then
        return math.min(reward_limit(item), math.max(0, total - count(item.reward_start)))
    end
    return total >= item.required_count and 1 or 0
end
local function reward_count(archive, mode, item)
    local rewards = type(archive.mode_clear_rewards) == "table" and archive.mode_clear_rewards or {}
    local result = count(rewards[receipt(mode, item)])
    local completed = type(archive.completed) == "table" and archive.completed or {}
    if completed[receipt(mode, item)] == true or legacy_completed(archive, mode, item) then
        result = math.max(1, result)
    end
    return result
end

function M.is_mode(mode) return names[mode] ~= nil end
function M.mode_name(mode) return names[mode] end

-- Follow the same availability list as team difficulty selection. Future CSV
-- rewards can remain configured without appearing before their waves exist.
function M.max_available(mode)
    if not M.is_mode(mode) then return 0 end
    local config = require("config/difficulty_config")
    local balance = (mode == "cold" or mode == "scourge") and require("config/recorded_mode_balance") or nil
    local maximum = 0
    for _, option in ipairs(config.client_options()) do
        if not balance or balance.has_difficulty(mode, option.difficulty_id) then
            maximum = math.max(maximum, difficulty_number(option.difficulty_id) or 0)
        end
    end
    return maximum
end

local function available(mode, options)
    local maximum = options and options.max_available_difficulty
    if type(maximum) == "table" then maximum = maximum[mode] end
    if maximum == nil then return M.max_available(mode) end
    return integer(maximum) and maximum or 0
end

local function visible(mode, options)
    -- Every integrated mode has an N1-N10 archive. A missing wave profile
    -- cannot fabricate a win; record() still checks actual combat support.
    -- Higher rewards appear only when their real difficulty data is added.
    if options and options.max_available_difficulty ~= nil then return available(mode, options) end
    return math.max(10, M.max_available(mode))
end

-- The outer settlement owns receipt deduplication, quotas, compatibility
-- counters and double-clear entitlement adjustment. This function only records
-- the resulting trusted count and grants this mode's configured milestones.
function M.record(archive, command, stats, apply_effects, options)
    local mode, difficulty = command.mode_id, command.difficulty_id
    if type(difficulty) == "string" then difficulty = string.lower(difficulty) end
    local number = difficulty_number(difficulty)
    if not M.is_mode(mode) or not number or number > 20
        or not integer(command.count) or command.count < 1 then
        return false, "archive_mode_clear_invalid"
    end
    if number > available(mode, options) then return false, "archive_mode_difficulty_unavailable" end
    archive.mode_clear_counts = type(archive.mode_clear_counts) == "table" and archive.mode_clear_counts or {}
    local values = archive.mode_clear_counts[mode]
    if type(values) ~= "table" then values = {}; archive.mode_clear_counts[mode] = values end
    values[difficulty] = count(values[difficulty]) + command.count
    archive.completed = archive.completed or {}
    archive.mode_clear_rewards = archive.mode_clear_rewards or {}
    for _, item in ipairs(achievements.rows) do
        if item.enabled and mode_of(item) == mode and item.difficulty_id == difficulty
            and integer(item.required_count) and item.required_count > 0 then
            local granted = reward_count(archive, mode, item)
            local earned = earned_count(item, values[difficulty])
            for _ = granted + 1, earned do apply_effects(stats, item) end
            if earned > granted then
                archive.mode_clear_rewards[receipt(mode, item)] = earned
                archive.completed[receipt(mode, item)] = true
            end
        end
    end
    return true
end

function M.rows(archive, options)
    archive, options = archive or {}, options or {}
    local result = {}
    for _, item in ipairs(achievements.rows) do
        local mode, number = mode_of(item), difficulty_number(item.difficulty_id)
        if item.enabled and M.is_mode(mode) and (not options.mode_id or options.mode_id == mode)
            and number and number <= visible(mode, options) then
            local current = progress(archive, mode, item.difficulty_id)
            -- Keep the existing standard archive visible without claiming its
            -- mixed historical values belong to pure or any advanced mode.
            current = math.max(current, legacy_progress(archive, mode, item.difficulty_id))
            local owned, limit = reward_count(archive, mode, item), reward_limit(item)
            result[#result + 1] = { id = item.achievement_id, mode_id = mode, mode_name = names[mode],
                difficulty_id = item.difficulty_id, name = item.display_name,
                description = item.description, icon_style = item.icon_style,
                rune = string.upper(item.difficulty_id), quality = "gold",
                count = current, target = item.required_count,
                completed = (item.reward_mode == "counter" and current >= item.required_count or owned >= limit) and 1 or 0,
                reward_count = owned, reward_limit = limit }
        end
    end
    return result
end

return M
