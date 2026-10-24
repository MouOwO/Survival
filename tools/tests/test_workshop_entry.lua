-- Real entry modules and admission policy; replace engine I/O only.
local SERVER = "scripts/vscripts/systems/workshop_entry.lua"
local CLIENT = "scripts/vscripts/addon_game_mode_client.lua"
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function load(path, environment)
    local chunk = assert(loadfile(path))
    setfenv(chunk, environment)
    return chunk()
end
local function fixture(server, client, map)
    local state = { accounts = {[0] = 101}, kicks = {}, commands = {}, logs = {}, requires = {}, teams = {},
        setup_calls = 0, think_calls = 0, forbidden_calls = 0 }
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.IsServer = function() return server end
    env.IsClient = function() return client end
    env.GetMapName = function() return map end
    state.map = function(value) map = value end
    env.DOTA_MAX_TEAM_PLAYERS = 4
    env.DOTA_TEAM_GOODGUYS, env.DOTA_TEAM_BADGUYS = 2, 3
    env.print = function(text) state.logs[#state.logs + 1] = text end
    local function forbidden() state.forbidden_calls = state.forbidden_calls + 1; error("gameplay/cloud/cheat dependency reached") end
    env.CreateHTTPRequestScriptVM, env.CreateHTTPRequest = forbidden, forbidden
    env.SendToServerConsole, env.Convars, env.CustomNetTables = forbidden, false, false
    env.SendToConsole = function(command) state.commands[#state.commands + 1] = command end
    env.DisconnectClient = function(id, force) state.kicks[#state.kicks + 1] = {id = id, force = force} end
    env.PlayerResource = {
        GetPlayer = function(_, id) return state.accounts[id] ~= nil and {} or nil end,
        IsValidPlayerID = function(_, id) return id >= 0 and id < 4 end,
        GetSteamAccountID = function(_, id) return state.accounts[id] or 0 end,
    }
    local host = {SetContextThink = function(_, name, callback, delay)
        check(name == "SurvivalWorkshopEntryAdmission" and delay == 0.1, "only the admission thinker is scheduled")
        state.think_calls = state.think_calls + 1
        state.tick = callback
    end}
    env.GameRules = {GetGameModeEntity = function() return host end,
        SetCustomGameTeamMaxPlayers = function(_, team, maximum) state.teams[team] = maximum end}
    for _, name in ipairs({"SetHeroSelectionTime", "SetStrategyTime", "SetShowcaseTime", "SetCustomGameSetupTimeout",
                          "EnableCustomGameSetupAutoLaunch"}) do
        env.GameRules[name] = function(_, value) state.setup_calls = state.setup_calls + 1; state[name] = value end
    end
    state.config = {enabled = true, allowed_steamids = {
        "76561197960265829", "76561197960265830", "76561197960265831", "76561197960265832"}}
    env.require = function(name)
        state.requires[#state.requires + 1] = name
        if name == "config/test_access" then return state.config end
        check(name == "core/test_access_policy", "entry cannot import gameplay, profile, HTTP, cheat or generated modules")
        if not state.access then state.access = load("scripts/vscripts/core/test_access_policy.lua", env) end
        return state.access
    end
    return env, state
end

-- The module exposes activation only; the real addon script owns callbacks.
local env, state = fixture(true, false, "ws4_entry")
local entry = load(SERVER, env)
check(#state.requires == 0 and state.setup_calls == 0, "loading the entry module has no engine/module side effects")
check(entry.install == nil and rawget(env, "Activate") == nil and rawget(env, "Precache") == nil,
    "a require module must not attempt to install callbacks into its private scope")
check(entry.activate())
check(state.teams[2] == 1 and state.teams[3] == 0, "only this entry map is a single-player room")
check(state.SetCustomGameSetupTimeout == 1 and state.EnableCustomGameSetupAutoLaunch == true)
check(state.SetHeroSelectionTime == 0 and state.SetStrategyTime == 0 and state.SetShowcaseTime == 0)
check(state.think_calls == 1 and state.forbidden_calls == 0 and #state.commands == 0)
check(entry.activate() and state.think_calls == 1, "repeated activation cannot duplicate the admission loop")
for account = 101, 104 do state.accounts[0] = account; check(state.tick() == 0.1 and #state.kicks == 0) end
state.accounts[0] = 0
check(state.tick() == 0.1 and #state.kicks == 0, "unknown Steam identity remains gated without a stale kick")
state.accounts[0] = 105
check(state.tick() == 0.1 and #state.kicks == 1 and state.kicks[1].id == 0 and state.kicks[1].force == true,
    "the real admission policy disconnects a known outsider")
state.tick()
check(#state.kicks == 1, "the entry preserves the policy's pending-disconnect deduplication")
state.accounts[0] = 101; state.tick()
state.accounts[0] = 105; state.tick()
check(#state.kicks == 2, "entry admission rechecks account changes")
state.map("template_map")
check(state.tick() == nil and entry.activate() == false, "entry logic stops outside its own map")

-- Wrong VMs, missing/throwing APIs and ordinary maps do not bind callbacks.
for _, row in ipairs({{false, true, "ws4_entry"}, {true, true, "ws4_entry"}, {1, false, "ws4_entry"},
                      {true, false, "template_map"}, {true, false, "offline_logic_test"},
                      {true, false, "ws4_entry; exec injected"}}) do
    env, state = fixture(unpack(row))
    local original = function() end
    env.Activate, env.Precache = original, original
    entry = load(SERVER, env)
    check(entry.activate() == false)
    check(env.Activate == original and env.Precache == original and #state.requires == 0 and state.think_calls == 0)
end
for _, unavailable in ipairs({"IsServer", "IsClient", "GetMapName"}) do
    env, state = fixture(true, false, "ws4_entry")
    env[unavailable] = function() error("native unavailable") end
    entry = load(SERVER, env)
    check(entry.activate() == false and #state.requires == 0)
end
for _, kind in ipairs({"disabled", "malformed", "disconnect_missing", "loader_error"}) do
    env, state = fixture(true, false, "ws4_entry")
    if kind == "disabled" then state.config.enabled = false
    elseif kind == "malformed" then state.config.allowed_steamids = {}
    elseif kind == "disconnect_missing" then env.DisconnectClient = false
    else env.require = function() error("private-loader-error") end end
    entry = load(SERVER, env)
    local called, ready = pcall(entry.activate)
    check(called and ready == false and state.setup_calls == 0 and state.think_calls == 0,
        "an invalid entry guard fails closed without entering gameplay or throwing a protection error")
end

-- Execute the real root prefix with a separate require-module scope. This
-- catches callbacks accidentally defined only inside workshop_entry.lua.
env, state = fixture(true, false, "ws4_entry")
local module_env = setmetatable({}, {__index = env})
local module_entry = load(SERVER, module_env)
local original_require = env.require
env.require = function(name)
    if name == "systems/workshop_entry" then
        state.requires[#state.requires + 1] = name
        return module_entry
    end
    return original_require(name)
end
local main_file = assert(io.open("scripts/vscripts/addon_game_mode.lua", "rb"))
local main_source = main_file:read("*a"); main_file:close()
local prefix_end = assert(main_source:find("\nlocal SURVIVAL_FORCE_HERO", 1, true), "real entry prefix missing")
local prefix = assert(loadstring(main_source:sub(1, prefix_end), "@real_addon_entry_prefix"))
setfenv(prefix, env)
prefix()
check(type(rawget(env, "Precache")) == "function" and type(rawget(env, "Activate")) == "function",
    "the addon main scope owns the native callbacks")
check(rawget(module_env, "Precache") == nil and rawget(module_env, "Activate") == nil)
check(#state.requires == 1 and state.requires[1] == "systems/workshop_entry" and state.setup_calls == 0,
    "the entry prefix returns before requiring any gameplay or cloud module")
env.Precache({}); env.Activate()
check(state.think_calls == 1 and state.setup_calls > 0 and state.forbidden_calls == 0,
    "the native main-scope Activate reaches the lightweight server module")
env.Activate()
check(state.think_calls == 1)

-- The client route is deliberately not an identity grant. Its immutable target
-- still has the original server-owned four-account and web-auth barriers.
env, state = fixture(false, true, "ws4_entry")
env.command, env.workshop_id, env.target_map = "sv_cheats 1", "attacker", "injected_map"
local client = load(CLIENT, env)
check(#state.commands == 1 and state.commands[1] == "dota_launch_custom_game 3824360109 template_map")
check(client.init({command = "exec injected", workshop_id = "other", map = "other"}))
env.Activate(); env.ActivateClient(); load(CLIENT, env)
check(#state.commands == 1 and #state.requires == 0 and state.setup_calls == 0 and state.think_calls == 0,
    "client execution and repeated loads cannot import server systems or issue a second command")
check(state.forbidden_calls == 0)
env, state = fixture(false, true, "maps/ws4_entry.vpk")
client = load(CLIENT, env)
check(#state.commands == 1 and state.commands[1] == "dota_launch_custom_game 3824360109 template_map",
    "the exact map VPK path returned by the native client routes successfully")
env.Activate(); env.ActivateClient(); load(CLIENT, env)
check(#state.commands == 1, "the native VPK map form also routes only once per VM")
for _, row in ipairs({{true, false, "ws4_entry"}, {true, true, "ws4_entry"}, {false, false, "ws4_entry"},
                      {false, 1, "ws4_entry"}, {false, true, "template_map"},
                      {false, true, "offline_logic_test"}, {false, true, "WS4_ENTRY"},
                      {false, true, "maps/template_map.vpk"}, {false, true, "maps/offline_logic_test.vpk"},
                      {false, true, "prefix/maps/ws4_entry.vpk"}, {false, true, "maps/ws4_entry.vpk.bak"},
                      {false, true, "maps/../maps/ws4_entry.vpk"}, {false, true, "maps/ws4_entry.vpk; exec injected"}}) do
    env, state = fixture(unpack(row))
    local original = function() end
    env.Activate, env.ActivateClient = original, original
    client = load(CLIENT, env)
    check(client.init() == false and #state.commands == 0 and #state.requires == 0)
    check(env.Activate == original and env.ActivateClient == original,
        "ordinary template/offline maps keep their existing client lifecycle")
end
for _, unavailable in ipairs({"IsServer", "IsClient", "GetMapName"}) do
    env, state = fixture(false, true, "ws4_entry")
    env[unavailable] = function() error("native unavailable") end
    client = load(CLIENT, env)
    check(client.init() == false and #state.commands == 0)
end
env, state = fixture(false, true, "ws4_entry")
env.SendToConsole = false
client = load(CLIENT, env)
check(#state.commands == 0 and client.init() == false)
env.SendToConsole = function(command) state.commands[#state.commands + 1] = command end
env.ActivateClient()
check(#state.commands == 1, "activation may recover only before a command has been attempted")
env, state = fixture(false, true, "ws4_entry")
env.SendToConsole = function(command) state.commands[#state.commands + 1] = command; error("native dispatch failed") end
client = load(CLIENT, env)
env.Activate(); env.ActivateClient(); client.init(); load(CLIENT, env)
check(#state.commands == 1, "even a failed native dispatch is attempted only once per VM")
check(state.forbidden_calls == 0)

print("WORKSHOP_ENTRY_PASS checks=" .. checks .. ": real four-account gate, lightweight server, exact client map/VM, fixed same-item command, once-per-VM, ordinary/offline untouched")
