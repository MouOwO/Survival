-- Real difficulty config, wave request handler, event bus, and wave builder.
-- Engine-only spawning/rendering dependencies are not involved in selection.
package.path = "scripts/vscripts/?.lua;" .. package.path
local release = require("config/mode_release_config")
release.all_difficulties_unlocked = false
local config = require("config/difficulty_config")
local function progression(counts)
    local values = {}; for key,value in pairs(counts or {}) do values[key]=value end
    return {loaded=true, clear_counts=counts or {}, standard_clear_counts=values, mode_clear_counts={pure={}}}
end
local fresh = progression()
for number = 1, 10 do
    assert(config.is_unlocked("N" .. number, fresh) == (number <= 4))
end
assert(not config.is_unlocked("N11", progression({ n10 = 1 })))
assert(not config.is_unlocked("n6", progression({ n5 = 1 })), "only canonical config IDs")
for previous = 4, 9 do
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
assert(config.client_options(fresh)[5].unlock_hint == "通关 N4 解锁")
local progression_rules = require("config/mode_progression")
local entry_required={rich=3,cold=5,scourge=9,ruins=9,celestial=11}
local maximum={standard=10,pure=10,rich=30,cold=50,scourge=50,ruins=50,celestial=35}
for mode_id,required in pairs(entry_required) do
    local progress = {loaded=true, mode_id=mode_id, clear_counts={n4=99,n5=99,n9=99,n10=99},
        standard_clear_counts={}, mode_clear_counts={pure={}}, rich_clear_counts={},
        cold_clear_counts={}, scourge_clear_counts={}, ruins_clear_counts={}, celestial_clear_counts={}}
    local own_field = progression_rules.clear_field(mode_id)
    assert(not config.is_unlocked("N1", progress), "advanced N1 still requires an authenticated exact entry clear")
    assert(config.client_options(progress)[1].unlock_hint == progression_rules.entry_hint(mode_id))
    local donor=required<=10 and progress.standard_clear_counts or progress.cold_clear_counts
    donor["n"..required] = 1
    local options=config.client_options(progress)
    assert(#options==maximum[mode_id] and config.get("N"..maximum[mode_id],mode_id))
    assert(not config.get("N"..(maximum[mode_id]+1),mode_id))
    for number = 1, maximum[mode_id] do
        assert(config.is_unlocked("N" .. number, progress) == (number <= 4),
            "only the initial four levels open on mode entry")
    end
    assert(config.client_options(progress)[5].unlock_hint == progression_rules.difficulty_hint(mode_id, "N5"))
    progress[own_field].n4 = 1
    assert(config.is_unlocked("N5",progress) and not config.is_unlocked("N6",progress))
    assert(config.client_options(progress)[6].unlock_hint == progression_rules.difficulty_hint(mode_id, "N6"))
    progress[own_field].n5 = 1
    assert(config.is_unlocked("N6",progress) and not config.is_unlocked("N10",progress),"own N5 unlocks N6 only")
    progress[own_field].n9=1
    assert(config.is_unlocked("N10",progress))
    for _, invalid in ipairs({true, "1", -1, 0.5, math.huge}) do
        progress[own_field].n9 = invalid
        assert(not config.is_unlocked("N10", progress), "invalid or cross-mode counts cannot unlock the next tier")
    end
    progress[own_field].n9 = 1
    progress.mode_id = "standard"
    assert(config.is_unlocked("N10", progress, mode_id), "the server-supplied mode overrides a legacy profile projection")
    donor["n"..required] = 0
    -- Remove the mode's own entry-sized counter if this test populated it
    -- while checking later tiers; other-mode summaries still cannot qualify.
    progress[own_field]["n"..required]=nil
    assert(not config.is_unlocked("N1", progress, mode_id))
end

-- This offline fixture authenticates only its two roster players; the real
-- event bus still enforces that admission before invoking wave permissions.
package.loaded["core/test_access_policy"] = {
    enabled=function() return true end,
    enforce=function(id) return id==0 or id==1 end,
}
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
local gameplay_ready = true
local setup = {
    get_mode = function() return mode end,
    get_session_id = function() return "test-match" end,
    is_mode_selected = function() return mode ~= nil end,
    selector_player_id = function() return selector end,
    is_selector = function(id) return id == selector end,
}
package.loaded["systems/match_setup_service"] = setup
package.loaded["systems/startup_loading_service"] = {
    is_player_ready = function(id) return gameplay_ready and admitted[id] == true end,
    is_difficulty_selection_ready = function(id) return admitted[id] == true end,
    selection_player_ids = function() return { 0, 1 } end,
}
package.loaded["systems/player_profile_service"] = {
    get_progression = function(id) return loaded_profile[id] end,
    -- Pure mode may present an empty archive; permissions must not read it.
    get_profile = function() return { save = { archive = {} } } end,
}
GameRules = { GetGameTime = function() return 0 end }
local builder = require("systems/wave_difficulty_builder")
local original_build, last_build = builder.build, nil
builder.build = function(...)
    local built, reason = original_build(...)
    last_build = built
    return built, reason
end
local wave = require("systems/wave_system")
local function request(id, player_id, extra)
    local payload = extra or {}
    payload.difficulty_id, payload.player_id = id, player_id
    return assert(bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, payload))
