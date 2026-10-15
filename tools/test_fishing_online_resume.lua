package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local clock, mode, match, account, loaded_account, ready, defeated, game_state =
    0, "fishing", "fishing_resume_match", "account_a", "account_a", true, false, 5
local requests = {}
GameRules = {GetGameTime = function() return clock end, State_Get = function() return game_state end}
package.loaded["systems/match_setup_service"] = {
    get_mode = function() return mode end, get_session_id = function() return match end,
}
package.loaded["systems/startup_loading_service"] = {is_player_ready = function() return ready end}
package.loaded["systems/player_context_service"] = {is_defeated = function() return defeated end}
local provider = {
    resolve_account_id = function() return account end,
    online_checkpoint = function(payload, done, failed)
        requests[#requests + 1] = {payload = payload, done = done, failed = failed}
    end,
}
package.loaded["systems/player_profile_service"] = {
    get_provider = function() return provider end,
    is_loaded_for_account = function(_, identity) return identity == loaded_account end,
}
local online = require("systems/online_time_service")
online.init()
local function complete(index)
    assert(requests[index], "missing checkpoint " .. index).done({grants = {}})
end
local function tick(time)
    clock = time; scheduler.think()
end
assert(pcall(online.disconnect, nil), "nil disconnect must be ignored")
for _, player_id in ipairs({"invalid", -1, 0.5}) do
    assert(pcall(online.disconnect, player_id), "invalid disconnect must be ignored")
end
assert(#requests == 0, "invalid disconnect cannot issue a checkpoint")
for _, value in ipairs({"pure", "standard"}) do
    mode = value
    local ok, reason = online.resume_fishing(0)
    assert(not ok and reason == "fishing_mode_required" and #requests == 0)
end
mode = "fishing"; ready = false
assert(not online.resume_fishing(0) and #requests == 0)
ready = true; loaded_account = "wrong_account"
assert(not online.resume_fishing(0) and #requests == 0)
loaded_account = account; defeated = true
assert(not online.resume_fishing(0) and #requests == 0)
defeated = false; game_state = 8
assert(not online.resume_fishing(0) and #requests == 0)
game_state = 5
assert(online.resume_fishing(0) and #requests == 1)
local first_session = requests[1].payload.session_id
assert(online.resume_fishing(0) and #requests == 1, "duplicate connects cannot create another lease")
complete(1)
tick(60)
assert(#requests == 2 and not requests[2].payload.final)
online.disconnect(0)
assert(#requests == 2, "old active checkpoint completes before its final request")
assert(online.resume_fishing(0))
assert(online.resume_fishing(0) and #requests == 2, "in-flight finalization coalesces reconnects")
complete(2)
assert(#requests == 3 and requests[3].payload.final and requests[3].payload.session_id == first_session)
assert(online.resume_fishing(0) and #requests == 3, "final HTTP in flight still owns the old lease")
complete(3)
assert(#requests == 4 and not requests[4].payload.final)
local resumed_session = requests[4].payload.session_id
assert(resumed_session ~= first_session, "resume starts a fresh backend lease only after CLOSED")
complete(3)
assert(#requests == 4 and online.resume_fishing(0), "duplicate old final cannot close/restart the new lease")
complete(4)
tick(120)
assert(#requests == 5 and requests[5].payload.session_id == resumed_session and not requests[5].payload.final)
online.disconnect(0); assert(online.resume_fishing(0)); online.disconnect(0)
complete(5)
assert(#requests == 6 and requests[6].payload.final)
complete(6); tick(180)
assert(#requests == 6, "a second disconnect cancels the pending resume")

assert(online.resume_fishing(0)); complete(7); tick(240)
online.disconnect(0); assert(online.resume_fishing(0))
account, loaded_account = "account_b", "account_b"
complete(8)
assert(#requests == 9 and requests[9].payload.final and requests[9].payload.account_id == "account_a",
    "old final remains bound to its original account even after slot identity changes")
complete(9)
assert(#requests == 9, "queued resume cannot transfer to a different loaded account")
account, loaded_account = "account_a", "account_a"
assert(online.resume_fishing(0))
online.disconnect(0); assert(online.resume_fishing(0)); online.finish("game_end")
complete(10)
assert(#requests == 11 and requests[11].payload.final)
complete(11)
assert(#requests == 11 and not online.resume_fishing(0), "game finish blocks late reconnect resurrection")

online.init()
assert(online.resume_fishing(0))
online.disconnect(0); assert(online.resume_fishing(0))
online.init()
complete(12)
assert(#requests == 12, "an old generation cannot issue a final request or revive its pending resume")
assert(online.resume_fishing(0) and #requests == 13)
complete(13); online.disconnect(0); assert(online.resume_fishing(0))
ready = false
complete(14)
assert(#requests == 14, "ready/account gate is checked again when the old final completes")
ready = true
assert(online.resume_fishing(0)); complete(15)
online.disconnect(0); assert(online.resume_fishing(0)); game_state = 8
complete(16)
assert(#requests == 16 and not online.resume_fishing(0), "POST_GAME blocks queued and direct restarts")
assert(scheduler.task_count() == 1, "resume reuses the existing minute heartbeat without a new polling timer")

-- Ordinary modes retain the original HERO_READY start path.
game_state = 5; mode = "pure"; online.init()
bus.emit(events.HERO_READY, {player_id = 0})
assert(#requests == 17 and not requests[17].payload.final)
bus.emit(events.HERO_READY, {player_id = 0})
assert(#requests == 17)
complete(17)
print("FISHING_ONLINE_RESUME_PASS: ready/account/mode gates, duplicate connects, in-flight active/final ordering, old final isolation, queued disconnect/finish/reset, original account, post-game and ordinary HERO_READY")
