-- Lua 5.1 simulation: production wave/archival services and real CSV-generated rules.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local clock, engine_state = 0, 7
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_GAMERULES_STATE_POST_GAME = 8
Vector = function(x, y, z) return { x = x, y = y, z = z } end
local scheduled, winners, finalized, created, granted, archive_clears
local active_players, markers_ready, reward_pending, last_projection, defeated, personal_finalized
local serial, state_listener = 0, nil
local noop = function() end
local function marker(id)
    return { IsNull = function() return false end,
        GetAbsOrigin = function() return Vector(id * 1000, 20, 30) end }
end
local function unit(name)
    serial = serial + 1
    local result = { id = serial, name = name, abilities = {}, alive = true }
    function result:IsNull() return self.removed == true end
    function result:IsAlive() return self.alive end
    function result:entindex() return self.id end
    function result:SetControllableByPlayer(id) self.owner = id end
    function result:FindAbilityByName(key) return self.abilities[key] end
    function result:AddAbility(key)
        local ability = { owner = self, name = key }
        function ability:IsNull() return false end
        function ability:SetLevel(value) self.level = value end
        function ability:SetActivated(value) self.activated = value end
        function ability:GetCaster() return self.owner end
        function ability:GetAbilityName() return self.name end
        function ability:StartCooldown(value) self.cooldown = value end
        ability.EndCooldown = noop
        self.abilities[key] = ability
        return ability
    end
    for _, method in ipairs({ "SetModel", "SetOriginalModel", "SetModelScale",
        "AddNewModifier", "SetDeathXP", "SetMinimumGoldBounty",
        "SetMaximumGoldBounty", "SetBaseMagicalResistanceValue", "SetBaseMaxHealth",
        "SetMaxHealth", "SetHealth", "SetBaseDamageMin", "SetBaseDamageMax",
        "SetPhysicalArmorBaseValue", "SetBaseMoveSpeed", "SetBaseAttackTime",
        "Script_SetAttackRange", "SetAttackCapability" }) do result[method] = noop end
    result.HasModifier = function() return false end
    result.FindModifierByName = function() return nil end
    return result
