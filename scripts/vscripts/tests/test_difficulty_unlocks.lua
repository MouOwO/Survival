-- Real difficulty config, wave request handler, event bus, and wave builder.
-- Engine-only spawning/rendering dependencies are not involved in selection.
package.path = "scripts/vscripts/?.lua;" .. package.path
local config = require("config/difficulty_config")
local function progression(counts) return { loaded = true, clear_counts = counts or {} } end
local fresh = progression()
for number = 1, 10 do
    assert(config.is_unlocked("N" .. number, fresh) == (number <= 5))
end
assert(not config.is_unlocked("N11", progression({ n10 = 1 })))
assert(not config.is_unlocked("n6", progression({ n5 = 1 })), "only canonical config IDs")
for previous = 5, 9 do
    local saved = progression({ ["n" .. previous] = 1 })
    assert(config.is_unlocked("N" .. (previous + 1), saved))
    if previous < 9 then assert(not config.is_unlocked("N" .. (previous + 2), saved)) end
end
for _, bad in ipairs({ 0, -1, 1.5, math.huge, "1", true, {} }) do
    assert(not config.is_unlocked("N6", progression({ n5 = bad })))
end
assert(not config.is_unlocked("N6", progression({ n5 = 0 / 0 })))
assert(not config.is_unlocked("N6", { loaded = false, clear_counts = { n5 = 1 } }))
assert(not config.is_unlocked("N10", { loaded = true, highest_difficulty = 10 }))
assert(config.client_options(fresh)[6].unlock_hint == "通关 N5 解锁")

local bus = require("core/event_bus")
local events = require("core/events")
local scheduled, published = {}, nil
package.loaded["core/scheduler"] = {
    every = function(_, callback, key) scheduled[key] = callback end,
    after = function(_, callback, key) scheduled[key or (#scheduled + 1)] = callback end,
    cancel = function(key) scheduled[key] = nil end,
}
for _, name in ipairs({
    "config/armor_balance", "systems/asset_preload_service", "config/asset_catalog",
    "config/monster_visual_config", "systems/monster_visual_service",
    "systems/monster_hero_visual_service", "systems/monster_hull_scale",
    "systems/monster_navigation_policy", "systems/monster_corpse_lifecycle_service",
    "systems/wave_monster_collision", "config/global_rules",
}) do package.loaded[name] = {} end
package.loaded["systems/monster_spawn_marker"] = { find = function() return nil end }
package.loaded["config/generated/monster_spawn_points"] = { rows = {}, by_id = {} }
package.loaded["config/generated/monster_archetypes"] = { rows = {}, by_id = {} }
package.loaded["systems/player_context_service"] = {
    active_player_ids = function() return { 0, 1 } end,
    slot = function() return {} end,
}
local mode, selector, loaded_profile = nil, 0, {}
local admitted = { [0] = true, [1] = true }
local setup = {
    get_mode = function() return mode end,
    get_session_id = function() return "test-match" end,
    is_mode_selected = function() return mode ~= nil end,
    selector_player_id = function() return selector end,
    is_selector = function(id) return id == selector end,
}
package.loaded["systems/match_setup_service"] = setup
package.loaded["systems/startup_loading_service"] = {
    is_player_ready = function(id) return admitted[id] == true end,
}
package.loaded["systems/player_profile_service"] = {
    get_progression = function(id) return loaded_profile[id] end,
    -- Pure mode may present an empty archive; permissions must not read it.
    get_profile = function() return { save = { archive = {} } } end,
}
GameRules = { GetGameTime = function() return 0 end }
local wave = require("systems/wave_system")
local function request(id, player_id, extra)
    local payload = extra or {}
    payload.difficulty_id, payload.player_id = id, player_id
    return assert(bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, payload))
end
local function snapshot() return assert(bus.request(events.WAVE_STATE_GET_REQUEST, {})) end
local function restart()
    bus.reset()
    scheduled, published = {}, nil
    wave.init()
    bus.subscribe(events.WAVE_CHANGED, function(data) published = data end)
    bus.emit(events.GAME_STARTED, {})
end

loaded_profile[0], loaded_profile[1] = fresh, progression({ n5 = 1, n9 = 1 })
restart()
assert(snapshot().status == "selecting_mode" and not snapshot().mode_selected)
assert(request("N1", 0).error == "mode_not_selected")
assert(not snapshot().difficulty_selected and scheduled.wave_countdown == nil)
mode = "standard"
wave.refresh_selection("mode_selected")
assert(published.status == "selecting_difficulty" and published.game_mode == "standard")
assert(published.selector_player_id == 0 and published.difficulty_options[6].unlocked == 0)
assert(request("N10", 1).error == "difficulty_selector_required", "other veteran cannot race host")
assert(request("N6", 0, { clear_counts = { n5 = 99 }, unlocked = 1 }).error == "difficulty_not_unlocked")
assert(request("N10", 0, { progression = loaded_profile[1] }).error == "difficulty_not_unlocked")
assert(request("N11", 0).error == "difficulty_not_found")
assert(not snapshot().difficulty_selected and scheduled.wave_countdown == nil,
    "rejected choices must not build/start a match")
admitted[0] = false
assert(request("N1", 0).error == "player_not_ready", "direct bus requests retain startup gate")
admitted[0] = true
loaded_profile[0] = nil
assert(request("N1", 0).error == "profile_not_loaded", "unknown save is never an empty successful save")
loaded_profile[0] = fresh
assert(request("N5", 0).ok)
assert(snapshot().difficulty_id == "N5" and snapshot().status == "countdown")
local countdown = scheduled.wave_countdown
assert(request("N5", 0).ok and scheduled.wave_countdown == countdown, "retry cannot restart countdown")
assert(request("N1", 0).error == "difficulty_locked")

-- An acknowledged profile refresh is the only source that unlocks the next
-- choice. A new game reads the same durable progression instead of a UI flag.
restart()
assert(snapshot().difficulty_options[6].unlocked == 0)
loaded_profile[0] = progression({ n5 = 1 })
bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = 0 })
assert(published.difficulty_options[6].unlocked == 1)
assert(published.difficulty_options[7].unlocked == 0)
mode = "pure"
wave.refresh_selection("mode_selected")
assert(request("N6", 0).ok and snapshot().game_mode == "pure",
    "pure ignores bonuses, not real progression permissions")
restart()
assert(snapshot().difficulty_options[6].unlocked == 1 and request("N6", 0).ok)

-- Permissions follow the server's chosen player, not the first loaded or most
-- advanced profile. Internal Tools callers retain their explicit debug API.
selector = 1
restart()
assert(published.selector_player_id == 1 and published.difficulty_options[10].unlocked == 1)
assert(request("N10", 0).error == "difficulty_selector_required")
assert(request("N10", 1).ok)
mode, loaded_profile[0] = nil, nil
restart()
assert(wave.set_difficulty("N10"), "existing internal Tools selection remains available")
assert(snapshot().difficulty_id == "N10")
print("PASS test_difficulty_unlocks")
