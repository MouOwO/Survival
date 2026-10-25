-- Exercise the actual provider and actual four-account admission policy.
package.path = "scripts/vscripts/?.lua;" .. package.path

local config = require("config/session_multiplayer_test")
local access_config = require("config/test_access")
local web_config = require("config/player_web_auth")
assert(config.enabled == false and config.expected_map == "template_map", "checked-in opt-in must stay off")
package.loaded["config/release_profile"] = { channel = "production" }

local server, tools, map, cheats = true, false, "template_map", false
local session, mode = "native_session_one", nil
local identities = { [0] = 885195478, [1] = 463897428, [2] = 144521714, [3] = 1014036256, [4] = 7 }
local fake, disconnected, http_calls, file_calls = {}, {}, 0, 0
IsServer = function() return server end
IsInToolsMode = function() return tools end
GetMapName = function() return map end
Convars = { GetBool = function(_, name) assert(name == "sv_cheats"); return cheats end }
DisconnectClient = function(id, forced) assert(forced == true); disconnected[id] = true end
PlayerResource = {
    IsValidPlayerID = function(_, id) return identities[id] ~= nil end,
    GetSteamAccountID = function(_, id) return identities[id] end,
    IsFakeClient = function(_, id) return fake[id] == true end,
}
package.loaded["systems/match_setup_service"] = {
    get_session_id = function() return session end,
    get_mode = function() return mode end,
    get_profile_mode = function() return mode == "cold" and "standard" or mode end,
    is_mode_selected = function() return mode ~= nil end,
}
local function forbidden_http()
    http_calls = http_calls + 1
    error("session test attempted HTTP")
end
CreateHTTPRequestScriptVM, CreateHTTPRequest = forbidden_http, forbidden_http
local session_test = require("systems/session_multiplayer_test")
assert(session_test.configure() == false and session_test.profile_options() == nil)
assert(require("core/release_policy").is_production(), "test must cover production explicitly")
local original_open, original_load = io.open, LoadKeyValues
io.open = function() file_calls = file_calls + 1; error("session provider attempted file access") end
LoadKeyValues = function() file_calls = file_calls + 1; error("session provider attempted fixture loading") end

config.enabled, web_config.enabled = true, false
assert(session_test.configure(), "explicit native restricted test is allowed in production")
local options = assert(session_test.profile_options())
assert(options.session_multiplayer_test == true and options.offline_logic_test == nil)
local provider = options.provider
assert(session_test.is_provider(provider) and not session_test.is_provider({}), "provider identity is exact")
local option_count = 0
for _ in pairs(options) do option_count = option_count + 1 end
assert(option_count == 2, "only provider identity and the scoped session option are returned")
provider.init()
local alpha, beta = provider.resolve_account_id(0), provider.resolve_account_id(1)
assert(alpha == "885195478" and beta == "463897428", "identity must remain the real engine account")
assert(provider.resolve_account_id(4) == nil and disconnected[4], "unknown real account is enforced")
fake[2] = true
assert(provider.resolve_account_id(2) == nil, "fake client cannot acquire a profile")
fake[2] = nil
assert(provider.resolve_account_id(-1) == nil and provider.resolve_account_id(0.5) == nil)

local function fetched(account)
    local value, reason
    provider.fetch_snapshot(account, function(result) value = result end, function(error_code) reason = error_code end)
    return value, reason
end
local function authenticated(account)
    local value, reason
    provider.authenticate(account, function(result) value = result end, function(error_code) reason = error_code end)
    return value, reason
end
local auth = assert(authenticated(alpha))
assert(auth.authenticated and auth.account_id == alpha and auth.match_session_id == session)
assert(auth.progression.loaded and next(auth.progression.clear_counts) == nil)
local missing, reason = fetched(alpha)
assert(missing == nil and reason == "mode_not_selected", "authentication does not choose a mode")
assert(authenticated("invented_account") == nil)

mode = "standard"
local first, second = assert(fetched(alpha)), assert(fetched(beta))
assert(first.account_id ~= second.account_id and first.match_session_id == session)
assert(first.save.gameplay_stats.initial_wood == 10 and first.save.gameplay_stats.hero_initial_attack == 100)
assert(next(first.entitlements) == nil and next(first.achievements) == nil
    and next(first.save.content_inventory) == nil and next(first.save.archive) == nil,
    "profiles contain authored base values and no permanent grants")
