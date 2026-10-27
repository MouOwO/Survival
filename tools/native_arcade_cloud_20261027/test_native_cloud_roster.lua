-- Actual read-only roster and access modules; no live game, HTTP or orders.
local PATH = "scripts/vscripts/systems/native_cloud_roster.lua"
local checks, groups = 0, 0
local function check(value, message) checks = checks + 1; assert(value, message or "check failed") end
local function load(path, env) local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk() end
local function fixture()
    local s = {option = "463897428_885195478", reads = 0, required = {}, server = true, client = false, tools = false,
        map = "template_map", cheats = 0, valid = {}, players = {}, accounts = {}, connections = {}, teams = {}, fake = {},
        profile = {channel = "production"}, config = {enabled = true, allowed_steamids = {
            "76561198424163156", "76561198845461206", "76561198104787442", "76561198974301984"}}}
    local e = setmetatable({}, {__index = _G}); e._G = e; e.package = {loaded = {}}
    e.IsServer, e.IsClient, e.IsInToolsMode = function() return s.server end, function() return s.client end, function() return s.tools end
    e.GetMapName = function() return s.map end
    e.Convars = {GetInt = function(_, name) check(name == "sv_cheats"); return s.cheats end,
        GetStr = function() return "0" end, RegisterConvar = function() end}
    e.DisconnectClient = function() error("read-only roster must not disconnect anyone") end
    e.SendToServerConsole = function() error("read-only roster must not run commands") end
    e.print = function() error("read-only roster must not log player identities") end
    e.PlayerResource = {
        IsValidPlayerID = function(_, id) return s.valid[id] == true end,
        IsFakeClient = function(_, id) return s.fake[id] == true end,
        GetTeam = function(_, id) return s.teams[id] end,
        GetPlayer = function(_, id) return s.players[id] end,
        GetConnectionState = function(_, id) return s.connections[id] end,
        GetSteamAccountID = function(_, id) return s.accounts[id] end,
    }
    s.add = function(id, account, connection)
        local bound = id
        s.valid[id], s.accounts[id], s.connections[id], s.teams[id] = true, account, connection or 2, 2
        s.players[id] = {GetPlayerID = function() return bound end, IsNull = function() return false end}
    end
    s.add(0, 463897428); s.add(5, 885195478)
    s.mode = {}
    e.GameRules = {GetGameModeEntity = function() return s.mode end,
        GetGameSessionConfigValue = function(_, name, fallback)
            check(name == "ws4_native_roster" and fallback == "", "reads only the fixed engine option with exact empty default")
            s.reads = s.reads + 1; return s.option
        end,
        GetCustomGamePlayerCount = function() error("target VM count must not shrink entry roster") end,
        SetCustomGameTeamMaxPlayers = function() error("read-only roster cannot set team capacity") end,
    }
    local modules = {['core/test_access_policy'] = "scripts/vscripts/core/test_access_policy.lua",
        ['debug/offline_onboarding_test'] = "scripts/vscripts/debug/offline_onboarding_test.lua",
        ['core/release_policy'] = "scripts/vscripts/core/release_policy.lua"}
    e.require = function(name)
        s.required[#s.required + 1] = name
        if name == "config/release_profile" then return s.profile end
        if name == "config/test_access" then return s.config end
        if not modules[name] then error("forbidden identity/profile/payment/gameplay require: " .. name) end
        if not e.package.loaded[name] then e.package.loaded[name] = load(modules[name], e) end
        return e.package.loaded[name]
    end
    return e, s, load(PATH, e)
end
local function group(name, fn) fn(); groups = groups + 1; print("PASS " .. name) end

group("load is inert and expected roster is copied from fixed option", function()
    local _, s, p = fixture()
    check(s.reads == 0 and #s.required == 0, "require neither inspects engine nor initializes policy")
    check(p.requirement_present() == true)
    local accounts = p.expected_accounts()
    check(#accounts == 2 and accounts[1] == "463897428" and accounts[2] == "885195478")
    accounts[1] = "123"
    check(p.expected_accounts()[1] == "463897428", "caller cannot mutate stored party requirement")
    local ready, reason = p.complete_roster()
    check(ready and reason == "complete" and s.reads >= 4, "every observation reads actual map option and player bindings")
    check(s.required[1] == "config/release_profile" and #s.required > 3, "real production access-policy chain runs")
end)

group("one to four actual accounts bind across non-contiguous player slots", function()
    local expected = {"463897428", "463897428_885195478", "144521714_463897428_885195478",
        "144521714_463897428_885195478_1014036256"}
    for count = 1, 4 do
        local _, s, p = fixture(); s.valid, s.players, s.accounts, s.connections, s.teams = {}, {}, {}, {}, {}
        local identities = {463897428, 885195478, 144521714, 1014036256}
        s.option = expected[count]
        for index = 1, count do s.add((index - 1) * 5, identities[index]) end
        local row = p.snapshot()
        check(row.present and row.valid and row.complete and #row.expected_accounts == count and #row.player_ids == count,
            "all named real humans are needed regardless of target temporary native count")
    end
    local _, s, p = fixture(); s.option = "885195478_463897428"
    check(p.expected_accounts()[1] == "463897428" and p.complete_roster(), "valid unsorted input is normalized numerically")
end)

group("slow guest remains required when host has already connected", function()
    local _, s, p = fixture(); s.valid[5], s.players[5] = false, nil
    for _ = 1, 15 do
        local ready, reason = p.complete_roster()
        check(not ready and reason == "waiting_expected_roster" and #p.expected_accounts() == 2,
            "polling cannot replace two-account requirement with first target player")
    end
    s.add(5, 885195478, 1)
    check(not p.complete_roster(), "resource arrival is not a connected real player")
    s.connections[5] = 2; check(p.complete_roster(), "guest becoming connected completes the original party")
    s.connections[5] = 3; check(not p.complete_roster(), "same-world disconnect is observed immediately")
    s.connections[5] = 2; check(p.complete_roster(), "reconnection requires actual entity and account again")
end)

group("missing option never invents a roster or changes ordinary helper mode", function()
    local _, s, p = fixture(); s.option = ""; s.tools = true; s.profile.channel = "development"
    check(p.requirement_present() == false)
    local expected, reason = p.expected_accounts()
    check(type(expected) == "table" and #expected == 0 and reason == "not_required", "no roster inferred from PlayerResource")
    local ready, status = p.complete_roster()
    local profile_only = true
    for _, name in ipairs(s.required) do if name ~= "config/release_profile" then profile_only = false end end
    check(ready and status == "not_required" and profile_only,
        "absent optional barrier leaves caller's normal helper/auth/readiness policy in charge")
end)

group("explicit native flag rejects lost options while legacy false and absent flags remain ordinary", function()
    local _, native_state, native_service = fixture(); native_state.profile.native_cloud_roster_required = true
    check(native_service.complete_roster(), "explicit native flag with the complete real option remains usable")
    for _, value in ipairs({true, false}) do
        local _, s, p = fixture(); s.option = ""; s.profile.native_cloud_roster_required = value
        local complete, reason = p.complete_roster()
        check(complete == not value and reason == (value and "native_roster_option_required" or "not_required"))
        check(p.requirement_present() == value)
    end
    local _, s, p = fixture(); s.option = ""; check(p.complete_roster(), "legacy profile without field keeps ordinary behavior")
    for _, bad in ipairs({"true", 1, {}, function()end}) do
        local _, state, service = fixture(); state.option = ""; state.profile.native_cloud_roster_required = bad
        check(not service.complete_roster() and service.snapshot().status == "native_roster_configuration_invalid")
    end
    for _, bad in ipairs({false, "production", {}, {channel="production",native_cloud_roster_required=true}}) do
        local _, state, service = fixture(); state.option="";state.profile=bad
        if type(bad)=="table" and bad.channel=="production" then state.profile.channel="development" end
        check(not service.complete_roster(), "malformed or contradictory profile cannot disable native requirement")
    end
    local e, state, service = fixture();state.option="";e.require=function()error("private config error")end
    check(not service.complete_roster() and service.snapshot().status=="native_roster_configuration_invalid")
    local _, broken, closed=fixture();broken.option="";broken.profile=setmetatable({}, {__index=function()error("private field error")end})
    check(not closed.complete_roster() and closed.snapshot().status=="native_roster_configuration_invalid")
end)

group("native flag is latched per world and cannot be deleted or disabled to bypass missing option", function()
    for _, change in ipairs({function(p)p.native_cloud_roster_required=nil end,function(p)p.native_cloud_roster_required=false end}) do
        local _, s, p=fixture();s.option="";s.profile.native_cloud_roster_required=true
        check(not p.complete_roster());change(s.profile)
        check(not p.complete_roster() and p.snapshot().status=="native_roster_configuration_changed")
        s.mode={};check(p.complete_roster(),"new legacy world may use its own explicit profile")
    end
end)

group("invalid nonempty map options are closed, never partial or executable", function()
    for _, value in ipairs({"0", "000463897428", "463897428_463897428", "463897428_", "_463897428", "463897428__885195478",
        "463897428,885195478", "463897428 885195478", "463897428;quit", "463897428\nquit", "463897428=1", "NaN",
        "4294967296", "76561198424163156", "123456789", "463897428_885195478_144521714_1014036256_463897428", string.rep("1", 44)}) do
        local _, s, p = fixture(); s.option = value
        check(p.requirement_present() == true and p.expected_accounts() == nil and p.complete_roster() == false,
            "invalid nonempty option is required-but-invalid, never silently absent")
        check(p.snapshot().status == "native_roster_option_invalid")
    end
end)

group("missing option API or nonstring result cannot be interpreted as absence", function()
    for _, change in ipairs({
        function(e, s) e.GameRules.GetGameSessionConfigValue = nil end,
        function(e, s) e.GameRules.GetGameSessionConfigValue = function() error("SECRET option") end end,
        function(e, s) s.option = nil end,
        function(e, s) s.option = 0 / 0 end,
        function(e, s) s.option = {} end,
        function(e, s) s.option = false end,
    }) do
        local e, s, p = fixture(); change(e, s)
        check(p.requirement_present() == true and p.complete_roster() == false
            and p.snapshot().status == "native_roster_option_unavailable", "unknown engine state fails closed")
    end
end)

group("native production and real four-account policy are checked repeatedly", function()
    for _, change in ipairs({
        function(e, s) s.server, s.client = false, true end,
        function(e, s) s.tools = true end,
        function(e, s) s.map = "ws4_entry" end,
        function(e, s) s.cheats = 1 end,
        function(e, s) s.cheats = nil end,
        function(e, s) s.profile.channel = "development" end,
        function(e, s) s.config.enabled = false end,
        function(e, s) s.config.allowed_steamids[4] = nil end,
        function(e, s) e.package.loaded['core/test_access_policy'].allowed = function() return false end end,
    }) do
        local e, s, p = fixture(); check(p.complete_roster()); change(e, s)
        check(p.requirement_present() == true and p.complete_roster() == false,
            "previous complete result never authorizes a changed runtime or policy")
    end
end)

group("replacement, bots and forged account values cannot complete expected party", function()
    for _, change in ipairs({
        function(e, s) s.accounts[5] = 144521714 end,
        function(e, s) s.accounts[5] = 123456789 end,
        function(e, s) s.accounts[5] = s.accounts[0] end,
        function(e, s) s.accounts[5] = 0 / 0 end,
        function(e, s) s.accounts[5] = math.huge end,
        function(e, s) s.accounts[5] = "885195478" end,
        function(e, s) s.accounts[5] = 885195478.5 end,
        function(e, s) s.players[5].GetPlayerID = function() return 0 end end,
        function(e, s) s.players[5].IsNull = function() return true end end,
        function(e, s) s.players[5] = nil end,
        function(e, s) s.fake[5] = true end,
        function(e, s) s.teams[5] = 1 end,
        function(e, s) e.PlayerResource.GetConnectionState = nil end,
    }) do
        local e, s, p = fixture(); check(p.complete_roster()); change(e, s)
        check(not p.complete_roster(), "all observed identities/bindings are revalidated on every call")
    end
    local _, s, p = fixture(); s.add(10, 0, 1)
    check(not p.complete_roster(), "another still-loading human cannot be hidden behind already-complete expected accounts")
end)

group("same-world options cannot shrink and a genuinely new world reads its own option", function()
    local _, s, p = fixture(); check(p.complete_roster())
    s.option = "463897428"; s.valid[5], s.players[5] = false, nil
    check(p.requirement_present() == true and p.expected_accounts() == nil and not p.complete_roster()
        and p.snapshot().status == "native_roster_option_changed", "same-world option edit cannot discard missing guest")
    s.option = ""
    check(p.requirement_present() and not p.complete_roster(), "removing option cannot release existing barrier")
    s.mode = {}; s.option = "463897428"
    check(p.complete_roster() and #p.expected_accounts() == 1, "new world owns a distinct original requirement")
    s.mode = {}; s.option = ""
    check(not p.requirement_present() and #p.expected_accounts() == 0, "new helper world does not inherit a prior party")
end)

print(string.format("PASS native cloud roster: %d groups, %d checks (actual modules; no live game)", groups, checks))
