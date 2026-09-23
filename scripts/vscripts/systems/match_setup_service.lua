-- Match-wide settings are chosen before any player's saved bonuses are loaded.
-- Requests reach select_mode only after startup resolves the engine event actor.
local M = {}
local session_id, mode_id, selected_by = "", nil, nil
local mode_options = {
    { mode_id = "pure", display_name = "纯净模式",
        description = "默认属性开局，不继承已有存档加成；本局奖励正常获得并保存。" },
    { mode_id = "standard", display_name = "常规模式",
        description = "继承已有存档与永久加成；本局奖励正常获得并保存。" },
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
function M.is_mode_selected() return mode_id ~= nil end

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
    if requested ~= "pure" and requested ~= "standard" then
        return { ok = false, error = "mode_not_found" }
    end
    if mode_id ~= nil then
        return { ok = requested == mode_id, mode_id = mode_id,
            error = requested ~= mode_id and "mode_locked" or nil }
    end
    mode_id, selected_by = requested, tonumber(id)
    return { ok = true, mode_id = mode_id }
end

function M.snapshot()
    local options = {}
    for _, row in ipairs(mode_options) do
        options[#options + 1] = { mode_id = row.mode_id, display_name = row.display_name,
            description = row.description }
    end
    return { mode_selected = M.is_mode_selected(), mode_id = mode_id or "",
        selector_player_id = M.selector_player_id(), mode_options = options }
end

return M