first.save.content_inventory.session_probe = 3
first.save.gameplay_stats.initial_wood = 40
first.save.archive.clear_counts = { n1 = 2 }
assert(provider.persist_save(alpha, first.save, 10))
first.save.content_inventory.session_probe = 999
assert(provider.persist_gameplay_stats(beta, { initial_wood = 70 }, 11))
local stored = assert(fetched(alpha))
assert(stored.save.content_inventory.session_probe == 3 and stored.save.gameplay_stats.initial_wood == 40)
assert(stored.progression.clear_counts.n1 == 2, "progression follows this account's session save")
assert(fetched(beta).save.content_inventory.session_probe == nil and fetched(beta).save.gameplay_stats.initial_wood == 70,
    "second account cannot inherit the first account's writes")
stored.save.content_inventory.session_probe = 888
assert(fetched(alpha).save.content_inventory.session_probe == 3, "snapshots never alias provider memory")

mode = "pure"
assert(fetched(alpha).save.gameplay_stats.initial_wood == 10 and fetched(alpha).save.content_inventory.session_probe == nil)
assert(provider.persist_isolated_gameplay_stat(alpha, "initial_wood", 22, 12))
assert(fetched(alpha).save.gameplay_stats.initial_wood == 22)
assert(fetched(beta).save.gameplay_stats.initial_wood == 10, "pure profiles also isolate accounts")
mode = "standard"
assert(fetched(alpha).save.gameplay_stats.initial_wood == 40, "pure writes cannot replace standard save")
mode = "cold"
assert(fetched(alpha).mode == "standard" and fetched(alpha).game_mode == "cold")
mode = "standard"
assert(not provider.persist_save(alpha, {}, 13))
assert(not provider.persist_isolated_gameplay_stat(alpha, "invented_field", 1, 13))
assert(not provider.persist_gameplay_stats(alpha, {}, math.huge))

identities[0] = identities[1]
assert(fetched(alpha) == nil and authenticated(alpha) == nil, "a changed slot identity revokes old access")
assert(provider.resolve_account_id(0) == nil, "one Steam account cannot own two admitted slots")
identities[0] = 885195478
assert(provider.resolve_account_id(0) == alpha)

session, mode = "native_session_two", "standard"
assert(fetched(alpha) == nil and authenticated(beta) == nil, "new match revokes every prior account binding")
assert(provider.resolve_account_id(0) == alpha and provider.resolve_account_id(1) == beta)
local restarted = assert(fetched(alpha))
assert(restarted.match_session_id == session and restarted.save.content_inventory.session_probe == nil
    and restarted.save.gameplay_stats.initial_wood == 10 and next(restarted.progression.clear_counts) == nil)
assert(provider.persist_gameplay_stats(alpha, { initial_wood = 90 }, 50))
provider.init()
assert(fetched(alpha) == nil, "provider restart clears bindings even if engine session text is unchanged")
assert(provider.resolve_account_id(0) == alpha and fetched(alpha).save.gameplay_stats.initial_wood == 10)

local refusal_cases = 0
local function rejected(change, restore, expected)
    change()
    local ok, message = pcall(session_test.configure)
    assert(not ok and tostring(message):find(expected, 1, true), "expected refusal: " .. expected)
    assert(not session_test.is_enabled() and session_test.profile_options() == nil)
    restore()
    assert(session_test.configure())
    refusal_cases = refusal_cases + 1
end
rejected(function() tools = true end, function() tools = false end, "native_required")
rejected(function() server = false end, function() server = true end, "server_required")
rejected(function() map = "ws4_entry" end, function() map = "template_map" end, "map_required")
rejected(function() config.expected_map = "ws4_entry" end, function() config.expected_map = "template_map" end,
    "configuration_invalid")
rejected(function() config.enabled = "true" end, function() config.enabled = true end, "configuration_invalid")
for _, invalid in ipairs({ true, 1, "1", "true", "FALSE", " false ", "", 2, -1, {} }) do
    rejected(function() cheats = invalid end, function() cheats = false end, "cheats_must_be_disabled")
end

-- Normal Source 2 native capture: the same false cvar has three different
-- representations. Every available getter must still explicitly report off.
local original_convars = Convars
local native_values = { GetBool = false, GetInt = 0, GetStr = "false" }
Convars = {}
for _, name in ipairs({ "GetBool", "GetInt", "GetStr" }) do
    local getter = name
    Convars[getter] = function(_, requested)
        assert(requested == "sv_cheats")
        return native_values[getter]
    end
