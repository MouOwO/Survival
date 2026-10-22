-- Match-local mode testing. Never manufacture permanent clears or capabilities.
local M = {}
local release_policy = require("core/release_policy")
local acceptance = require("config/mode_release_config")
local enabled, session_id = false, ""

local function allowed()
    return release_policy.development_allowed()
end

function M.reset(session)
    session_id = tostring(session or "")
    -- Explicit server configuration can open a read-only acceptance arena in
    -- any release channel. Latch isolation until the next match: disabling the
    -- flag halfway through a test must never turn its rewards into real saves.
    enabled = session_id ~= "" and acceptance.all_difficulties_unlocked == true
end

function M.is_enabled()
    local setup = package.loaded["systems/match_setup_service"]
    -- Isolation lasts for the entire match, even if cheats are later disabled.
    return enabled and type(setup) == "table"
        and setup.get_session_id() == session_id
end

function M.enable(player_id)
    if not allowed() then return false, "release_debug_disabled" end
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
