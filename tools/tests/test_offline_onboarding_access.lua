-- Real access, offline provider, profiles and startup modules. Only engine I/O
-- is replaced; no test account, HTTP response or persistent save is fabricated.
package.path = "scripts/vscripts/?.lua;" .. package.path
local original_open = io.open
local release = require("config/release_profile")
local web_config = require("config/player_web_auth")
local original_channel, original_web = release.channel, web_config.enabled
local event_bus = require("core/event_bus")
local groups = 0

local function environment(options)
    options = options or {}
    io.open = original_open
    for _, name in ipairs({"debug/offline_onboarding_test", "core/test_access_policy",
        "debug/offline_logic_test", "systems/player_profile_service",
        "systems/startup_loading_service", "systems/player_web_auth"}) do
        package.loaded[name] = nil
    end
    event_bus.reset()
    release.channel = options.production and "production" or "development"
    web_config.enabled = options.web == true
    local state = {time=0, native_state=2, steam=options.steam or 123456789,
        tools=options.tools ~= false, server=options.server ~= false, fake=false,
        valid=true, bound_id=0, http=0, files=0, kicks=0, admission=0, gameplay=0,
        values={survival_offline_logic_test=options.offline == false and "0" or "1",
            survival_offline_onboarding_test=options.preview == false and "0" or "1"},
        listeners={},tasks={},responses={},registered={},
        asset={total=10,ready=0,failed=0,progress=0,complete=false}}
    Convars = {
        RegisterConvar=function(_, name, default)
            if state.values[name] == nil then state.values[name] = default end
            state.registered[name]=true
        end,
        GetStr=function(_, name)
            if options.registration_required and not state.registered[name] then return "" end
            return state.values[name] or ""
        end,
    }
    IsServer=function() return state.server end
    IsInToolsMode=function() return state.tools end
    Time=function() return state.time end
    local unique=0
    DoUniqueString=function(prefix) unique=unique+1;return prefix..unique end
    DOTA_MAX_TEAM_PLAYERS,DOTA_CONNECTION_STATE_CONNECTED=4,2
    DOTA_TEAM_SPECTATOR,DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP=1,2
    DisconnectClient=function() state.kicks=state.kicks+1 end
    local player={GetPlayerID=function() return state.bound_id end,IsNull=function() return false end}
    PlayerResource={
        IsValidPlayerID=function(_, id) return id==0 and state.valid end,
        IsFakeClient=function() return state.fake end,
        GetSteamAccountID=function() return state.steam end,
        GetPlayer=function(_, id) return id==0 and player or nil end,
        GetPlayerName=function() return "Offline tutorial tester" end,
        GetConnectionState=function() return 2 end,
        GetTeam=function() return 2 end,
    }
    EntIndexToHScript=function(index) return index==200 and player or nil end
    GameRules={
        GetGameModeEntity=function() return {SetContextThink=function(_, name, callback) state.tasks[name]=callback end} end,
        State_Get=function() return state.native_state end,
        GetGameTime=function() return state.time end,
        PlayerHasCustomGameHostPrivileges=function(_, actor) return actor==player end,
    }
    CustomGameEventManager={
        RegisterListener=function(_, name, callback) state.listeners[name]=callback;return name end,
        UnregisterListener=function(_, name) state.listeners[name]=nil end,
        Send_ServerToPlayer=function(_, actor, name, payload)
            assert(actor==player);state.responses[name]=payload
        end,
    }
    CustomNetTables={SetTableValue=function() end}
    CreateHTTPRequestScriptVM=function() state.http=state.http+1;error("offline HTTP forbidden") end
    package.loaded["core/logger"]={info=function() end,warn=function() end}
    package.loaded["core/scheduler"]={every=function(_, callback, name) state.tasks[name]=callback end}
    package.loaded["systems/multiplayer_player_service"]={
        participating_player_ids=function() return {0} end,is_disconnected=function() return false end}
    package.loaded["systems/startup_asset_preload_service"]={
        snapshot=function() return state.asset end,retry=function() return {ok=true} end}
    state.helper=require("debug/offline_onboarding_test")
    state.access=require("core/test_access_policy")
    return state
end

local function passed() groups=groups+1 end
local state=environment()
assert(state.access.init() and state.helper.requested(), "early access init latches preview before provider exists")
assert(state.access.allowed(0), "any real human account may preview even outside the four-account list")
assert(not state.helper.is_enabled() and state.helper.account_id(0)==nil,
    "early access request must not construct or enable an offline provider")
for _, id in ipairs({-1,256,0.5,"0"}) do assert(not state.access.allowed(id)) end
state.fake=true;assert(not state.access.allowed(0));state.fake=false
state.valid=false;assert(not state.access.allowed(0));state.valid=true
state.bound_id=1;assert(not state.access.allowed(0));state.bound_id=0
passed()

state=environment({registration_required=true})
assert(Convars:GetStr("survival_offline_logic_test")==""
    and Convars:GetStr("survival_offline_onboarding_test")=="",
    "Source 2 command-line values may remain hidden until registration")
assert(state.access.init() and state.helper.requested() and state.access.allowed(0),
    "early policy registers both flags before latching the requested preview")
