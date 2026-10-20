-- Match-local mode testing. Never manufacture permanent clears or capabilities.
local M = {}
local enabled, session_id = false, ""

local function allowed()
    if type(IsInToolsMode) == "function" and IsInToolsMode() then return true end
    if GameRules and type(GameRules.IsCheatMode) == "function" then
        local ok, cheats = pcall(GameRules.IsCheatMode, GameRules)
        return ok and cheats == true
    end
    return false
end

function M.reset(session)
    enabled, session_id = false, tostring(session or "")
end

function M.is_enabled()
    local setup = package.loaded["systems/match_setup_service"]
    -- Isolation lasts for the entire match, even if cheats are later disabled.
    return enabled and type(setup) == "table"
        and setup.get_session_id() == session_id
end

function M.enable(player_id)
    if not allowed() then return false, "tools_mode_or_cheats_required" end
    local setup = require("systems/match_setup_service")
    if not setup.is_selector(player_id) then return false, "selection_not_host" end
    if M.is_enabled() then return true end
    if setup.is_mode_selected() then return false, "请在选择模式前输入 0" end
    if session_id == "" or setup.get_session_id() ~= session_id then
        return false, "match_session_mismatch"
    end
    enabled = true
    return true
end

return M