end
assert(session_test.configure() and session_test.is_enabled(), "real native false/0/string-false getter combination is allowed")
for _, name in ipairs({ "GetBool", "GetInt", "GetStr" }) do
    local getter, off = name, native_values[name]
    for _, invalid in ipairs({ true, 1, "true", "1", "FALSE", " false ", "off" }) do
        rejected(function() native_values[getter] = invalid end,
            function() native_values[getter] = off end, "cheats_must_be_disabled")
    end
    rejected(function() native_values[getter] = nil end,
        function() native_values[getter] = off end, "cheats_must_be_disabled")
    local normal = Convars[getter]
    rejected(function() Convars[getter] = function() error("getter unavailable") end end,
        function() Convars[getter] = normal end, "cheats_must_be_disabled")
end
provider.init()
assert(provider.resolve_account_id(0) == alpha)
assert(provider.persist_gameplay_stats(alpha, { initial_wood = 88 }, 60))
native_values.GetStr = "true"
assert(not session_test.is_enabled() and session_test.profile_options() == nil,
    "one native getter changing on revokes the session even when the other two still say off")
native_values.GetStr = "false"
assert(not session_test.is_enabled(), "returning to all-off cannot revive a revoked session")
assert(session_test.configure())
provider.init()
assert(provider.resolve_account_id(0) == alpha and fetched(alpha).save.gameplay_stats.initial_wood == 10,
    "native getter revocation clears the earlier in-memory profile")
Convars = original_convars
assert(session_test.configure())

local convars = Convars
rejected(function() Convars = nil end, function() Convars = convars end, "cheats_must_be_disabled")
rejected(function() Convars.GetInt = function() return 1 end end,
    function() Convars.GetInt = nil end, "cheats_must_be_disabled")
cheats = 0
assert(session_test.configure(), "numeric zero is an explicit non-cheating state")
cheats = false
rejected(function() web_config.enabled = true end, function() web_config.enabled = false end, "web_auth_conflict")
rejected(function() web_config.enabled = nil end, function() web_config.enabled = false end, "web_auth_conflict")
rejected(function() access_config.enabled = false end, function() access_config.enabled = true end,
    "four_account_gate_required")
local fourth = access_config.allowed_steamids[4]
rejected(function() access_config.allowed_steamids[4] = nil end,
    function() access_config.allowed_steamids[4] = fourth end, "four_account_gate_required")
rejected(function() access_config.allowed_steamids[4] = access_config.allowed_steamids[1] end,
    function() access_config.allowed_steamids[4] = fourth end, "four_account_gate_required")

local function missing_configuration(name, expected)
    local prior, preload = package.loaded[name], package.preload[name]
    rejected(function()
        package.loaded[name] = nil
        package.preload[name] = function() error("configuration absent") end
    end, function() package.loaded[name], package.preload[name] = prior, preload end, expected)
end
missing_configuration("config/session_multiplayer_test", "configuration_invalid")
missing_configuration("config/player_web_auth", "web_auth_conflict")
missing_configuration("config/test_access", "four_account_gate_required")
missing_configuration("core/test_access_policy", "four_account_gate_required")
local access_policy = require("core/test_access_policy")
local access_init = access_policy.init
rejected(function() access_policy.init = function() error("admission unavailable") end end,
    function() access_policy.init = access_init end, "four_account_gate_required")

provider.init()
assert(provider.resolve_account_id(0) == alpha)
cheats = true
assert(not session_test.is_enabled() and session_test.profile_options() == nil)
cheats = false
assert(not session_test.is_enabled(), "runtime safety loss latches off until explicit configure")
assert(not pcall(provider.fetch_snapshot, alpha, function() error("unexpected success") end, function() end))
assert(session_test.configure())
provider.init()
assert(provider.resolve_account_id(0) == alpha and fetched(alpha).save.gameplay_stats.initial_wood == 10,
    "reconfiguration cannot resurrect old data")
assert(not provider.archive_enabled() and provider.archive_submit == nil and provider.online_checkpoint == nil
    and provider.lottery_catalog == nil, "provider has no remote persistence contract")
assert(package.loaded["debug/offline_logic_test"] == nil and package.loaded["debug/mode_unlock_test"] == nil,
    "native session provider must not enable debug modules")
assert(http_calls == 0 and file_calls == 0, "all exercised auth/read/write/reset/refusal paths avoid HTTP and files")
io.open, LoadKeyValues = original_open, original_load
config.enabled = false
assert(session_test.configure() == false and session_test.profile_options() == nil)
print("SESSION_MULTIPLAYER_TEST_PASS: real four-account policy; two-account/mode/session isolation; restart clears; "
    .. refusal_cases .. " fail-closed gates; production opt-in; no HTTP/files/debug/archive")
