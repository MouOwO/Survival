-- Actual handoff and access-policy modules; only engine I/O is simulated.
-- No running Dota process, HTTP, files outside this repository, or cloud calls.
local PATH = "scripts/vscripts/systems/native_cloud_handoff.lua"
local COMMAND = "changelevel template_map gamemode=15 customgamemode=3824360109 nomapvalidation=1"
local checks, groups = 0, 0
local function check(value, message) checks = checks + 1; assert(value, message or "check failed") end
local function load(path, env) local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk() end
local function fixture()
    local s = {now = 100, server = true, client = false, tools = false, map = "ws4_entry", cheats = 0, phase = 2,
        expected = 2, expected_roster = "463897428_885195478", valid = {}, players = {}, accounts = {}, connections = {}, fake = {}, teams = {},
        commands = {}, capacities = {}, logs = {}, schedules = 0, ticks = 0, kicks = 0, required = {},
        profile = {channel = "production"}, roster = {enabled = true, allowed_steamids = {
            "76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984"}},
        rules = {by_id = {default_multiplayer = {max_players = 4}}}}
    local e = setmetatable({}, {__index = _G}); e._G = e; e.package = {loaded = {}}
    e.Time = function() return s.now end
    e.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP, e.DOTA_GAMERULES_STATE_POST_GAME = 2, 11
    e.IsServer, e.IsClient, e.IsInToolsMode = function() return s.server end, function() return s.client end, function() return s.tools end
    e.GetMapName = function() return s.map end
    e.DisconnectClient = function() s.kicks = s.kicks + 1; error("handoff must not kick players") end
    e.Convars = {GetInt = function(_, name) check(name == "sv_cheats", "only actual cheats setting read"); return s.cheats end,
        GetStr = function() return "0" end, RegisterConvar = function() end}
    e.PlayerResource = {
        GetPlayerCount = function() return s.expected end,
        IsValidPlayerID = function(_, id) return s.valid[id] == true end,
        IsFakeClient = function(_, id) return s.fake[id] == true end,
        GetTeam = function(_, id) return s.teams[id] end,
        GetPlayer = function(_, id) return s.players[id] end,
        GetConnectionState = function(_, id) return s.connections[id] end,
        GetSteamAccountID = function(_, id) return s.accounts[id] end,
    }
    s.add = function(id, account, connected)
        local bound = id
        s.valid[id], s.accounts[id], s.connections[id], s.teams[id] = true, account, connected or 2, 2
        s.players[id] = {GetPlayerID = function() return bound end, IsNull = function() return false end}
    end
    s.add(0, 463897428); s.add(5, 885195478)
    s.mode = {SetContextThink = function(_, name, callback, delay)
        check(name == "SurvivalNativeCloudHandoff01" and delay == 0.1, "one fixed bounded thinker")
        s.tick, s.schedules = callback, s.schedules + 1
    end}
    e.GameRules = {GetGameModeEntity = function() return s.mode end, State_Get = function() return s.phase end,
        SetCustomGameTeamMaxPlayers = function(_, team, count)
            check(team == 2 and count == 4 or team == 3 and count == 0, "fixed co-op capacity only")
            s.capacities[#s.capacities + 1] = {team, count}
        end}
    e.SendToServerConsole = function(command)
        check(command == COMMAND .. " ws4_native_roster=" .. s.expected_roster,
            "exact validated command prefix plus actual sorted account32 roster only")
        s.commands[#s.commands + 1] = command
    end
    e.print = function(line)
        check(type(line) == "string" and line:find("[WS4-NATIVE-HANDOFF-01] status=", 1, true) == 1
            and not line:find("SECRET", 1, true) and not line:find("765611", 1, true)
            and not line:find("463897428", 1, true), "logs contain fixed statuses/counts, no identities or errors")
        s.logs[#s.logs + 1] = line
    end
    local modules = {['core/test_access_policy'] = "scripts/vscripts/core/test_access_policy.lua",
        ['core/release_policy'] = "scripts/vscripts/core/release_policy.lua"}
    e.require = function(name)
        s.required[#s.required + 1] = name
        if name == "config/release_profile" then return s.profile end
        if name == "config/test_access" then return s.roster end
        if name == "config/generated/multiplayer_rules" then return s.rules end
        if not modules[name] then error("forbidden gameplay/auth/save/payment module: " .. name) end
        if not e.package.loaded[name] then e.package.loaded[name] = load(modules[name], e) end
        return e.package.loaded[name]
    end
    s.advance = function(seconds)
        for _ = 1, math.floor(seconds * 10 + 0.5) do
            s.now = s.now + 0.1
            if s.tick then
                s.ticks = s.ticks + 1
                local delay = s.tick()
                if delay == nil then s.tick = nil else check(delay == 0.1, "fixed think cadence") end
            end
        end
    end
    return e, s, load(PATH, e)
end
local function group(name, fn) fn(); groups = groups + 1; print("PASS " .. name) end

group("require has no side effects and activate takes no parameters", function()
    local _, s, p = fixture()
    check(#s.required == 0 and s.schedules == 0 and #s.commands == 0 and #s.capacities == 0 and #s.logs == 0,
        "module load neither loads dependencies nor configures native runtime")
    check(p.activate({PlayerID = 0, map = "template_map", command = "quit"}) == false)
    check(p.activate(nil) == false and s.schedules == 0 and #s.commands == 0,
        "no payload or optional argument can configure a server handoff")
end)

group("non-contiguous two-player roster waits one stable second and sends once", function()
    local e, s, p = fixture()
    check(p.activate() and p.activate() and s.schedules == 1 and #s.capacities == 2, "activation latches native context")
    check(e.package.loaded['core/test_access_policy'] ~= nil, "real four-account policy loaded")
    s.advance(0.9)
    check(#s.commands == 0 and p.snapshot().players == 2 and p.snapshot().expected_players == 2,
        "does not rush player zero or skip non-contiguous slot five")
    s.advance(0.4)
    check(#s.commands == 1 and p.snapshot().status == "handoff_queued" and p.snapshot().handoff_attempted
        and not p.snapshot().active and s.tick == nil and s.kicks == 0,
        "one fixed server command after complete stable roster, never client launch or kick")
    s.advance(3); check(p.activate() and #s.commands == 1 and s.schedules == 1, "same context cannot issue a second handoff")
    local reloaded = load(PATH, e); check(reloaded.activate() and #s.commands == 1 and s.schedules == 1,
        "module reload cannot repeat committed command")
end)

group("real resource-count API works without the nonexistent GameRules count", function()
    local e, s, p = fixture()
    check(rawget(e.GameRules, "GetCustomGamePlayerCount") == nil,
        "fixture must not invent an API absent from the real engine")
    setmetatable(e.GameRules, {__index = function(_, key)
        if key == "GetCustomGamePlayerCount" then error("nonexistent GameRules count must never be queried") end
    end})
    e.PlayerResource.GetNumConnectedHumanPlayers = function()
        error("connected/team count cannot replace all registered native slots")
    end
    check(p.activate()); s.advance(1.3)
    check(#s.commands == 1 and p.snapshot().expected_players == 2,
        "actual registered count plus setup barrier is sufficient; no invented count fallback")
end)

group("one to four genuine players use the same registered resource barrier", function()
    for number = 1, 4 do
        local _, s, p = fixture()
        s.valid, s.players, s.accounts, s.connections, s.teams = {}, {}, {}, {}, {}
        local accounts = {463897428, 885195478, 144521714, 1014036256}
        for index = 1, number do s.add((index - 1) * 5, accounts[index]) end
        s.expected = number
        s.expected_roster = ({"463897428", "463897428_885195478", "144521714_463897428_885195478",
            "144521714_463897428_885195478_1014036256"})[number]
        check(p.activate()); s.advance(1.3)
        check(#s.commands == 1 and p.snapshot().players == number, "not hard-coded to a single player")
    end
end)

group("connected players wait for native setup before the stable interval", function()
    local _, s, p = fixture(); s.phase = 0
    check(p.activate() and p.snapshot().status == "waiting_native_load")
    s.advance(2)
    check(#s.commands == 0 and p.snapshot().status == "waiting_native_load" and p.snapshot().active,
        "STATE_INIT cannot hand off despite fully connected two-player resources")
    s.phase = 1; s.advance(2)
    check(#s.commands == 0 and p.snapshot().status == "waiting_native_load",
        "WAIT_FOR_PLAYERS_TO_LOAD cannot be replaced by connected resource slots")
    s.phase = 2; s.advance(0.9)
    check(#s.commands == 0 and p.snapshot().status == "waiting_stable_roster",
        "native setup begins a fresh whole-roster stable interval")
    s.advance(0.4); check(#s.commands == 1 and p.snapshot().status == "handoff_queued")
end)

group("missing phase API, constants and non-finite states fail explicitly", function()
    for _, change in ipairs({
        function(e, s) e.GameRules.State_Get = nil end,
        function(e, s) e.GameRules.State_Get = function() error("SECRET state") end end,
        function(e, s) e.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP = nil end,
        function(e, s) e.DOTA_GAMERULES_STATE_POST_GAME = nil end,
        function(e, s) e.DOTA_GAMERULES_STATE_POST_GAME = 2 end,
        function(e, s) e.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP = "2" end,
        function(e, s) s.phase = nil end,
        function(e, s) s.phase = "2" end,
        function(e, s) s.phase = 2.5 end,
        function(e, s) s.phase = -1 end,
        function(e, s) s.phase = 0 / 0 end,
        function(e, s) s.phase = math.huge end,
        function(e, s) s.phase = 11 end,
        function(e, s) s.phase = 12 end,
    }) do
        local e, s, p = fixture(); change(e, s)
        local ok, accepted, reason = pcall(p.activate)
        check(ok and accepted == false and type(reason) == "string" and #s.capacities == 0
            and s.schedules == 0 and #s.commands == 0, "no phase guess, fallback constant or terminal handoff")
    end
end)

group("phase revocation is rechecked before send and preserves total timeout", function()
    local _, s, p = fixture(); check(p.activate()); s.advance(0.8); s.phase = 11; s.advance(1)
    check(#s.commands == 0 and s.tick == nil and p.snapshot().status == "native_game_finished",
        "post-game during stable wait stops handoff permanently")
    local e, final, q = fixture(); check(q.activate())
    local state_reads = 0
    e.GameRules.State_Get = function()
        state_reads = state_reads + 1
        return state_reads >= 3 and 11 or 2
    end
    check(final.tick() == 0.1); final.now = final.now + 1.1
    check(final.tick() == nil and #final.commands == 0 and q.snapshot().status == "native_game_finished",
        "phase ending between stable scan and command is caught at final boundary")
    local _, regressed, r = fixture(); check(r.activate()); regressed.advance(0.8)
    regressed.phase = 1; regressed.advance(1); regressed.phase = 2; regressed.advance(0.9)
    check(#regressed.commands == 0, "regression below setup discards prior stable roster time")
    regressed.advance(0.4); check(#regressed.commands == 1)
    local _, slow, t = fixture(); slow.phase = 1; check(t.activate()); slow.advance(121)
    check(#slow.commands == 0 and slow.tick == nil and t.snapshot().status == "handoff_timeout_or_clock_invalid",
        "waiting native phase consumes the same original 120 second budget")
end)

group("native registered resources protect slow players and late arrivals", function()
    local _, s, p = fixture()
    s.valid[5], s.players[5] = false, nil
    check(p.activate()); s.advance(2)
    check(#s.commands == 0 and p.snapshot().status == "waiting_complete_roster", "registered count of two prevents early host-only transition")
    s.add(5, 885195478, 1); s.advance(2)
    check(#s.commands == 0 and p.snapshot().status == "waiting_connected_roster", "resource slot arrival is not full connection")
    s.connections[5] = 2; s.advance(0.9); check(#s.commands == 0, "new connected roster starts fresh stable interval")
    s.advance(0.4); check(#s.commands == 1 and s.kicks == 0, "slow participant remains admitted")
    local _, later, q = fixture(); later.expected = 1; later.valid[5], later.players[5] = false, nil
    check(q.activate()); later.advance(0.8)
    later.expected = 2; later.add(5, 885195478, 1); later.advance(1.4)
    check(#later.commands == 0, "late resource-count increase cancels prior host stability")
    later.connections[5] = 2; later.advance(1.3); check(#later.commands == 1)
end)

group("native loading-party observation cannot shrink to host-only setup", function()
    local _, s, p = fixture()
    s.phase, s.valid[5], s.players[5] = 1, false, nil
    check(p.activate()); s.advance(0.5)
    check(p.snapshot().expected_players == 2 and #s.commands == 0,
        "native registered party size is remembered during WAIT_FOR_PLAYERS_TO_LOAD")
    s.phase, s.expected = 2, 1
    s.advance(3)
    check(#s.commands == 0 and p.snapshot().status == "waiting_complete_roster" and p.snapshot().expected_players == 2,
        "a disappearing resource must not rewrite the same original party into solo mode")
    s.expected = 2; s.add(5, 885195478, 1); s.advance(1)
    check(#s.commands == 0 and p.snapshot().status == "waiting_connected_roster")
    s.connections[5] = 2; s.advance(0.9); check(#s.commands == 0)
    s.advance(0.4); check(#s.commands == 1)
end)

group("disconnect, entity and account changes reset or revoke readiness", function()
    local _, s, p = fixture(); check(p.activate()); s.advance(0.8)
    s.connections[5] = 3; s.advance(1.5); check(#s.commands == 0)
    s.connections[5] = 2; s.advance(0.8); check(#s.commands == 0)
    s.add(5, 885195478); s.advance(0.8); check(#s.commands == 0, "new entity cannot inherit old entity stable interval")
    s.advance(0.5); check(#s.commands == 1)
    local _, denied, q = fixture(); check(q.activate()); denied.advance(0.8)
    denied.accounts[5] = 123456789; denied.advance(0.8)
    check(#denied.commands == 0 and q.snapshot().status == "account_not_allowed" and denied.tick == nil,
        "foreign identity replaces slot without inheriting transition authority")
end)

group("full recheck catches a player change at final send boundary", function()
    local e, s, p = fixture()
    local read_count = 0
    e.PlayerResource.GetPlayerCount = function()
        read_count = read_count + 1
        if read_count == 3 then s.accounts[5] = 123456789 end
        return s.expected
    end
    check(p.activate()); check(s.tick() == 0.1)
    s.now = s.now + 1.1
    check(s.tick() == nil and #s.commands == 0 and p.snapshot().status == "account_not_allowed",
        "stable first scan is insufficient if actor changes during final roster check")
end)

group("production, actual server, map and cheats guards fail closed", function()
    for _, change in ipairs({
        function(e, s) s.server, s.client = false, true end,
        function(e, s) s.client = true end,
        function(e, s) s.tools = true end,
        function(e, s) s.map = "template_map" end,
        function(e, s) s.map = "ws4_lobby" end,
        function(e, s) s.cheats = 1 end,
        function(e, s) s.cheats = nil end,
        function(e, s) s.cheats = "0" end,
        function(e, s) s.profile.channel = "development" end,
        function(e, s) s.profile = false end,
        function(e, s) s.roster.enabled = false end,
        function(e, s) s.roster.allowed_steamids[4] = nil end,
        function(e, s) s.roster.allowed_steamids[5] = "76561198974301984" end,
        function(e, s) s.rules.by_id.default_multiplayer.max_players = 1 end,
        function(e, s) s.rules.by_id.default_multiplayer.max_players = "4" end,
    }) do
        local e, s, p = fixture(); change(e, s)
        check(p.activate() == false and s.schedules == 0 and #s.commands == 0 and #s.capacities == 0,
            "configuration/client claims do not authorize transition")
    end
end)

group("four-account policy and environment are rechecked during every wait", function()
    for _, change in ipairs({
        function(e, s) s.profile.channel = "development" end,
        function(e, s) s.roster.enabled = false end,
        function(e, s) s.roster.allowed_steamids[4] = "76561198424163156" end,
        function(e, s) s.rules.by_id.default_multiplayer.max_players = 5 end,
        function(e, s) s.tools = true end,
        function(e, s) s.cheats = 1 end,
        function(e, s) s.map = "template_map" end,
        function(e, s) e.package.loaded['core/test_access_policy'].allowed = function() return false end end,
    }) do
        local e, s, p = fixture(); check(p.activate()); s.advance(0.8); change(e, s); s.advance(1)
        check(#s.commands == 0 and s.tick == nil and not p.snapshot().active and s.kicks == 0,
            "revoked server policy halts rather than restarting or kicking")
    end
end)

group("bots, spectators, duplicates and malformed registered counts cannot hand off", function()
    for _, change in ipairs({
        function(e, s) s.fake[5] = true end,
        function(e, s) s.teams[5] = 1 end,
        function(e, s) s.accounts[5] = s.accounts[0] end,
        function(e, s) s.accounts[5] = 123456789 end,
        function(e, s) s.accounts[5] = 885195478.5 end,
        function(e, s) s.accounts[5] = "885195478" end,
        function(e, s) s.players[5].GetPlayerID = function() return 0 end end,
        function(e, s) s.players[5].IsNull = function() return true end end,
        function(e, s) s.expected = 5 end,
        function(e, s) s.expected = -1 end,
        function(e, s) s.expected = "2" end,
        function(e, s) s.expected = nil end,
        function(e, s) s.expected = 0 / 0 end,
        function(e, s) s.expected = math.huge end,
        function(e, s) s.expected = 1.5 end,
    }) do
        local e, s, p = fixture(); change(e, s); check(p.activate()); s.advance(2)
        check(#s.commands == 0 and s.tick == nil and not p.snapshot().active, "malformed roster is never treated as complete")
    end
    local _, s, p = fixture(); s.expected = 0; check(p.activate()); s.advance(2)
    check(#s.commands == 0 and p.snapshot().active and p.snapshot().status == "waiting_roster", "empty resource count waits without inventing players")
end)

group("required engine APIs, false returns and exceptions stay explicit", function()
    for _, change in ipairs({
        function(e, s) e.PlayerResource.GetPlayerCount = nil end,
        function(e, s) e.GameRules.SetCustomGameTeamMaxPlayers = nil end,
        function(e, s) e.SendToServerConsole = nil end,
        function(e, s) e.PlayerResource.GetSteamAccountID = nil end,
        function(e, s) s.mode.SetContextThink = nil end,
        function(e, s) e.Time = nil end,
        function(e, s) e.Convars = {} end,
        function(e, s) e.GameRules.SetCustomGameTeamMaxPlayers = function() return false end end,
        function(e, s) s.mode.SetContextThink = function() return false end end,
        function(e, s) s.mode.SetContextThink = function() error("SECRET timer") end end,
    }) do
        local e, s, p = fixture(); change(e, s)
        local ok, accepted, reason = pcall(p.activate)
        check(ok and accepted == false and type(reason) == "string" and #s.commands == 0,
            "missing or rejected API fails explicitly before any handoff")
    end
    local e, s, p = fixture()
    e.PlayerResource.GetPlayerCount = function() error("SECRET native resource read") end
    check(p.activate()); s.advance(0.2)
    check(#s.commands == 0 and p.snapshot().status == "registered_roster_count_invalid" and not p.snapshot().active,
        "a registered API that throws never falls back to host-only scan size")
    for _, behavior in ipairs({"false", "throw"}) do
        local e, s, p = fixture()
        e.SendToServerConsole = function(command)
            check(command == COMMAND .. " ws4_native_roster=" .. s.expected_roster); s.commands[#s.commands + 1] = command
            if behavior == "throw" then error("SECRET handoff") end
            return false
        end
        check(p.activate()); s.advance(1.3)
        check(#s.commands == 1 and p.snapshot().status == "handoff_send_failed" and p.activate() == false,
            "ambiguous/failed engine call consumes the one-shot latch, never auto retries")
    end
end)

group("timeouts, stopped clocks and old-world callbacks do not force open", function()
    local _, s, p = fixture(); s.expected = 4; check(p.activate()); s.advance(121)
    check(#s.commands == 0 and s.tick == nil and p.snapshot().status == "handoff_timeout_or_clock_invalid"
        and p.activate() == false and s.kicks == 0, "120 second incomplete-roster timeout stops without force-start")
    local _, frozen, q = fixture(); frozen.expected = 4; check(q.activate())
    for _ = 1, 1203 do if frozen.tick and frozen.tick() == nil then frozen.tick = nil end end
    check(#frozen.commands == 0 and frozen.tick == nil, "tick budget also stops when native Time is frozen")
    local _, reversed, r = fixture(); check(r.activate()); reversed.advance(0.8); reversed.now = 99; reversed.advance(0.1)
    check(#reversed.commands == 0 and reversed.tick == nil, "clock reversal cannot satisfy stable window")
    local _, replaced, t = fixture(); check(t.activate()); replaced.advance(0.8); replaced.mode = {}; replaced.advance(1)
    check(#replaced.commands == 0 and replaced.tick == nil and t.snapshot().status == "not_started",
        "old mode thinker cannot operate new native world")
end)

print(string.format("PASS native cloud handoff: %d groups, %d checks (actual module/policy; no live game)", groups, checks))
