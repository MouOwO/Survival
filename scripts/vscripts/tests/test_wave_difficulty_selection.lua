package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local every_calls = 0
local scheduler
scheduler = {
    cancel = function() end,
    after = function() end,
    every = function(_, callback)
        every_calls = every_calls + 1
        scheduler.last_countdown = callback
    end,
}

package.loaded["core/scheduler"] = scheduler
package.loaded["core/team_alignment"] = { enforce = function() end }
package.loaded["systems/monster_spawn_marker"] = { find = function() return nil end }
package.loaded["systems/asset_preload_service"] = { queue_model = function() end }
package.loaded["config/generated/monster_archetypes"] = { by_id = {} }
package.loaded["config/generated/monster_spawn_points"] = { rows = {} }

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()

local latest
event_bus.subscribe(events.WAVE_CHANGED, function(payload) latest = payload end)
package.loaded["systems/wave_system"] = nil
local wave_system = require("systems/wave_system")
wave_system.init()

assert(latest.status == "waiting", "wave system did not initialize as waiting")
assert(latest.difficulty_selected == false,
    "difficulty must not be selected during initialization")
assert(every_calls == 0, "countdown started during initialization")

event_bus.emit(events.GAME_STARTED, {})
assert(latest.status == "selecting_difficulty",
    "game start did not enter difficulty selection")
assert(every_calls == 0, "countdown started before difficulty selection")

local invalid = event_bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, {
    difficulty_id = "N3",
})
assert(invalid and invalid.ok == false, "invalid difficulty was accepted")
assert(every_calls == 0, "invalid difficulty started the countdown")

local selected = event_bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, {
    difficulty_id = "N2",
})
assert(selected and selected.ok == true, "N2 selection failed")
assert(selected.total_waves == 30, "N2 selection returned wrong wave count")
assert(latest.difficulty_id == "N2" and latest.difficulty_selected == true,
    "N2 was not published as selected")
assert(latest.status == "countdown", "N2 did not start the countdown")
assert(every_calls == 1, "N2 must start exactly one countdown")

local repeated = event_bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, {
    difficulty_id = "N2",
})
assert(repeated and repeated.ok == true, "same difficulty retry is not idempotent")
assert(every_calls == 1, "same difficulty retry restarted the countdown")

local changed = event_bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, {
    difficulty_id = "N1",
})
assert(changed and changed.ok == false and changed.error == "difficulty_locked",
    "locked difficulty could be changed")
assert(every_calls == 1, "rejected difficulty change restarted countdown")

print("WAVE_DIFFICULTY_SELECTION_PASS")