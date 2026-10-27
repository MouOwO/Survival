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
    env.package = {loaded = {}}
    env.IsServer = function() return server end
    env.IsClient = function() return client end
    env.IsInToolsMode = function() return false end
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
        if name == "config/release_profile" then return {channel = "production"} end
        if name == "debug/offline_onboarding_test" or name == "core/release_policy" then
            if not env.package.loaded[name] then
                env.package.loaded[name] = load("scripts/vscripts/" .. name .. ".lua", env)
            end
            return env.package.loaded[name]
        end
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

-- The real root prefix must delegate to the server-owned handoff before any
-- gameplay/cloud module. Its engine/roster behavior is exercised separately by
-- test_native_cloud_handoff.lua against the real module and admission policy.
env, state = fixture(true, false, "ws4_entry")
local activation_count = 0
env.require = function(name)
    check(name == "systems/native_cloud_handoff", "only server handoff may load in the entry prefix")
    state.requires[#state.requires + 1] = name
    return {activate = function() activation_count = activation_count + 1; return true end}
end
local main_file = assert(io.open("scripts/vscripts/addon_game_mode.lua", "rb"))
local main_source = main_file:read("*a"); main_file:close()
local prefix_end = assert(main_source:find("\nlocal SURVIVAL_FORCE_HERO", 1, true))
local chunk = assert(loadstring(main_source:sub(1, prefix_end), "@real_addon_entry_prefix"))
setfenv(chunk, env); chunk()
check(type(env.Precache) == "function" and type(env.Activate) == "function")
check(#state.requires == 1 and #state.commands == 0 and activation_count == 0)
env.Precache({}); env.Activate()
check(activation_count == 1 and state.forbidden_calls == 0)

-- Entry clients follow the server's multiplayer changelevel. In particular,
-- neither reloads, hostile globals nor missing APIs may create solo servers.
for _, map in ipairs({"ws4_entry", "maps/ws4_entry.vpk", "template_map", "offline_logic_test", "ws4_entry; exec injected"}) do
    for _, side in ipairs({{false, true}, {true, false}, {true, true}, {false, false}}) do
        env, state = fixture(side[1], side[2], map)
        local original = function() end
        env.Activate, env.ActivateClient = original, original
        env.command, env.workshop_id, env.target_map = "sv_cheats 1", "attacker", "injected_map"
        for iteration = 1, 3 do
            local client = load(CLIENT, env)
            check(type(client) == "table" and next(client) == nil)
            check(#state.commands == 0 and #state.requires == 0 and state.forbidden_calls == 0)
            check(env.Activate == original and env.ActivateClient == original)
        end
    end
end
print("WORKSHOP_ENTRY_PASS checks=" .. checks .. ": legacy admission retained; server handoff prefix; clients never launch solo maps")