end
local function snapshot() return assert(bus.request(events.WAVE_STATE_GET_REQUEST, {})) end
local function restart(before_gameplay)
    bus.reset()
    scheduled, published = {}, nil
    wave.init()
    bus.subscribe(events.WAVE_CHANGED, function(data) published = data end)
    if not before_gameplay then bus.emit(events.GAME_STARTED, {}) end
end

loaded_profile[0], loaded_profile[1] = fresh, progression({ n4 = 1, n5 = 1, n9 = 1 })
restart()
assert(snapshot().status == "selecting_mode" and not snapshot().mode_selected)
assert(request("N1",99).error=="test_access_denied","unadmitted actors never reach difficulty selection")
assert(request("N1", 0).error == "mode_not_selected")
assert(not snapshot().difficulty_selected and scheduled.wave_countdown == nil)
mode = "standard"
wave.refresh_selection("mode_selected")
assert(published.status == "selecting_difficulty" and published.game_mode == "standard")
assert(published.selector_player_id == 0 and published.difficulty_options[6].unlocked == 0)
assert(request("N10", 1).error == "difficulty_selector_required", "other veteran cannot race host")
assert(request("N6", 0, { clear_counts = { n5 = 99 }, unlocked = 1 }).error == "difficulty_not_unlocked")
assert(request("N5", 0, { clear_counts = { n4 = 99 }, unlocked = 1 }).error == "difficulty_not_unlocked")
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
loaded_profile[1] = nil
assert(request("N1", 0).error == "profile_not_loaded", "a missing non-host save also fails closed")
assert(not snapshot().difficulty_data_ready and snapshot().max_difficulty_id == "")
loaded_profile[1] = progression({ n4 = 1, n5 = 1, n9 = 1 })
assert(request("N4", 0).ok)
assert(snapshot().difficulty_id == "N4" and snapshot().status == "countdown")
local countdown = scheduled.wave_countdown
assert(request("N4", 0).ok and scheduled.wave_countdown == countdown, "retry cannot restart countdown")
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
assert(request("N6",0).error=="difficulty_not_unlocked","standard clears cannot unlock pure's later difficulties")
loaded_profile[0].mode_clear_counts.pure.n5=1
loaded_profile[1].mode_clear_counts.pure.n5=1
assert(request("N6", 0).ok and snapshot().game_mode == "pure",
    "pure ignores bonuses and reads its own authenticated progression")
restart()
assert(snapshot().difficulty_options[6].unlocked == 1 and request("N6", 0).ok)

-- Changing the host never lets a veteran bypass the least advanced teammate.
-- Even a temporarily missing active-player slot remains in the frozen roster.
mode, selector = "standard", 1
restart()
assert(published.selector_player_id == 1 and published.difficulty_options[10].unlocked == 0)
assert(published.max_difficulty_id == "N6" and published.difficulty_limit_player_ids[1] == 0)
assert(request("N10", 0).error == "difficulty_selector_required")
assert(request("N10", 1).error == "difficulty_not_unlocked")
package.loaded["systems/player_context_service"].active_player_ids = function() return { 1 } end
admitted[0] = false
wave.refresh_selection("teammate_disconnected")
assert(snapshot().difficulty_options[10].unlocked == 0,
    "disconnected low-progress teammate cannot disappear from the permission roster")
assert(request("N10", 1, { player_ids = { 1 }, progression = loaded_profile[1] }).error == "difficulty_not_unlocked")
loaded_profile[0] = nil
assert(request("N6", 1).error == "profile_not_loaded", "unknown teammate cannot raise the cap")
loaded_profile[0], admitted[0] = progression({ n5 = 1 }), true
assert(request("N6", 1).ok)

-- Every teammate can eventually unlock a higher option through real progress.
restart()
loaded_profile[0] = progression({ n5 = 1, n9 = 1 })
bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = 0 })
assert(published.difficulty_options[10].unlocked == 1 and request("N10", 1).ok)

-- Authentication is enough to record difficulty while full mode login waits.
-- The real wave controller cannot start countdown until GAME_STARTED arrives.
gameplay_ready = false
restart(true)
assert(snapshot().can_confirm_difficulty and not snapshot().game_started)
assert(request("N6", 1).ok)
assert(snapshot().difficulty_selected and snapshot().difficulty_id == "N6")
assert(wave.selection_snapshot().difficulty_selected and wave.selection_snapshot().difficulty_id == "N6",
    "loading can publish the confirmed setup without exposing a gameplay snapshot")
