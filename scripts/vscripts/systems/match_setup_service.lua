-- Match-wide settings are chosen before any player's saved bonuses are loaded.
-- Requests reach select_mode only after startup resolves the engine event actor.
local M = {}
local progression_rules = require("config/mode_progression")
local mode_test = require("debug/mode_unlock_test")
local release_modes = require("config/mode_release_config")
local session_id, mode_id, selected_by = "", nil, nil
local mode_options = {
    { mode_id = "standard", display_name = "常规模式",
        description = "继承已有存档与永久加成；本局奖励正常获得并保存。" },
    { mode_id = "rich", display_name = "丰饶模式",
        description = "沿用常规档案，丰饶模式难度通关进度独立保存。" },
    { mode_id = "cold", display_name = "极寒模式",
        description = "沿用常规档案，极寒模式难度通关进度独立保存。" },
    { mode_id = "scourge", display_name = "天灾模式",
        description = "沿用常规档案，天灾模式难度通关进度独立保存。" },
    { mode_id = "ruins", display_name = "归墟模式",
        description = "沿用常规档案，归墟模式难度通关进度独立保存。" },
    { mode_id = "celestial", display_name = "天域模式",
        description = "沿用常规档案，天域模式难度通关进度独立保存。" },
    { mode_id = "fishing", display_name = "摸鱼模式",
        description = "不选择难度、不生成波次，自动挂机；沿用常规档案并正常保存奖励。" },
    { mode_id = "pure", display_name = "纯净模式",
        description = "默认属性开局，不继承已有存档加成；本局奖励正常获得并保存。" },
}

local function resource(method, id)
    if not PlayerResource or type(PlayerResource[method]) ~= "function" then return nil end
    local ok, value = pcall(PlayerResource[method], PlayerResource, id)
    return ok and value or nil
end

local function available(id)
    if type(id) ~= "number" or id < 0 or id ~= math.floor(id) then return false end
    if not resource("IsValidPlayerID", id) or resource("IsFakeClient", id) then return false end
    if resource("GetTeam", id) == (DOTA_TEAM_SPECTATOR or 1) then return false end
    if not resource("GetPlayer", id) then return false end
    local connection = resource("GetConnectionState", id)
    return connection == nil or connection == (DOTA_CONNECTION_STATE_CONNECTED or 2)
end

function M.init(id)
    assert(type(id) == "string" and id ~= "", "match session required")
    session_id, mode_id, selected_by = id, nil, nil
    mode_test.reset(id)
end

function M.get_session_id() return session_id end
function M.get_mode() return mode_id end
function M.get_profile_mode()
    return (mode_id == "fishing" or progression_rules.parent_mode(mode_id) ~= nil)
        and "standard" or mode_id
end
function M.is_fishing_mode() return mode_id == "fishing" end
function M.is_rich_mode() return mode_id == "rich" end
function M.is_mode_selected() return mode_id ~= nil end

local function mode_permission(id, requested)
    -- Entry authentication precedes profile loading. Never accept a client
    -- unlock flag, a combat projection, or a previous account/session's save.
    local ok, profiles = pcall(require, "systems/player_profile_service")
    if not ok or type(profiles.get_authenticated_progression) ~= "function" then return false, true end
    local valid, progress = pcall(profiles.get_authenticated_progression, id)
    if not valid or type(progress) ~= "table" or progress.loaded ~= true then return false, true end
    if mode_test.is_enabled() then return true, false end
    if type(progress[progression_rules.clear_field(requested)]) ~= "table" then
        local name = ({rich="丰饶模式", cold="极寒模式", scourge="天灾模式",ruins="归墟模式",celestial="天域模式"})[requested]
        return false, true, name .. "服务尚未就绪"
    end
    return progression_rules.entry_unlocked(requested, progress), false
end

local mode_daily_keys = {pure="clear", standard="clear", rich="mode_rich",
    cold="mode_cold", scourge="mode_scourge"}
local function daily_capped(quota)
    return quota and (quota.capped == true or tonumber(quota.capped) == 1
        or tonumber(quota.remaining) == 0) or false
