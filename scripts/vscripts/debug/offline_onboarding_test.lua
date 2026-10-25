-- A server launch choice for a disposable onboarding preview. This never
-- authorizes cloud access and is deliberately separate from ordinary offline QA.
local M = {}
local configured, selected = false, false

local function trusted()
    local ok, policy = pcall(require, "core/release_policy")
    if not ok or type(policy) ~= "table" or type(policy.development_allowed) ~= "function"
        or policy.development_allowed() ~= true then return false end
    -- Read configuration directly: player_web_auth itself imports access policy.
    local loaded, config = pcall(require, "config/player_web_auth")
    return loaded and type(config) == "table" and rawget(config, "enabled") == false
end

local function flag(name)
    if not Convars or type(Convars.GetStr) ~= "function" then return false end
    local ok, value = pcall(Convars.GetStr, Convars, name)
    return ok and value == "1"
end

function M.configure()
    if not configured then
        configured = true
        if Convars and type(Convars.RegisterConvar) == "function" then
            -- Source 2 may expose command-line values only after registration.
            -- Access policy runs before the ordinary offline provider does.
            pcall(Convars.RegisterConvar, Convars, "survival_offline_logic_test", "0",
                "Opt-in development Workshop Tools offline logic arena", 0)
            pcall(Convars.RegisterConvar, Convars, "survival_offline_onboarding_test", "0",
                "Opt-in memory-only Workshop Tools onboarding preview", 0)
        end
        selected = trusted() and flag("survival_offline_logic_test")
            and flag("survival_offline_onboarding_test")
    end
    return selected and trusted() or false
end

function M.requested()
    return M.configure()
end

function M.is_enabled()
    if not M.requested() then return false end
    -- Never require the provider while it is configuring this helper.
    local offline = package.loaded["debug/offline_logic_test"]
    return type(offline) == "table" and type(offline.is_enabled) == "function"
        and offline.is_enabled() == true or false
end

local function resource(name, player_id)
    if not PlayerResource or type(PlayerResource[name]) ~= "function" then return nil end
    local ok, value = pcall(PlayerResource[name], PlayerResource, player_id)
    if ok then return value end
    return nil
end

function M.is_human(player_id)
    if type(player_id) ~= "number" or player_id ~= player_id or player_id < 0
        or player_id > 255 or player_id ~= math.floor(player_id) then return false end
    if resource("IsValidPlayerID", player_id) ~= true
        or resource("IsFakeClient", player_id) ~= false then return false end
    local player = resource("GetPlayer", player_id)
    if not player or type(player.GetPlayerID) ~= "function" then return false end
    if type(player.IsNull) == "function" then
        local ok, null = pcall(player.IsNull, player)
        if not ok or null then return false end
    end
    local ok, actual = pcall(player.GetPlayerID, player)
    return ok and actual == player_id
end

function M.account_id(player_id)
    if not M.is_enabled() or not M.is_human(player_id) then return nil end
    local identity = resource("GetSteamAccountID", player_id)
    if type(identity) ~= "number" or identity ~= identity or identity < 0
        or identity > 4294967295 or identity ~= math.floor(identity) then return nil end
    if identity > 0 then return string.format("%.0f", identity) end
    -- A zero Steam identity belongs only to this match's in-memory provider.
    -- A later real identity produces a different key, closing account gates.
    return "offline-player-" .. tostring(player_id)
end

return M