assert(not snapshot().game_started and snapshot().status ~= "countdown" and scheduled.wave_countdown == nil,
    "early difficulty confirmation must not start waves before the gameplay gate")
assert(request("N6", 1).ok and scheduled.wave_countdown == nil,
    "retries cannot manufacture an early gameplay start")
gameplay_ready = true
bus.emit(events.GAME_STARTED, {})
assert(snapshot().status == "countdown" and scheduled.wave_countdown ~= nil,
    "the held gameplay event starts the previously chosen difficulty exactly once")
-- Internal Tools callers retain their explicit debug API.
mode, loaded_profile[0] = nil, nil
restart()
assert(wave.set_difficulty("N10"), "existing internal Tools selection remains available")
assert(snapshot().difficulty_id == "N10")

-- Acceptance opens every configured tier, while the real request path keeps
-- authentication, fixed-roster readiness, host authority and mode admission.
release.all_difficulties_unlocked = true
selector, admitted[0], admitted[1], gameplay_ready = 0, true, true, true
local function acceptance_profile()
    local value = progression({ n3=1, n5=1 })
    value.rich_clear_counts, value.cold_clear_counts = {}, {}
    return value
end
for _, case in ipairs({{"standard",10},{"pure",10},{"rich",30},{"cold",50}}) do
    mode = case[1]
    loaded_profile[0], loaded_profile[1] = acceptance_profile(), acceptance_profile()
    restart()
    local state = snapshot()
    assert(state.difficulty_data_ready and state.difficulty_access_policy == "all_configured")
    assert(state.max_difficulty_id == "N"..case[2] and #state.difficulty_options == case[2])
    for _, option in ipairs(state.difficulty_options) do
        assert(option.unlocked == 1 and option.unlock_hint == "", "every configured tier is selectable")
    end
    assert(published.difficulty_access_policy == "all_configured",
        "wave updates publish the authoritative acceptance policy")
    assert(request("N"..case[2],1).error == "difficulty_selector_required")
    assert(request("N"..(case[2]+1),0).error == "difficulty_not_found")
    assert(request("n"..case[2],0).error == "difficulty_not_found", "IDs remain canonical")
    assert(request("N"..case[2],0).ok, "the host can request the highest tier without previous-tier clears")
    assert(snapshot().difficulty_id == "N"..case[2] and snapshot().status == "countdown")
    local rules = require("config/human_monster_rules")
    local selected, base = rules.mode(mode,"N"..case[2]), rules.wave_base(1)
    assert(last_build and last_build.mode_id == mode and last_build.difficulty.difficulty_id == "N"..case[2])
    local first = last_build.waves[1][1]
    assert(first.health == base.health * selected.hp_multiplier
        and first.war3_armor == base.war3_armor * selected.armor_multiplier,
        "the actual wave rebuild receives this mode's highest-tier HP and armor instead of a fallback")
end

mode = "cold"
restart()
admitted[0] = false
assert(request("N50",0).error == "player_not_ready")
admitted[0] = true
assert(request("N50",99).error == "test_access_denied")
loaded_profile[0] = nil
assert(request("N50",0).error == "profile_not_loaded")
loaded_profile[0] = acceptance_profile()
loaded_profile[1].loaded = false
assert(request("N50",0).error == "profile_not_loaded", "an unloaded frozen-roster teammate still blocks acceptance")
loaded_profile[1] = nil
assert(request("N50",0).error == "profile_not_loaded", "missing teammate profile is never fabricated")
loaded_profile[1] = acceptance_profile()
loaded_profile[1].cold_clear_counts = nil
assert(request("N50",0).error == "profile_not_loaded", "independent mode capability remains mandatory")
loaded_profile[1] = acceptance_profile()
loaded_profile[1].standard_clear_counts.n5 = nil
assert(request("N50",0).error == "difficulty_not_unlocked", "cold's exact mode-entry prerequisite is retained")
assert(snapshot().difficulty_options[50].unlocked == 0)
loaded_profile[1].standard_clear_counts.n5 = 1
assert(request("N50",0).ok)

mode = "rich"
loaded_profile[0], loaded_profile[1] = acceptance_profile(), acceptance_profile()
loaded_profile[1].standard_clear_counts.n3 = nil
restart()
assert(request("N30",0).error == "difficulty_not_unlocked", "rich admission is not bypassed by tier acceptance")
loaded_profile[1].standard_clear_counts.n3 = 1
assert(request("N30",0).ok)

release.all_difficulties_unlocked = false
mode = "standard"
loaded_profile[0], loaded_profile[1] = progression(), progression()
restart()
assert(snapshot().difficulty_access_policy == "progression" and snapshot().max_difficulty_id == "N4")
assert(request("N10",0).error == "difficulty_not_unlocked", "switching acceptance off restores normal tier rules")
print("PASS test_difficulty_unlocks")
