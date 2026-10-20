-- Match-wide settings are chosen before any player's saved bonuses are loaded.
-- Requests reach select_mode only after startup resolves the engine event actor.
local M = {}
local session_id, mode_id, selected_by = "", nil, nil
local mode_options = {
    { mode_id = "pure", display_name = "纯净模式",
        description = "默认属性开局，不继承已有存档加成；本局奖励正常获得并保存。" },
    { mode_id = "standard", display_name = "常规模式",
        description = "继承已有存档与永久加成；本局奖励正常获得并保存。" },
    { mode_id = "fishing", display_name = "摸鱼模式",
        description = "不选择难度、不生成波次，自动挂机；沿用常规档案并正常保存奖励。" },
    { mode_id = "rich", display_name = "丰饶模式",
        description = "沿用常规档案，丰饶模式难度通关进度独立保存。" },
    { mode_id = "cold", display_name = "极寒模式",
        description = "沿用常规档案与解锁进度，使用独立的极寒怪物属性。" },
    { mode_id = "scourge", display_name = "天灾模式",
        description = "沿用常规档案与解锁进度，使用独立的天灾怪物属性。" },
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
end

function M.get_session_id() return session_id end
function M.get_mode() return mode_id end
function M.get_profile_mode()
    return (mode_id == "fishing" or mode_id == "rich" or mode_id == "cold" or mode_id == "scourge")
        and "standard" or mode_id
end
function M.is_fishing_mode() return mode_id == "fishing" end
function M.is_rich_mode() return mode_id == "rich" end
function M.is_mode_selected() return mode_id ~= nil end

local function rich_permission(id)
    -- Entry authentication precedes profile loading. Never accept a client
    -- unlock flag, a combat projection, or a previous account/session's save.
    local ok, profiles = pcall(require, "systems/player_profile_service")
    if not ok or type(profiles.get_authenticated_progression) ~= "function" then return false, true end
    local valid, progress = pcall(profiles.get_authenticated_progression, id)
    if not valid or type(progress) ~= "table" or progress.loaded ~= true then return false, true end
    if type(progress.rich_clear_counts) ~= "table" then
        return false, true, "丰饶模式服务尚未就绪"
    end
    local counts = progress.standard_clear_counts
    if counts == nil then counts = progress.clear_counts end -- Existing authoritative historical progression.
    local count = type(counts) == "table" and counts.n10 or nil
    return type(count) == "number" and count > 0 and count < math.huge
        and count == math.floor(count), false
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
    if requested ~= "pure" and requested ~= "standard" and requested ~= "fishing" and requested ~= "rich"
        and requested ~= "cold" and requested ~= "scourge" then
        return { ok = false, error = "mode_not_found" }
    end
    if mode_id ~= nil then
        return { ok = requested == mode_id, mode_id = mode_id,
            error = requested ~= mode_id and "mode_locked" or nil }
    end
    if requested == "rich" then
        local unlocked, pending = rich_permission(tonumber(id))
        if not unlocked then return { ok = false, error = pending and "rich_progression_pending" or "rich_mode_locked" } end
    end
    mode_id, selected_by = requested, tonumber(id)
    return { ok = true, mode_id = mode_id }
end

function M.snapshot()
    local options = {}
    for _, row in ipairs(mode_options) do
        options[#options + 1] = { mode_id = row.mode_id, display_name = row.display_name,
            description = row.description }
        if row.mode_id == "rich" then
            local unlocked, pending, hint = rich_permission(M.selector_player_id())
            options[#options].unlocked = unlocked and 1 or 0
            options[#options].pending = pending and 1 or 0
            options[#options].unlock_hint = hint or "常规模式N10通关后解锁"
        end
    end
    return { mode_selected = M.is_mode_selected(), mode_id = mode_id or "",
        selector_player_id = M.selector_player_id(), mode_options = options }
end

return M
