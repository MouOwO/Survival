package.path = "scripts/vscripts/?.lua;" .. package.path

local bus = require("core/event_bus")
local events = require("core/events")
local tasks, requests, warnings = {}, {}, {}
local game_time = 0
local valid_players = { [0] = true }
package.loaded["core/scheduler"] = {
    every = function(_, callback, key) tasks[key] = callback end,
}
package.loaded["core/logger"] = {
    info = function() end,
    warn = function(_, message) warnings[#warnings + 1] = message end,
}
package.loaded["systems/player_entitlement_service"] = {
    replace_all = function() end,
}
GameRules = {
    GetGameTime = function() return game_time end,
    GetGameModeEntity = function() return {} end,
}
PlayerResource = {
    IsValidPlayerID = function(_, id) return valid_players[id] == true end,
    GetSteamAccountID = function(_, id) return 1000 + id end,
}
local provider = {
    init = function() end,
    resolve_account_id = function(id) return tostring(1000 + id) end,
    fetch_snapshot = function(account_id, success, failure)
        requests[#requests + 1] = { account_id = account_id, success = success, failure = failure }
    end,
}
local profiles = require("systems/player_profile_service")
profiles.init({ provider = provider })
local tick = assert(tasks.http_profile_preload)
local function snapshot(account_id, revision)
    return { schema_version = 1, account_id = account_id, revision = revision,
        entitlements = {}, achievements = {}, public = {},
        save = { gameplay_stats = {}, content_inventory = { permanent_item = 1 } } }
end

-- HERO_READY replaces a still-pending preload. A failed replacement must not
-- permanently pin the preloader's previous loading flag.
tick()
assert(#requests == 1, "preload begins exactly one request")
tick()
assert(#requests == 1, "preload does not overlap its own request")
bus.emit(events.HERO_READY, { player_id = 0 })
assert(#requests == 2, "hero initialization may replace the preload")
requests[2].failure("http_status_0")
assert(profiles.get_profile(0) == nil, "network failure must not fabricate a profile")
tick()
assert(#requests == 3, "failed replacement leaves preload free to retry")
requests[1].success(snapshot("1000", 99))
assert(profiles.get_profile(0) == nil, "superseded reply must not install a profile")
tick()
assert(#requests == 3, "superseded reply must not clear the current pending request")
requests[3].failure("database_unavailable")
game_time = 4
tick()
assert(#requests == 3, "preload failure retains the five-game-second cooldown")
game_time = 5
tick()
assert(#requests == 4, "retry runs after the cooldown")
requests[4].success(snapshot("1000", 4))
local loaded = assert(profiles.get_profile(0))
assert(loaded.revision == 4 and loaded.save.content_inventory.permanent_item == 1)
requests[1].failure("late_failure")
game_time = 20
tick()
assert(#requests == 4 and profiles.get_profile(0).revision == 4,
    "stale failures and preload ticks never clear a successfully loaded profile")

-- A wrong-account reply is rejected and settles the preload attempt, rather
-- than leaving the in-flight flag stuck forever.
valid_players[1] = true
tick()
assert(#requests == 5 and requests[5].account_id == "1001")
requests[5].success(snapshot("somebody-else", 1))
assert(profiles.get_profile(1) == nil, "wrong-account snapshot remains rejected")
game_time = 24
tick()
assert(#requests == 5, "mismatched account completes through the error cooldown")
game_time = 25
tick()
assert(#requests == 6, "mismatched account no longer permanently blocks retry")
requests[6].success(snapshot("1001", 1))
assert(profiles.get_profile(1).revision == 1 and profiles.get_profile(0).revision == 4)

-- An explicit authentication-recovery request can supersede preload too.
valid_players[2] = true
tick()
assert(#requests == 7)
profiles.load_player(2, "ecs_test_auth_ready")
assert(#requests == 8)
requests[8].failure("unauthorized")
tick()
assert(#requests == 9, "explicit failed retry does not strand the preload")
requests[7].failure("late_failure")
tick()
assert(#requests == 9, "old explicit-retry callbacks do not unlock the current request")
requests[9].success(snapshot("1002", 1))
assert(profiles.get_profile(2).revision == 1)

-- Missing authentication fails synchronously. Once authentication is restored,
-- the normal retry path must run without resetting the profile service.
local deferred_fetch = provider.fetch_snapshot
local missing_token_calls = 0
provider.fetch_snapshot = function(_, _, failure)
    missing_token_calls = missing_token_calls + 1
    failure("fishing_api_token_missing")
end
valid_players[3] = true
tick()
assert(missing_token_calls == 1 and profiles.get_profile(3) == nil)
provider.fetch_snapshot = deferred_fetch
game_time = 29
tick()
assert(#requests == 9, "authentication failures also obey the retry cooldown")
game_time = 30
tick()
assert(#requests == 10, "restored authentication can load via the existing preloader")
requests[10].success(snapshot("1003", 1))
assert(profiles.get_profile(3).revision == 1)
assert(profiles.is_loaded_for_account(3, "1003"))
assert(not profiles.is_loaded_for_account(3, "1000"))
assert(not profiles.is_loaded_for_account(17, "1003"))

print("PLAYER_PROFILE_LOAD_RETRY_PASS: superseded requests, auth recovery, failure cooldown, account isolation, loaded-profile preservation")
