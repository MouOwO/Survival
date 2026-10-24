local profile = require("config/release_profile")
local M = {}

local function engine_true(callback)
    if type(callback) ~= "function" then return false end
    local ok, result = pcall(callback)
    return ok and result == true
end

function M.is_production()
    return type(profile) ~= "table" or profile.channel ~= "development"
end

local function web_auth_disabled()
    -- Only the trusted server configuration can identify the offline build.
    -- Missing, malformed or failed configuration must never enable grants.
    local ok, config = pcall(require, "config/player_web_auth")
    return ok and type(config) == "table" and rawget(config, "enabled") == false
end

function M.development_allowed()
    -- Fail closed, including production launched through Workshop Tools.
    -- Engine cheats, host privileges and payload fields are not build identity.
    return not M.is_production()
        and engine_true(IsServer) and engine_true(IsInToolsMode)
        and web_auth_disabled()
end

function M.denied_result()
    return { ok = false, error = "release_debug_disabled" }
end

return M
