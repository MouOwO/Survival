-- Real archive event/queue, HTTP adapter, settlement reducer and unlock config.
-- The HTTP transport/database are a durable in-memory fixture, not an ECS test.
package.path = "scripts/vscripts/?.lua;" .. package.path
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local bus = require("core/event_bus")
local events = require("core/events")
local difficulty = require("config/difficulty_config")
local reducer = require("systems/archive_settlement")
local stats = require("config/generated/player_gameplay_stats")
local function empty_profile(account)
    local profile = { account_id = account, revision = 1, entitlements = {},
        save = { archive = { clear_counts = {} }, gameplay_stats = {}, content_inventory = {} } }
    for _, row in ipairs(stats.rows) do profile.save.gameplay_stats[row.field_id] = row.default_value end
    return profile
end
local accounts = { [0] = "fixture-a", [1] = "fixture-b" }
local database = { [accounts[0]] = empty_profile(accounts[0]), [accounts[1]] = empty_profile(accounts[1]) }
local received, commits, tasks, cached = {}, 0, {}, {}
local down, lose_next_response = false, false
local provider = {
    archive_enabled = function() return true end,
    resolve_account_id = function(id) return accounts[id] end,
    archive_submit = function(payload, success, failure)
        received[#received + 1] = copy(payload)
        assert(payload.command.kind == "clear" and payload.command.count == 1)
        assert(type(payload.config_hash) == "string" and #payload.config_hash > 0)
        if down then failure("backend_unavailable", 503); return end
        local stored = assert(database[payload.account_id])
        local result = reducer.settle(stored, payload.command, false)
        assert(result.ok)
        if not result.duplicate then
            stored.save.archive, stored.save.gameplay_stats = result.archive, result.gameplay_stats
            stored.revision, commits = stored.revision + 1, commits + 1
        end
        if lose_next_response then lose_next_response = false; failure("response_lost", 504); return end
        success({ ok = true, duplicate = result.duplicate, profile = copy(stored) })
    end,
}
local profile_service = {
    get_provider = function() return provider end,
    get_account_profile = function(id) return copy(cached[id]) end,
    -- Pure mode has no previous-match archive bonuses in its gameplay view.
    get_profile = function(id)
        if not cached[id] then return nil end
        return empty_profile(accounts[id])
    end,
    get_progression = function(id)
        if not cached[id] then return nil end
        return { loaded = true, clear_counts = copy(cached[id].save.archive.clear_counts) }
    end,
    apply_snapshot = function(id, profile)
        assert(profile.account_id == accounts[id], "adapter must preserve account binding")
        if cached[id] and profile.revision < cached[id].revision then
            return { ok = false, error = "snapshot_revision_stale" }
        end
        cached[id] = copy(profile)
        bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = id })
        return { ok = true }
    end,
    update_save_sections = function() error("remote clear may not write a local save") end,
}
package.loaded["systems/player_profile_service"] = profile_service
package.loaded["core/scheduler"] = {
    every = function(_, callback, key) tasks[key] = callback end,
    after = function(_, callback, key) tasks[key] = callback end,
    cancel = function(key) tasks[key] = nil end,
}
GameRules = { GetGameTime = function() return 0 end, IsCheatMode = function() return false end }
IsInToolsMode = function() return false end
CustomGameEventManager = { RegisterListener = function() end }
PlayerResource = { GetPlayer = function() return nil end,
    IsValidPlayerID = function(_, id) return accounts[id] ~= nil end }
local archive = require("systems/archive_service")
local function restart_match()
    bus.reset(); tasks = {}
    cached[0], cached[1] = copy(database[accounts[0]]), copy(database[accounts[1]])
    archive.init()
end
local function unlocked(id, level) return difficulty.is_unlocked(level, profile_service.get_progression(id)) end
restart_match()
assert(not unlocked(0, "N6") and not unlocked(1, "N6"))
-- A victory intent is not a confirmed unlock. DB outage leaves it pending.
down = true
bus.emit("archive.final_wave_cleared", { player_id = 0, difficulty_id = "N5" })
local operation = received[#received].command.id
assert(commits == 0 and not unlocked(0, "N6"))
down, lose_next_response = false, true
tasks.archive_retry()
assert(database[accounts[0]].save.archive.clear_counts.n5 == 1 and commits == 1)
assert(not unlocked(0, "N6"), "lost response cannot grant an optimistic local unlock")
tasks.archive_retry()
assert(received[#received].command.id == operation, "retry reuses match clear receipt")
assert(commits == 1 and unlocked(0, "N6") and not unlocked(0, "N7"))
assert(not unlocked(1, "N6"), "one player's clear cannot unlock another player's save")
assert(next(profile_service.get_profile(0).save.archive.clear_counts) == nil,
    "pure gameplay projection remains empty while progression is real")
bus.emit("archive.final_wave_cleared", { player_id = 0, difficulty_id = "N5" })
assert(commits == 1 and database[accounts[0]].save.archive.clear_counts.n5 == 1,
    "duplicate final-wave event does not issue another reward or clear")

-- New match/session reloads the permanent record; clear of N6 now opens N7.
restart_match()
assert(unlocked(0, "N6") and not unlocked(1, "N6"))
bus.emit("archive.final_wave_cleared", { player_id = 0, difficulty_id = "N6" })
assert(received[#received].command.id ~= operation)
assert(commits == 2 and unlocked(0, "N7") and not unlocked(0, "N8"))
assert(database[accounts[0]].save.archive.clear_counts.n5 == 1)
assert(database[accounts[0]].save.archive.clear_counts.n6 == 1)
restart_match()
assert(unlocked(0, "N7"), "second reload retains the acknowledged higher unlock")
print("PASS test_archive_difficulty_progression: offline HTTP adapter/reducer boundary")