assert(state.registered.survival_offline_logic_test and state.registered.survival_offline_onboarding_test)
assert(Convars:GetStr("survival_offline_logic_test")=="1"
    and Convars:GetStr("survival_offline_onboarding_test")=="1",
    "registration preserves explicit launch values")
passed()

for _, options in ipairs({{production=true},{tools=false},{server=false},{web=true},
    {offline=false},{preview=false}}) do
    state=environment(options)
    assert(not state.helper.requested() and not state.helper.is_enabled())
    assert(not state.access.allowed(0), "untrusted or single-flag launch keeps the restricted policy")
end
passed()

state=environment({preview=false})
assert(not state.helper.requested())
state.values.survival_offline_onboarding_test="1"
assert(not state.helper.configure() and not state.access.allowed(0), "late convar cannot open admission")
state=environment()
assert(state.helper.requested())
state.values.survival_offline_logic_test="0"
state.values.survival_offline_onboarding_test="0"
assert(state.helper.requested(), "launch choice is latched rather than toggled midmatch")
state.tools=false;assert(not state.helper.requested() and not state.access.allowed(0))
state.tools=true;release.channel="production";assert(not state.helper.requested())
release.channel="development";web_config.enabled=true;assert(not state.helper.requested())
passed()

local function start(options)
    local current=environment(options)
    assert(current.access.init())
    current.offline=require("debug/offline_logic_test")
    assert(current.offline.configure())
    assert(current.helper.is_enabled())
    current.profiles=require("systems/player_profile_service")
    current.startup=require("systems/startup_loading_service")
    current.setup=require("systems/match_setup_service")
    io.open=function() current.files=current.files+1;error("offline save file access forbidden") end
    current.profiles.init(current.offline.profile_options())
    current.startup.init({native_team_setup=true,tools_backend_wait=false,
        on_ready=function() current.admission=current.admission+1 end})
    current.startup.gameplay_gate(function() current.gameplay=current.gameplay+1 end)
    function current.tick(count)
        for _=1,count do current.time=current.time+.25;current.startup.tick() end
    end
    function current.ack()
        current.listeners.survival_loading_client_ready(200,{session_id=current.setup.get_session_id()})
    end
    function current.select()
        current.listeners.survival_loading_mode_select(200,
            {session_id=current.setup.get_session_id(),mode_id="standard"})
        return current.responses.survival_loading_mode_result
    end
    return current
end

for _, steam in ipairs({123456789,0}) do
    state=start({steam=steam,registration_required=true})
    local account=steam>0 and tostring(steam) or "offline-player-0"
    assert(state.helper.account_id(0)==account)
    assert(state.profiles.get_provider().resolve_account_id(0)==account)
    state.ack();state.tick(2)
    assert(not state.startup.is_ready(), "native host start remains required")
    state.native_state=3;state.tick(2)
    assert(not state.startup.is_ready() and state.startup.snapshot().players[1].authenticated,
        "real provider authenticates the same identity while asset gate remains closed")
    state.asset={total=10,ready=10,failed=0,progress=100,complete=true}
    state.tick(2)
    assert(state.startup.is_ready() and state.admission==1 and not state.startup.is_gameplay_ready())
    assert(state.select().success==1)
    state.tick(3)
    assert(state.startup.is_player_ready(0) and state.startup.is_gameplay_ready() and state.gameplay==1)
    local profile=assert(state.profiles.get_profile(0))
    assert(profile.account_id==account and state.profiles.is_authenticated_for_account(0,account))
    assert(state.startup.is_difficulty_selection_ready(0))
    local receipt
    state.profiles.get_provider().onboarding_state({account_id=account},function(value) receipt=value end,error)
    assert(receipt.ok and receipt.required and receipt.status=="required",
        "existing accounts and Steam-free players both get the actual local tutorial state")
    state.steam=987654321
    assert(state.helper.account_id(0)=="987654321")
    assert(not state.startup.is_player_ready(0)
        and not state.profiles.is_authenticated_for_account(0,account),
        "identity change closes gameplay instead of inheriting a prior local save")
    assert(state.select().success==0, "old admission cannot select a mode after identity changes")
    assert(state.http==0 and state.files==0 and state.kicks==0)
    passed()
end

-- A zero identity becoming real before admission also cannot reuse its UI ack
-- and authentication; restart gives the new identity a fresh memory match.
state=start({steam=0})
state.native_state=3;state.ack();state.tick(2)
assert(state.startup.snapshot().players[1].authenticated)
state.steam=55555555
state.asset={total=10,ready=10,failed=0,progress=100,complete=true}
state.tick(3)
assert(not state.startup.is_ready() and state.startup.snapshot().error=="player_identity_changed")
assert(not state.profiles.is_authenticated_for_account(0,"offline-player-0"))
assert(state.http==0 and state.files==0)
passed()

io.open=original_open
release.channel,web_config.enabled=original_channel,original_web
print("OFFLINE_ONBOARDING_ACCESS_PASS: "..groups.." groups; trusted launch latch, arbitrary accounts, Steam-zero real startup/provider, identity changes, no HTTP/files")