end
GameRules = {
    GetGameTime = function() return clock end,
    State_Get = function() return engine_state end,
    SetGameWinner = function(_, team) winners[#winners + 1] = team; engine_state = 8 end,
}
Entities = { FindByName = function(_, _, name)
    if markers_ready then return marker(tonumber(name:match("player_(%d+)")) or 0) end
end }
GetGroundPosition = function(position) return position end
CreateUnitByName = function(name)
    local value = unit(name); created[#created + 1] = value; return value
end
UTIL_Remove = function(value) value.removed = true end
GetGroundHeight = function() return 0 end
FindClearSpaceForUnit = noop
ListenToGameEvent = function(_, callback) state_listener = callback; return 1 end
StopListeningToGameEvent = noop
package.loaded["core/scheduler"] = {
    every = function(_, callback, key) scheduled[key] = callback end,
    after = function(_, callback, key) scheduled[key or (#scheduled + 1)] = callback end,
    cancel = function(key) scheduled[key] = nil end,
    task_count = function() return 0 end,
}
for _, name in ipairs({ "systems/asset_preload_service", "config/asset_catalog",
    "config/monster_visual_config", "systems/monster_hull_scale",
    "systems/monster_navigation_policy", "systems/monster_corpse_lifecycle_service",
    "systems/wave_monster_collision" }) do package.loaded[name] = {} end
package.loaded["config/monster_visual_config"] = { resolve = function() return nil end }
package.loaded["core/team_alignment"] = { enforce = noop }
package.loaded["systems/monster_navigation_policy"] = { apply = noop }
package.loaded["systems/monster_corpse_lifecycle_service"] = { track = noop }
package.loaded["systems/monster_hull_scale"] = { apply = function() return true end }
package.loaded["systems/wave_monster_collision"] = { profile = function()
    return { base_hull_radius = 32, movement_type = "ground", no_unit_collision = false }
end }
package.loaded["systems/monster_visual_service"] = { cleanup = noop }
package.loaded["systems/monster_hero_visual_service"] = { on_death = noop, clear = noop }
package.loaded["systems/monster_spawn_marker"] = { find = function()
    return markers_ready and marker(0) or nil
end }
package.loaded["systems/player_context_service"] = {
    active_player_ids = function() return active_players end,
    slot = function(id) return { wave_spawn_marker = "player_" .. id } end,
    register_unit = function(id, value) value.owner = id end,
    unregister_unit = noop,
    unregister_player = noop,
    owner_player_id = function(value) return value.owner end,
}
package.loaded["systems/match_setup_service"] = {
    is_mode_selected = function() return true end, get_mode = function() return "standard" end,
    selector_player_id = function() return 0 end,
}
package.loaded["systems/player_profile_service"] = {
    get_progression = function() return { loaded = true, clear_counts = {} } end,
}
package.loaded["systems/startup_loading_service"] = { is_gameplay_ready = function() return true end }
package.loaded["systems/online_time_service"] = { disconnect = function(id) personal_finalized[#personal_finalized + 1] = id end, finish = function(reason)
    finalized[#finalized + 1] = reason
end }
package.loaded["systems/archive_endless_service"] = { init = noop, cancel = noop,
    is_running = function() return false end }
package.loaded["systems/archive_endless_config"] = { group = function() return {} end }
package.loaded["systems/archive_service"] = {
    has_pending = function(id) return reward_pending[id] == true end,
    record_challenge = function(id, challenge, sequence, difficulty)
        granted[#granted + 1] = { id = id, challenge = challenge, difficulty = difficulty }
        reward_pending[id] = true
    end,
}
local multiplayer = require("systems/multiplayer_player_service")
local wave = require("systems/wave_system")
local archive = require("systems/archive_challenge_service")
wave.spawn_challenge_monster = function() return unit("archive_boss") end
local function upvalue(wanted)
    local seen = {}
    local function visit(fn)
        if type(fn) ~= "function" or seen[fn] then return nil end
        seen[fn] = true
        for index = 1, math.huge do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if name == wanted then return value end
            if type(value) == "function" then
                local found = visit(value)
                if found ~= nil then return found end
            end
        end
    end
    for _, fn in pairs(wave) do
        local found = visit(fn)
        if found ~= nil then return found end
    end
    error("missing wave fixture: " .. wanted)
end
local function restart(difficulty, without_archive, players)
    clock, engine_state, serial = 0, 7, 0
    scheduled, winners, finalized, created, granted, archive_clears = {}, {}, {}, {}, {}, {}
    active_players, markers_ready, reward_pending = players or {0, 1}, true, {}
    defeated, last_projection, personal_finalized = {}, nil, {}
    multiplayer._reset_for_test()
    for _, id in ipairs(active_players) do multiplayer.mark_connected(id) end
    bus.reset()
    -- Match the addon listener: a personal loss must not end remaining players.
    bus.subscribe(events.PLAYER_DEFEATED, function(payload)
        defeated[#defeated + 1] = payload
        if multiplayer.all_participants_defeated() then
            require("systems/online_time_service").finish("all_players_defeated")
            GameRules:SetGameWinner(DOTA_TEAM_BADGUYS)
        end
    end)
    wave.init()
    if not without_archive then archive.init() end
    bus.subscribe(events.WAVE_CHANGED, function(payload) last_projection = payload end)
    bus.subscribe("archive.final_wave_cleared", function(payload)
        archive_clears[#archive_clears + 1] = payload.player_id
    end)
    assert(wave.set_difficulty(difficulty or "N1"))
    return upvalue("state"), upvalue("enemies")
end
local publish, final_check = upvalue("publish"), upvalue("check_final_victory")
local function snapshot(player)
    local payload = player ~= nil and { player_id = player } or {}
    return bus.request(events.WAVE_STATE_GET_REQUEST, payload)
end
local function tick(at, player)
    clock = at
    local key = "wave_monster_overflow:" .. player
    assert(scheduled[key], "overflow timer must exist for player " .. player)()
end
local function prepare_lanes()
    upvalue("rebuild_wave_channels")()
end
local function spawn_lane(player, count, boss)
    local state, channel = upvalue("state"), upvalue("wave_channels")[player]
    assert(channel, "expected active wave lane for player " .. player)
    local result = {}
    local row = { archetype_id = "humanoid_white_melee", member_role = boss and "assault_boss" or "normal",
        health = 200, attack = 2, attack_speed = 1 }
    state.pending = state.pending + count
    for index = 1, count do
        local before = #created
        upvalue("spawn_one")(row, upvalue("generation_token"), state.total_waves, index, nil, channel)
        assert(#created == before + 1, "real wave spawning must create a registered enemy")
        result[#result + 1] = created[#created]
    end
    return result
end
local function kill(value)
    value.alive = false
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = value, victim_entindex = value:entindex() })
end
local function final_ready(state)
    state.current_wave = state.total_waves
    state.pending, state.failed_spawn = 0, 0
    state.final_wave_generation_completed = true
end

-- The real rules admit N1/N2 but retain individual challenge difficulty gates.
for _, difficulty in ipairs({"N1", "N2", "N3"}) do
    local state, enemies = restart(difficulty)
    prepare_lanes()
    local boss, tail = spawn_lane(0, 1, true)[1], spawn_lane(1, 1)[1]
    final_ready(state)
    state.final_wave_generation_completed, state.pending = false, 1
    kill(boss)
    assert(state.alive == 1 and not state.victory_settled and #created == 2)
    state.pending, state.final_wave_generation_completed = 0, true
    final_check()
    assert(not state.victory_settled, "all lanes and surviving earlier-wave units must clear")
    kill(tail)
    assert(state.victory_settled and state.status == "archive_challenges")
    assert(#winners == 0 and #created == 8 and #archive_clears == 2)
    final_check()
    assert(#created == 8 and #archive_clears == 2, "handoff/rewards must be idempotent")
    local players = archive._test.players()
    local hero_hub = players[1].hubs[3]
    local beast = hero_hub:FindAbilityByName("ability_archive_social_beast")
    assert(beast.activated == true)
    assert(players[0].hubs[1]:FindAbilityByName("ability_archive_shadow_1").activated == true)
    assert(players[0].hubs[1]:FindAbilityByName("ability_archive_shadow_3").activated == (difficulty == "N3"))
    reward_pending[0] = true
    assert(not archive.finish(players[0].hubs[3]) and #winners == 0)
    reward_pending[0] = false
    assert(archive.finish(players[0].hubs[3]) and #winners == 0,
        "one player finishing must not end another player's challenge phase")
    assert(archive.summon(hero_hub, "social_beast", beast))
    local challenge_boss = players[1].active_boss
    kill(challenge_boss)
    kill(challenge_boss)
    assert(#granted == 1 and granted[1].challenge == "social_beast")
    assert(not archive.finish(hero_hub) and #winners == 0, "pending rewards delay final exit")
    reward_pending[1] = false
    assert(archive.finish(hero_hub) and #winners == 1 and winners[1] == DOTA_TEAM_GOODGUYS)
end

-- Missing handler/assets/markers keep the game alive and retry, never show native victory.
local state = restart("N1", true)
final_ready(state)
final_check()
assert(state.status == "archive_challenges_pending" and #winners == 0)
archive.init()
assert(scheduled.archive_challenge_begin_retry() == false)
assert(state.status == "archive_challenges" and #created == 6 and #archive_clears == 2)
state = restart("N1")
markers_ready = false
final_ready(state)
final_check()
assert(state.status == "archive_challenges" and #created == 0 and #winners == 0)
markers_ready = true
for id = 0, 1 do assert(scheduled["archive_hubs_retry:" .. id]() == false) end
assert(#created == 6)

-- All four players have independent capacity: combined population is not a cap.
local enemies
state, enemies = restart("N1", false, {0, 1, 2, 3})
prepare_lanes()
local lanes = {}
for id = 0, 3 do
    lanes[id] = spawn_lane(id, 80)
    local own = snapshot(id)
    assert(own.alive == 80 and own.alive_limit == 90 and not own.overflow_active)
    assert(scheduled["wave_monster_overflow:" .. id] == nil)
end
assert(state.alive == 320 and state.spawned == 320 and state.pending == 0)
assert(snapshot().alive == 320 and not snapshot().overflow_active,
    "no-argument business snapshots preserve the global count without a global overflow timer")
assert(last_projection.alive == 320)
local lane_counts = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
for _, meta in pairs(enemies) do lane_counts[meta.player_id] = lane_counts[meta.player_id] + 1 end
for id = 0, 3 do assert(lane_counts[id] == 80) end

-- The 91st enemy starts only its owner's ten seconds. Each deadline is independent.
spawn_lane(0, 10)
assert(snapshot(0).alive == 90 and not snapshot(0).overflow_active)
local extra_zero = spawn_lane(0, 1)
assert(snapshot(0).alive == 91 and snapshot(0).overflow_remaining == 10)
assert(snapshot(0).overflow_active and not snapshot(1).overflow_active)
assert(not snapshot(2).overflow_active and not snapshot(3).overflow_active)
clock = 2
spawn_lane(1, 11)
assert(snapshot(1).overflow_active and snapshot(1).overflow_remaining == 10)
tick(3.2, 0)
assert(snapshot(0).overflow_remaining == 7 and snapshot(1).overflow_remaining == 9,
    "a later owner's timer must not inherit the first owner's deadline")
kill(lanes[2][1])
assert(snapshot(2).alive == 79 and snapshot(0).overflow_active and snapshot(1).overflow_active,
    "another player's death must not cancel a player's overflow")
local unrelated = unit("practice_or_archive_monster")
local before = snapshot().alive
kill(unrelated)
assert(snapshot().alive == before and snapshot(0).overflow_remaining == 7,
    "independent challenge monsters do not enter assault-wave population")
clock = 4
local extra = spawn_lane(0, 5)
assert(snapshot(0).alive == 96 and snapshot(0).overflow_remaining == 6,
    "additional spawns must not restart the warning")
clock = 5
for _, value in ipairs(extra) do kill(value) end
kill(extra_zero[1])
assert(snapshot(0).alive == 90 and not snapshot(0).overflow_active)
assert(snapshot(0).overflow_remaining == 0 and scheduled["wave_monster_overflow:0"] == nil)
assert(snapshot(1).overflow_active and snapshot(1).overflow_remaining == 7)
kill(extra_zero[1])
assert(snapshot(0).alive == 90, "a duplicate death cannot lower the count again")
clock = 7
spawn_lane(0, 1)
assert(snapshot(0).overflow_remaining == 10 and snapshot(1).overflow_remaining == 5,
    "a recovered lane starts a fresh warning without resetting another player")
active_players = {0, 2, 3}
bus.emit(events.PLAYER_DISCONNECTED, { player_id = 1 })
assert(snapshot(1).alive == 0 and not snapshot(1).overflow_active)
assert(scheduled["wave_monster_overflow:1"] == nil and upvalue("wave_channels")[1] == nil)
assert(snapshot(0).alive == 91 and snapshot(0).overflow_remaining == 10)
assert(snapshot().alive == 250 and #winners == 0,
    "disconnect removes only the disconnected lane's registered enemies")

-- A personal deadline defeats only that player. Other players keep their channels and timers.
state = restart("N1", false, {0, 1, 2, 3})
prepare_lanes()
local old_zero_channel = upvalue("wave_channels")[0]
spawn_lane(0, 91)
clock = 2
spawn_lane(2, 91)
tick(9.99, 0)
assert(snapshot(0).overflow_remaining == 1 and #defeated == 0)
tick(10, 0)
assert(#defeated == 1 and defeated[1].player_id == 0 and defeated[1].reason == "monster_limit_exceeded")
assert(#personal_finalized == 1 and personal_finalized[1] == 0 and #finalized == 0,
    "personal defeat finalizes only the defeated player online session")
assert(snapshot(0).player_defeated and snapshot(0).defeat_reason == "monster_limit_exceeded")
assert(snapshot(0).alive == 0 and not snapshot(0).overflow_active)
assert(upvalue("wave_channels")[0] == nil and scheduled["wave_monster_overflow:0"] == nil)
assert(not state.defeat_settled and not state.post_clear_frozen and #winners == 0)
assert(snapshot(2).alive == 91 and snapshot(2).overflow_remaining == 2)
assert(snapshot().alive == 91, "personal cleanup must leave the other lane intact")
local produced = #created
state.pending = state.pending + 1
upvalue("spawn_one")({archetype_id="humanoid_white_melee", health=200, attack=2},
    upvalue("generation_token"), 1, 1, nil, old_zero_channel)
assert(#created == produced, "a queued spawn cannot resurrect a defeated player's channel")
spawn_lane(1, 91)
assert(snapshot(1).alive == 91 and snapshot(1).overflow_remaining == 10,
    "surviving players must continue real generation after another player's defeat")
tick(12, 2)
assert(#defeated == 2 and snapshot(2).player_defeated and #winners == 0)
assert(snapshot(1).alive == 91 and snapshot(1).overflow_remaining == 8)
spawn_lane(3, 91)
tick(20, 1)
assert(#defeated == 3 and #winners == 0 and not state.defeat_settled)
tick(22, 3)
assert(#defeated == 4 and state.defeat_settled and state.status == "defeat")
assert(#winners == 1 and winners[1] == DOTA_TEAM_BADGUYS)
assert(#finalized == 1 and finalized[1] == "all_players_defeated")
for id = 0, 3 do assert(scheduled["wave_monster_overflow:" .. id] == nil) end
final_ready(state)
final_check()
bus.emit(events.WAVE_START_NEXT, {})
publish("after_defeat")
assert(#winners == 1 and #archive_clears == 0 and #defeated == 4,
    "all-player defeat cannot reverse into archive victory or restart waves")

-- Simultaneous deadlines must settle every expired player before global final-wave handoff.
state = restart("N1", false, {0, 1, 2, 3})
prepare_lanes()
for id = 0, 3 do spawn_lane(id, 91) end
final_ready(state)
tick(10, 0)
assert(#defeated == 4 and #personal_finalized == 4)
assert(state.defeat_settled and not state.victory_settled and #archive_clears == 0)
assert(snapshot().alive == 0 and #winners == 1 and winners[1] == DOTA_TEAM_BADGUYS)
assert(#finalized == 1 and finalized[1] == "all_players_defeated")
for id = 0, 3 do
    bus.emit(events.PLAYER_DISCONNECTED, { player_id = id, defeat_cleanup = true })
    assert(snapshot(id).alive == 0 and snapshot(id).player_defeated)
    assert(scheduled["wave_monster_overflow:" .. id] == nil)
end
assert(#personal_finalized == 4 and #winners == 1 and #archive_clears == 0,
    "duplicate disconnect cleanup after simultaneous defeat must remain idempotent")
-- A defeated lane does not block surviving players from clearing the final wave.
state = restart("N1", false, {0, 1})
prepare_lanes()
spawn_lane(0, 91)
local surviving_tail = spawn_lane(1, 1)[1]
tick(10, 0)
assert(snapshot(0).player_defeated and snapshot().alive == 1 and #winners == 0)
final_ready(state)
final_check()
assert(not state.victory_settled, "the surviving player's last enemy still gates global completion")
kill(surviving_tail)
assert(state.status == "archive_challenges" and state.victory_settled and #winners == 0)
local surviving_challenges = archive._test.players()
assert(surviving_challenges[0] == nil and surviving_challenges[1] ~= nil,
    "final challenge handoff must exclude the defeated player")
assert(#archive_clears == 1 and archive_clears[1] == 1)
assert(archive.finish(surviving_challenges[1].hubs[3]))
assert(#winners == 1 and winners[1] == DOTA_TEAM_GOODGUYS)
-- Expiring inside other scheduler callbacks must not resurrect tasks after the last player's loss.
state = restart("N1", false, {0})
prepare_lanes()
upvalue("start_countdown")(60)
spawn_lane(0, 91)
clock = 10
assert(scheduled.wave_countdown() == false)
assert(state.status == "defeat" and scheduled.wave_countdown == nil and #winners == 1)
state = restart("N1", false, {0})
prepare_lanes()
spawn_lane(0, 91)
assert(upvalue("start_wave")(state.total_waves, "fixture"))
clock = 10
scheduled.wave_generation_complete()
assert(state.status == "defeat" and state.defeat_settled and #winners == 1)

-- A real death at the deadline restores that player's safe count before evaluation.
state = restart("N1", false, {0, 1})
prepare_lanes()
local victims = spawn_lane(0, 91)
clock = 10
kill(victims[1])
assert(snapshot(0).alive == 90 and not snapshot(0).overflow_active and #defeated == 0)
assert(#winners == 0)

-- Removal without a death event and forced cleanup cannot strand private counts or warnings.
state = restart("N1", false, {0, 1})
prepare_lanes()
local orphaned = spawn_lane(0, 91)
spawn_lane(1, 91)
orphaned[1].removed = true
upvalue("update_targets")()
assert(snapshot(0).alive == 90 and not snapshot(0).overflow_active)
assert(snapshot(1).alive == 91 and snapshot(1).overflow_active)
assert(snapshot().alive == 181)
assert(upvalue("clear_normal_wave_enemies")() == 181)
assert(snapshot().alive == 0 and #defeated == 0 and #archive_clears == 0)
for id = 0, 1 do
    assert(snapshot(id).alive == 0 and not snapshot(id).overflow_active)
    assert(scheduled["wave_monster_overflow:" .. id] == nil)
end
-- Terminal cleanup and reinitialization clear every independent warning.
state = restart("N1", false, {0, 1})
prepare_lanes()
spawn_lane(0, 91)
clock = 2
spawn_lane(1, 91)
engine_state = DOTA_GAMERULES_STATE_POST_GAME
state_listener()
for id = 0, 1 do
    assert(not snapshot(id).overflow_active and scheduled["wave_monster_overflow:" .. id] == nil)
end
state = restart("N1", false, {0, 1})
assert(snapshot().alive == 0)
for id = 0, 1 do assert(snapshot(id).alive == 0 and not snapshot(id).overflow_active) end
print("PASS wave population/endgame: N1/N2/N3 challenge handoff, global tail survivors, four independent lane counts/deadlines, death/disconnect recovery, personal defeat, surviving lane generation, all-player defeat once, terminal cleanup")