end
local function mode_daily_quota(id, requested)
    if mode_test.is_enabled() then return nil end
    local key = mode_daily_keys[requested]
    if not key then return nil end
    local ok, profiles = pcall(require, "systems/player_profile_service")
    if not ok or type(profiles.get_authenticated_daily_limits) ~= "function" then return nil end
    if type(profiles.is_authenticating) == "function" and profiles.is_authenticating(id) then return nil, true end
    local valid, summary = pcall(profiles.get_authenticated_daily_limits, id)
    if not valid or type(summary) ~= "table" or type(summary.by_key) ~= "table" then return nil end
    local date = tostring(require("systems/archive_calendar").day())
    if tostring(summary.day_key) ~= date then
        if type(profiles.get_daily_limit) == "function" then
            local global = profiles.get_daily_limit(id, "clear")
            local quota = key == "clear" and global or profiles.get_daily_limit(id, key)
            if global or quota then return daily_capped(global) and global or quota end
        end
        local profile = type(profiles.get_account_profile) == "function" and profiles.get_account_profile(id)
        if profile then
            summary = require("systems/archive_daily_limits").snapshot(profile, date)
        else
            -- A menu can remain open over midnight. Refresh on the server;
            -- no local UI date/reset may grant permission to enter a mode.
            if type(profiles.authenticate_player) == "function" then
                profiles.authenticate_player(id, "daily_limits_rollover")
            end
            return nil, true
        end
    end
    -- Every combat mode shares the global clear quota as well as any
    -- independent mode quota. Either exhausted counter closes this entry.
    if daily_capped(summary.by_key.clear) then return summary.by_key.clear end
    return summary.by_key[key]
end

function M.selector_player_id()
    local first = nil
    for id = 0, (DOTA_MAX_TEAM_PLAYERS or 24) - 1 do
        if available(id) then
            first = first or id
            if GameRules and type(GameRules.PlayerHasCustomGameHostPrivileges) == "function" then
                local ok, host = pcall(GameRules.PlayerHasCustomGameHostPrivileges,
                    GameRules, resource("GetPlayer", id))
                if ok and host == true then return id end
            end
        end
    end
    if selected_by ~= nil and available(selected_by) then return selected_by end
    -- Local Workshop launches need not have a lobby host. Never let the first
    -- arriving network client claim host privileges in a normal online lobby.
    if type(IsInToolsMode) == "function" and IsInToolsMode() then return first or -1 end
    return -1
end

function M.is_selector(id)
    id = tonumber(id)
    return id ~= nil and available(id) and id == M.selector_player_id()
end

function M.select_mode(id, requested, request_session)
    if session_id == "" or request_session ~= session_id then
        return { ok = false, error = "match_session_mismatch" }
    end
    if not M.is_selector(id) then return { ok = false, error = "selection_not_host" } end
    if not release_modes.is_known(requested) then
        return { ok = false, error = "mode_not_found" }
    end
    -- Release gating applies before debug unlocks and before accepting retries.
    if not release_modes.is_released(requested) then
        return { ok = false, error = "mode_not_released" }
    end
    if mode_id ~= nil then
        return { ok = requested == mode_id, mode_id = mode_id,
            error = requested ~= mode_id and "mode_locked" or nil }
    end
    if progression_rules.parent_mode(requested) then
        local unlocked, pending, hint = mode_permission(tonumber(id), requested)
        if not unlocked then return { ok = false, error = pending and "mode_profile_pending" or "mode_not_unlocked",
            unlock_hint = hint or progression_rules.entry_hint(requested) } end
    end
    local quota, daily_pending = mode_daily_quota(tonumber(id), requested)
    if daily_pending then return {ok=false, error="mode_daily_limits_pending"} end
    if daily_capped(quota) then
        return {ok=false, error="mode_daily_limit_reached"}
    end
    mode_id, selected_by = requested, tonumber(id)
    return { ok = true, mode_id = mode_id }
end

function M.snapshot()
    local options = {}
    for _, row in ipairs(mode_options) do
        if release_modes.is_released(row.mode_id) then
            options[#options + 1] = { mode_id = row.mode_id, display_name = row.display_name,
                description = row.description, unlocked = 1, pending = 0, unlock_hint = "" }
            if progression_rules.parent_mode(row.mode_id) then
                local unlocked, pending, hint = mode_permission(M.selector_player_id(), row.mode_id)
                options[#options].unlocked = unlocked and 1 or 0
                options[#options].pending = pending and 1 or 0
                options[#options].unlock_hint = hint or progression_rules.entry_hint(row.mode_id)
            end
            local quota, daily_pending = mode_daily_quota(M.selector_player_id(), row.mode_id)
            if daily_pending then
                options[#options].daily_pending = 1
                options[#options].daily_hint = "正在更新今日奖励额度……"
            end
            if quota then
                local option = options[#options]
                option.daily_key, option.daily_earned, option.daily_limit = quota.key, quota.earned, quota.limit
                option.daily_remaining, option.daily_capped = quota.remaining, daily_capped(quota) and 1 or 0
                option.daily_hint = "今日奖励已达上限"
            end
        end
    end
    return { mode_selected = M.is_mode_selected(), mode_id = mode_id or "",
        read_only_acceptance = mode_test.is_enabled(),
        selector_player_id = M.selector_player_id(), mode_options = options }
end

return M
