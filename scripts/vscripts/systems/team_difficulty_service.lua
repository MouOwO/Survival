-- One server-owned permission calculation for the loading page and wave start.
-- The startup roster remains authoritative even if a member disconnects or the
-- lobby host changes. No client counters participate in these permissions.
local config = require("config/difficulty_config")
local progression_rules = require("config/mode_progression")
local mode_test = require("debug/mode_unlock_test")
local M = {}

function M.snapshot(player_ids, mode)
    local profiles = require("systems/player_profile_service")
    local ids, seen, progression = {}, {}, {}
    local ready = true
    for _, id in ipairs(player_ids or {}) do
        if type(id) == "number" and id >= 0 and id <= 255 and id == math.floor(id) and not seen[id] then
            ids[#ids + 1], seen[id] = id, true
            local ok, value = pcall(profiles.get_progression, id, mode)
            progression[id] = ok and value or nil
            if type(progression[id]) ~= "table" or progression[id].loaded ~= true then ready = false end
            if not mode_test.is_enabled() and progression_rules.parent_mode(mode)
                and not progression_rules.counts(mode, progression[id]) then ready = false end
        end
    end
    table.sort(ids)
    ready = ready and #ids > 0
    local options, maximum, lowest, limits = config.client_options(nil, mode), "", nil, {}
    for _, id in ipairs(ids) do
        local highest = 0
        for _, option in ipairs(options) do
            if config.is_unlocked(option.difficulty_id, progression[id], mode) then
                highest = math.max(highest, tonumber(option.difficulty_id:match("^N(%d+)$")) or 0)
            end
        end
        if lowest == nil or highest < lowest then lowest, limits = highest, { id }
        elseif highest == lowest then limits[#limits + 1] = id end
    end
    for _, option in ipairs(options) do
        local unlocked, entry_blocked = ready, false
        for _, id in ipairs(ids) do
            if not config.is_unlocked(option.difficulty_id, progression[id], mode) then unlocked = false end
            if progression_rules.parent_mode(mode) and not progression_rules.entry_unlocked(mode, progression[id]) then
                entry_blocked = true
            end
        end
        option.unlocked = unlocked and 1 or 0
        if unlocked then
            option.unlock_hint, maximum = "", option.difficulty_id
        elseif not ready then
            option.unlock_hint = "等待队伍玩家进度加载"
        elseif progression_rules.parent_mode(mode) then
            option.unlock_hint = "队伍所有玩家：" .. (entry_blocked and progression_rules.entry_hint(mode)
                or progression_rules.difficulty_hint(mode, option.difficulty_id))
        else
            local number = tonumber(option.difficulty_id:match("^N(%d+)$")) or 1
            option.unlock_hint = "队伍所有玩家通关 N" .. (number - 1) .. " 后解锁"
        end
    end
    return { ready = ready, options = options, max_difficulty_id = maximum,
        limit_player_ids = ready and limits or {} }
end

function M.current(mode)
    local startup = package.loaded["systems/startup_loading_service"]
    local ids = startup and type(startup.selection_player_ids) == "function"
        and startup.selection_player_ids() or require("systems/player_context_service").active_player_ids()
    return M.snapshot(ids, mode)
end

return M
