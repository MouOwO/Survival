package.path = "scripts/vscripts/?.lua;" .. package.path

local tools, server, mode, session = true, true, nil, "offline_test_session_1"
local values, http_calls, file_calls = {}, 0, 0
Convars = {
    RegisterConvar = function(_, key, default) if values[key] == nil then values[key] = default end end,
    GetStr = function(_, key) return values[key] or "" end,
}
IsServer = function() return server end
IsInToolsMode = function() return tools end
DisconnectClient = function() error("allowed offline owner was unexpectedly disconnected") end
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    GetSteamAccountID = function() return 885195478 end,
}
CreateHTTPRequestScriptVM = function() http_calls = http_calls + 1; error("offline made an HTTP call") end
package.loaded["core/logger"] = { info = function() end, warn = function() end }
package.loaded["systems/match_setup_service"] = {
    get_session_id = function() return session end,
    get_mode = function() return mode end,
    get_profile_mode = function() return mode == "cold" and "standard" or mode end,
    is_mode_selected = function() return mode ~= nil end,
}
local release = require("config/release_profile")
local web_config = require("config/player_web_auth")
local offline = require("debug/offline_logic_test")
local profiles = require("systems/player_profile_service")

assert(offline.configure() == false and offline.profile_options() == nil,
    "ordinary development launch remains online")
for _, flag in ipairs({ "true", "yes", "01", "2" }) do
    values.survival_offline_logic_test = flag
    assert(not offline.configure(), "only exact explicit 1 enables offline")
end
values.survival_offline_logic_test = "1"
tools = false
local ok, reason = pcall(offline.configure)
assert(not ok and tostring(reason):find("offline_logic_tools_required", 1, true))
assert(not offline.is_enabled() and offline.profile_options() == nil,
    "non-Tools caller cannot force the offline flag")
tools, server = true, false
assert(not pcall(offline.configure), "client Lua cannot enable offline")
server = true
local channel = release.channel
release.channel = "production"
assert(not pcall(offline.configure), "production in Tools cannot enable offline")
release.channel = channel
local web_enabled = web_config.enabled
web_config.enabled = true
assert(not pcall(offline.configure), "online web authorization and offline provider cannot coexist")
web_config.enabled = web_enabled

assert(offline.configure())
local options = assert(offline.profile_options())
assert(options.offline_logic_test and offline.is_provider(options.provider))
local original_open = io.open
io.open = function() file_calls = file_calls + 1; error("offline read or wrote a fixture file") end
profiles.init(options)
local provider = assert(profiles.get_provider())
local account = assert(provider.resolve_account_id(0))
assert(account == "885195478", "memory-only storage must preserve the engine Steam identity used by admission")
assert(provider.resolve_account_id(1) == nil, "restricted player policy remains active")
local auth = profiles.authenticate_player(0, "entry")
assert(auth.ok and auth.authenticated and not auth.pending)
assert(auth.match_session_id == session and profiles.is_authenticated_for_account(0, account))
assert(profiles.get_profile(0) == nil, "entry receipt is not a loaded save")
assert(profiles.load_player(0).error == "mode_not_selected", "offline keeps normal mode selection")

mode = "pure"
assert(profiles.load_player(0).ok)
local pure = assert(profiles.get_profile(0))
assert(pure.mode == "pure" and pure.match_session_id == session)
assert(next(pure.entitlements) == nil and next(pure.achievements) == nil)
assert(next(pure.save.archive) == nil and next(pure.save.content_inventory) == nil,
    "offline starts without old JSON fixtures or cloud inventory")
assert(next(pure.progression.clear_counts) == nil, "does not manufacture permanent clears")
local initial_wood = pure.save.gameplay_stats.initial_wood
pure.save.gameplay_stats.initial_wood = initial_wood + 200
assert(profiles.get_profile(0).save.gameplay_stats.initial_wood == initial_wood,
    "profile caller cannot mutate the memory store")

mode = "cold"
assert(profiles.get_profile(0) == nil, "old pure profile cannot serve a different profile mode")
assert(profiles.load_player(0).ok)
local standard = profiles.get_profile(0)
assert(standard.mode == "standard" and standard.game_mode == "cold",
    "derived modes preserve their actual match identity")
assert(profiles.update_save_section(0, "content_inventory", {offline_probe = 7}, "offline_test").ok)
assert(profiles.refresh_player(0).ok)
assert(profiles.get_profile(0).save.content_inventory.offline_probe == 7,
    "local logic writes and reads the same match-local memory store")
provider.fetch_snapshot(account, function(value)
    value.save.content_inventory.offline_probe = 99
end, error)
assert(profiles.refresh_player(0).ok and profiles.get_profile(0).save.content_inventory.offline_probe == 7,
    "snapshots cannot mutate provider-owned data")
assert(not provider.archive_enabled() and provider.archive_submit == nil
    and provider.online_checkpoint == nil and provider.lottery_catalog == nil,
    "offline has no cloud proxy or long-lived credentials")

session, mode = "offline_test_session_2", nil
assert(not profiles.is_authenticated_for_account(0, account) and profiles.get_profile(0) == nil,
    "new match cannot inherit an old offline authentication or save")
local next_account = provider.resolve_account_id(0)
assert(next_account == account and profiles.authenticate_player(0, "new_match").ok,
    "session isolation keeps the same real player identity")
mode = "standard"
assert(profiles.load_player(0).ok)
assert(profiles.get_profile(0).save.content_inventory.offline_probe == nil,
    "each new match starts a new blank offline save")
assert(profiles.apply_snapshot(0, pure).error == "match_profile_mismatch")
assert(http_calls == 0 and file_calls == 0, "entire offline authentication/load/write path avoids network and files")
io.open = original_open

-- Existing fixture injection remains compatible; only the guarded new option
-- keeps live match scoping. A caller cannot substitute any other provider.
local forged = {provider = {}, offline_logic_test = true}
assert(not pcall(profiles.init, forged), "offline option requires the exact guarded provider")
tools = false
assert(not pcall(profiles.init, options), "a once-valid option is rejected outside Tools")
print("OFFLINE_LOGIC_TEST_PASS: explicit Tools/development opt-in, no HTTP/files, mode/session gates, blank memory profiles, local writes, next-match isolation")
