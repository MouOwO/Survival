package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
-- Fake native players below have no Steam identity. Authentication admission
-- has its own tests; this isolated fixture exercises real combat ownership.
package.loaded["core/test_access_policy"]={enabled=function() return false end,
    enforce=function() return true end,allowed=function() return true end}
-- Lua 5.1 simulation: production wave/archival services and real CSV-generated rules.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local clock, engine_state = 0, 7
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_GAMERULES_STATE_POST_GAME = 8
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3, 1, 2
DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 4, 64, 0
Vector = function(x, y, z) return { x = x, y = y, z = z } end
local scheduled, winners, finalized, created, granted, archive_clears
local active_players, markers_ready, reward_pending, last_projection, defeated, personal_finalized
local match_mode, preload_calls, scheduled_count = "standard", 0, 0
local cooperative_payloads, fake_players = {}, {}
local visual_deaths, hero_visual_deaths, visual_cleanups, boss_rewards
local death_metadata
local overflow_notices
local function active_player(id)
    for _, value in ipairs(active_players or {}) do if value==id then return true end end
    return false
end
PlayerResource = {
    IsFakeClient=function(_,id) return fake_players[id]==true end,
    IsValidPlayerID=function(_,id) return active_player(id) end,
    GetTeam=function() return DOTA_TEAM_GOODGUYS end,
    GetPlayer=function(_,id) return active_player(id) and id or nil end,
}
local serial, state_listener = 0, nil
local noop = function() end
local function marker(id)
    return { IsNull = function() return false end,
        GetAbsOrigin = function() return Vector(id * 1000, 20, 30) end }
end
local function unit(name, position)
    serial = serial + 1
    local result = { id = serial, name = name, abilities = {}, alive = true,
        position = position or Vector(0,0,30) }
    function result:IsNull() return self.removed == true end
    function result:IsAlive() return self.alive end
    function result:entindex() return self.id end
    function result:GetAbsOrigin() return self.position end
    function result:GetHullRadius() return self.name:match("^npc_archive_challenge_") and 64 or 32 end
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
CreateUnitByName = function(name, position)
    local value = unit(name, position); created[#created + 1] = value; return value
end
GridNav = {IsTraversable=function() return true end, IsBlocked=function() return false end,
    IsNearbyTree=function() return false end}
FindUnitsInRadius = function(_, position, _, radius)
    local result = {}
    for _, value in ipairs(created) do
        if not value:IsNull() and value:IsAlive() then
            local point=value:GetAbsOrigin()
            if (point.x-position.x)^2+(point.y-position.y)^2 <= radius^2 then
                result[#result+1]=value
            end
        end
    end
    return result
end
UTIL_Remove = function(value) value.removed = true end
GetGroundHeight = function() return 0 end
FindClearSpaceForUnit = noop
ListenToGameEvent = function(_, callback) state_listener = callback; return 1 end
StopListeningToGameEvent = noop
package.loaded["core/scheduler"] = {
    every = function(_, callback, key) scheduled_count = scheduled_count + 1; scheduled[key] = callback end,
    after = function(_, callback, key) scheduled_count = scheduled_count + 1; scheduled[key or (#scheduled + 1)] = callback end,
    cancel = function(key) scheduled[key] = nil end,
    task_count = function() return 0 end,
}
for _, name in ipairs({ "systems/asset_preload_service", "config/asset_catalog",
    "config/monster_visual_config", "systems/monster_hull_scale",
    "systems/monster_navigation_policy", "systems/monster_corpse_lifecycle_service",
    "systems/wave_monster_collision" }) do package.loaded[name] = {} end
package.loaded["config/monster_visual_config"] = {
    resolve = function() return nil end,
    resources_for_wave = function() preload_calls = preload_calls + 1; return {} end,
}
package.loaded["systems/asset_preload_service"] = {
    resources_for_models = function(paths)
        preload_calls = preload_calls + 1
        local resources = {}
        for _, path in ipairs(paths) do resources[#resources + 1] = { type = "model", path = path } end
        return resources
    end,
    resources_for_assets = function(_, resources) preload_calls = preload_calls + 1; return resources end,
    queue_resources = function(resources) preload_calls = preload_calls + 1; return true, "ready", #resources, 0 end,
}
package.loaded["core/team_alignment"] = { enforce = noop }
package.loaded["systems/monster_navigation_policy"] = { apply = noop }
package.loaded["systems/monster_corpse_lifecycle_service"] = { track = noop }
package.loaded["systems/monster_hull_scale"] = { apply = function() return true end }
package.loaded["systems/wave_monster_collision"] = { profile = function()
    return { base_hull_radius = 32, movement_type = "ground", no_unit_collision = false }
end }
local function record_death(records, value)
    assert(not value:IsAlive() and not value:IsNull(), "death visuals retain the native corpse")
    local meta = death_metadata(value)
    records[value] = records[value] or {}
    local row = {entindex=value:entindex(), owner=value.owner, wave=false}
    if meta then
        row.wave, row.player_id, row.wave_number = true, meta.player_id, meta.wave_number
        row.member_role, row.is_boss, row.is_final_boss = meta.member_role, meta.is_boss, meta.is_final_boss
    end
    records[value][#records[value]+1] = row
end
package.loaded["systems/monster_visual_service"] = {
    on_death=function(value) record_death(visual_deaths, value) end,
    -- Forced despawn has a distinct immediate cleanup API. Do not use it to
    -- satisfy on_death: that would mask losing the corpse's death appearance.
    cleanup=function(value) visual_cleanups[value]=(visual_cleanups[value] or 0)+1 end,
}
package.loaded["systems/monster_hero_visual_service"] = {
    on_death=function(value) record_death(hero_visual_deaths, value) end, clear=noop,
}
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
    is_mode_selected = function() return true end, get_mode = function() return match_mode end,
    selector_player_id = function() return 0 end,
    is_selector = function(id) return id == 0 end,
}
package.loaded["systems/player_profile_service"] = {
    get_progression = function() return { loaded = true, clear_counts = {} } end,
}
package.loaded["systems/startup_loading_service"] = {
    is_gameplay_ready = function() return true end,
    is_player_ready = function() return true end,
    is_difficulty_selection_ready = function() return true end,
}
package.loaded["systems/online_time_service"] = { disconnect = function(id) personal_finalized[#personal_finalized + 1] = id end, finish = function(reason)
    finalized[#finalized + 1] = reason
end }
package.loaded["systems/archive_endless_service"] = { init = noop, cancel = noop,
    is_running = function() return false end, skip_step=function() return 1 end }
package.loaded["systems/archive_endless_config"] = { group = function() return {} end }
package.loaded["systems/archive_service"] = {
    has_pending = function(id) return reward_pending[id] == true end,
    record_challenge = function(id, challenge, sequence, difficulty)
        granted[#granted + 1] = { id = id, challenge = challenge, difficulty = difficulty }
        reward_pending[id] = true
        return {ok=true}
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
local function restart(difficulty, without_archive, players, mode)
    clock, engine_state, serial = 0, 7, 0
    match_mode, preload_calls, scheduled_count = mode or "standard", 0, 0
    cooperative_payloads, fake_players = {}, {}
    scheduled, winners, finalized, created, granted, archive_clears = {}, {}, {}, {}, {}, {}
    visual_deaths, hero_visual_deaths, visual_cleanups, boss_rewards = {}, {}, {}, {}
    active_players, markers_ready, reward_pending = players or {0, 1}, true, {}
    defeated, last_projection, personal_finalized = {}, nil, {}
    overflow_notices = {}
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
    bus.subscribe(events.UI_NOTIFICATION, function(payload)
        if payload.kind == "wave_overflow_tip" then overflow_notices[#overflow_notices+1] = payload end
    end)
    wave.init()
    if not without_archive then archive.init() end
    bus.subscribe(events.WAVE_CHANGED, function(payload) last_projection = payload end)
    bus.subscribe("archive.wave_boss_killed", function(payload) boss_rewards[#boss_rewards+1]=payload end)
    bus.subscribe("archive.final_wave_cleared", function(payload)
        archive_clears[#archive_clears + 1] = payload.player_id
        cooperative_payloads[payload.player_id] = payload.cooperative_win
    end)
    if difficulty ~= false then assert(wave.set_difficulty(difficulty or "N1")) end
    return upvalue("state"), upvalue("enemies")
end
death_metadata=function(value) return upvalue("enemies")[value:entindex()] end
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
    local meta, state = death_metadata(value), upvalue("state")
    local before_alive, before_killed, before_rewards = state.alive, state.killed, #boss_rewards
    local before_visual = #(visual_deaths[value] or {})
    local before_hero_visual = #(hero_visual_deaths[value] or {})
    local before_cleanup = visual_cleanups[value] or 0
    value.alive = false
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = value, victim_entindex = value:entindex() })
    if meta then
        local rows = visual_deaths[value] or {}
        assert(#rows==before_visual+1 and #(hero_visual_deaths[value] or {})==before_hero_visual+1,
            "a registered wave death invokes each formal on_death exactly once")
        local row=rows[#rows]
        assert(row.wave and row.entindex==value:entindex() and row.player_id==meta.player_id
            and row.wave_number==meta.wave_number and row.member_role==meta.member_role and row.is_boss==meta.is_boss
            and row.is_final_boss==meta.is_final_boss, "visual death sees original wave metadata before retirement")
        assert((visual_cleanups[value] or 0)==before_cleanup and not value.removed,
            "normal death preserves the native corpse rather than immediate visual cleanup")
        assert(state.alive==before_alive-1 and state.killed==before_killed+1)
        assert(#boss_rewards==before_rewards+(meta.is_boss and 1 or 0), "boss reward publishes once for its owner")
    elseif before_visual>0 then
        assert(#(visual_deaths[value] or {})==before_visual
            and #(hero_visual_deaths[value] or {})==before_hero_visual
            and (visual_cleanups[value] or 0)==before_cleanup,
            "duplicate wave death cannot repeat appearance retirement or immediate cleanup")
        assert(state.alive==before_alive and state.killed==before_killed and #boss_rewards==before_rewards,
            "duplicate wave death cannot reduce counts or duplicate boss rewards")
    end
end
local function final_ready(state)
    -- A real final wave has prepared its lanes. The current hub contract
    -- anchors to those formal portals, not the former independent map marker.
    if next(upvalue("wave_channels"))==nil then prepare_lanes() end
    state.current_wave = state.total_waves
    state.pending, state.failed_spawn = 0, 0
    state.final_wave_generation_completed = true
end

-- The real rules admit N1/N2 but retain individual challenge difficulty gates.
local fixture_hook = rawget(_G, "SURVIVAL_WAVE_POPULATION_FIXTURE")
if fixture_hook then
    fixture_hook({bus=bus,events=events,restart=restart,prepare_lanes=prepare_lanes,upvalue=upvalue,
        final_ready=final_ready, final_check=final_check,
        set_clock=function(value) clock=value end,
        set_pending=function(id,value) reward_pending[id]=value end,
        set_fake=function(id,value) fake_players[id]=value end,
        set_active_players=function(ids) active_players=ids end,
        scheduled=function() return scheduled end,
        winners=function() return winners end,
        clears=function() return archive_clears end})
    return
end
for _, difficulty in ipairs({"N1", "N2", "N3"}) do
    local state, enemies = restart(difficulty)
    prepare_lanes()
    local boss, tail = spawn_lane(0, 1, true)[1], spawn_lane(1, 1)[1]
    final_ready(state)
    state.final_wave_generation_completed, state.pending = false, 1
    kill(boss)
    assert(state.alive == 1 and not state.victory_settled and #created == 2)
    assert(#boss_rewards==1 and boss_rewards[1].player_id==0)
    kill(boss)
    assert(state.alive==1 and state.killed==1 and #boss_rewards==1)
    state.pending, state.final_wave_generation_completed = 0, true
    final_check()
    assert(not state.victory_settled, "all lanes and surviving earlier-wave units must clear")
    kill(tail)
    assert(state.victory_settled and state.status == "archive_challenges")
    kill(tail)
    assert(#winners == 0 and #created == 10 and #archive_clears == 2)
    assert(cooperative_payloads[0] == 1 and cooperative_payloads[1] == 1, "both winning human teammates count")
    final_check()
    assert(#created == 10 and #archive_clears == 2, "handoff/rewards must be idempotent")
    local players = archive._test.players()
    for id=0,1 do assert(#players[id].hubs==4,"every winning player receives four archive hubs") end
    local beast_definition=require("config/generated/archive_challenge_definitions").by_id.social_beast
    local hero_hub = players[1].hubs[beast_definition.building_id]
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
    local challenge_group = assert(players[1].active_groups.social_beast)
    local challenge_boss = assert(challenge_group.units[next(challenge_group.units)])
    kill(challenge_boss)
    kill(challenge_boss)
    assert(#granted == 2 and granted[1].id==0 and granted[2].id==1
        and granted[1].challenge=="social_beast" and granted[2].challenge=="social_beast",
        "one challenge death awards each eligible human account once")
    assert(#(hero_visual_deaths[challenge_boss] or {})==1 and visual_deaths[challenge_boss]==nil,
        "archive boss death has one hero appearance tail and one challenge reward")
    assert(not archive.finish(hero_hub) and #winners == 0, "pending rewards delay final exit")
    reward_pending[0], reward_pending[1] = false, false
    assert(archive.finish(hero_hub) and #winners == 1 and winners[1] == DOTA_TEAM_GOODGUYS)
end

-- Early completion uses the selected difficulty's real final wave and full batches.
for difficulty_number = 1, 10 do
    local difficulty = "N" .. difficulty_number
    local last_wave = difficulty_number == 1 and 25 or 30
    local state, enemies = restart(difficulty, false, {0})
    local configured = upvalue("waves")
    assert(state.total_waves == last_wave)
    if difficulty == "N1" then assert(configured[30] == nil, "N1 must not borrow N2 wave 30") end
    assert(not bus.request(events.WAVE_EARLY_FINAL_REQUEST, {}).ok)
    bus.emit(events.GAME_STARTED, {})
    clock = 59
    assert(not bus.request(events.WAVE_EARLY_FINAL_REQUEST, {}).ok)
    state.current_wave = last_wave - 1
    local old_enemy = spawn_lane(0, 1)[1]
    clock = 60
    local result = bus.request(events.WAVE_EARLY_FINAL_REQUEST, {})
    assert(result.ok and result.final_wave == last_wave, difficulty .. " early final target")
    assert(state.current_wave == last_wave and state.total_waves == last_wave)
    assert(result.removed_normal_enemies == 1 and old_enemy.removed)
    assert(not state.victory_settled and not state.final_wave_generation_completed)
    local expected_count = 0
    for _, row in ipairs(configured[last_wave].batches) do
        expected_count = expected_count + row.monster_count
        assert(row.difficulty_id == difficulty, "must use this difficulty's final-wave stats")
    end
    assert(state.planned == expected_count)
    local callbacks = {}
    for key, callback in pairs(scheduled) do
        if type(key) == "number" then callbacks[#callbacks + 1] = callback end
    end
    for _, callback in ipairs(callbacks) do callback() end
    assert(state.spawned == expected_count and state.alive == expected_count)
    local victims, final_bosses = {}, 0
    for _, meta in pairs(enemies) do
        assert(meta.wave_number == last_wave)
        if meta.is_final_boss then final_bosses = final_bosses + 1 end
        victims[#victims + 1] = meta.unit
    end
    assert(final_bosses > 0, "early final boss must retain final-boss classification")
    scheduled.wave_generation_complete()
    assert(state.final_wave_generation_completed and not state.victory_settled)
    assert(not bus.request(events.WAVE_EARLY_FINAL_REQUEST, {}).ok)
    for index = 1, #victims - 1 do kill(victims[index]) end
    assert(not state.victory_settled, "early clear must wait for the entire final wave")
    kill(victims[#victims])
    assert(state.victory_settled and state.status == "archive_challenges")
    assert(#archive_clears == 1 and #winners == 0)
    assert(cooperative_payloads[0] == 0, "solo early final is not a cooperative win")
    final_check()
    assert(#archive_clears == 1, "early completion grants the clear only once")

    state = restart(difficulty, false, {0})
    bus.emit(events.GAME_STARTED, {})
    clock = 60
    state.current_wave = last_wave
    assert(not bus.request(events.WAVE_EARLY_FINAL_REQUEST, {}).ok)
    assert(not state.early_final_used, "cannot buy early completion once final wave has started")
end

-- Missing handler/assets/markers keep the game alive and retry, never show native victory.
local state = restart("N1", true)
final_ready(state)
final_check()
assert(state.status == "archive_challenges_pending" and #winners == 0)
archive.init()
assert(scheduled.archive_challenge_begin_retry() == false)
assert(state.status == "archive_challenges" and #created == 8 and #archive_clears == 2,
    "late archive handler must complete the pending handoff: " .. tostring(state.status)
        .. " created=" .. #created .. " clears=" .. #archive_clears)
state = restart("N1")
markers_ready = false
final_ready(state)
final_check()
assert(state.status == "archive_challenges" and #created == 0 and #winners == 0)
markers_ready = true
prepare_lanes()
for id = 0, 1 do assert(scheduled["archive_hubs_retry:" .. id]() == false) end
assert(#created == 8)

-- Every second has exactly one private center-tip; other publications cannot spam it.
state = restart("N1", true, {0, 1})
prepare_lanes()
local warned = spawn_lane(0, 91)
assert(#overflow_notices == 1 and overflow_notices[1].message == "您需在20s内清理怪物")
assert(overflow_notices[1].player_id == 0 and not snapshot(1).overflow_active)
for second = 1, 19 do
    tick(second, 0)
    assert(#defeated == 0 and #winners == 0, "no loss before twenty seconds")
    assert(#overflow_notices == second+1)
    assert(overflow_notices[#overflow_notices].message == "您需在" .. (20-second) .. "s内清理怪物")
    assert(overflow_notices[#overflow_notices].player_id == 0)
    publish("unrelated_hud_refresh")
    tick(second, 0) -- game time does not advance while paused
    assert(#overflow_notices == second+1, "duplicate publishes/paused ticks cannot duplicate tips")
end
kill(warned[1])
assert(snapshot(0).alive == 90 and snapshot(0).overflow_active, "ninety does not cancel an existing warning")
tick(20, 0)
assert(snapshot(0).player_defeated and not snapshot(1).player_defeated)
assert(#overflow_notices == 20, "expiry sends no zero/negative countdown")
assert(#winners == 0 and #defeated == 1, "only the overflowing player loses")
-- Clearing before the deadline cancels the task; subsequent overload gets a full new grace.
state = restart("N1", true, {0})
prepare_lanes()
local recovered = spawn_lane(0, 91)
clock = 19.99
kill(recovered[1]); kill(recovered[2])
assert(snapshot(0).alive == 89 and not snapshot(0).overflow_active)
assert(scheduled["wave_monster_overflow:0"] == nil and #defeated == 0)
assert(overflow_notices[#overflow_notices].message == "怪物数量已恢复，警报解除")
clock = 25
spawn_lane(0, 2)
assert(snapshot(0).overflow_deadline == 45 and snapshot(0).overflow_remaining == 20)
tick(44.99, 0)
assert(#defeated == 0)
tick(45, 0)
assert(#defeated == 1 and #winners == 1)
print("PASS overflow grace: private center tips 20..1, no duplicate/paused tips, strict recovery below 90, fresh grace, expiry at 20s")

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

-- The 91st enemy starts only its owner's twenty seconds. Each deadline is independent.
spawn_lane(0, 10)
assert(snapshot(0).alive == 90 and not snapshot(0).overflow_active)
local extra_zero = spawn_lane(0, 1)
assert(snapshot(0).alive == 91 and snapshot(0).overflow_remaining == 20)
assert(snapshot(0).overflow_active and not snapshot(1).overflow_active)
assert(not snapshot(2).overflow_active and not snapshot(3).overflow_active)
clock = 2
spawn_lane(1, 11)
assert(snapshot(1).overflow_active and snapshot(1).overflow_remaining == 20)
tick(3.2, 0)
assert(last_projection.hud_clock_only==true,"clock ticks do not request HUD rebuilds")
assert(snapshot(0).overflow_deadline==20 and snapshot(1).overflow_deadline==22,"absolute personal deadlines are exposed")
assert(snapshot(0).overflow_remaining == 17 and snapshot(1).overflow_remaining == 19,
    "a later owner's timer must not inherit the first owner's deadline")
kill(lanes[2][1])
assert(last_projection.hud_player_id==2,"enemy count change targets its lane owner")
assert(snapshot(2).alive == 79 and snapshot(0).overflow_active and snapshot(1).overflow_active,
    "another player's death must not cancel a player's overflow")
local unrelated = unit("practice_or_archive_monster")
local before = snapshot().alive
kill(unrelated)
assert(snapshot().alive == before and snapshot(0).overflow_remaining == 17,
    "independent challenge monsters do not enter assault-wave population")
clock = 4
local extra = spawn_lane(0, 5)
assert(snapshot(0).alive == 96 and snapshot(0).overflow_remaining == 16,
    "additional spawns must not restart the warning")
clock = 5
for _, value in ipairs(extra) do kill(value) end
kill(extra_zero[1])
assert(snapshot(0).alive == 90 and snapshot(0).overflow_active)
kill(lanes[0][1])
assert(snapshot(0).alive == 89 and not snapshot(0).overflow_active)
assert(snapshot(0).overflow_remaining == 0 and scheduled["wave_monster_overflow:0"] == nil)
assert(snapshot(1).overflow_active and snapshot(1).overflow_remaining == 17)
kill(extra_zero[1])
assert(snapshot(0).alive == 89, "a duplicate death cannot lower the count again")
clock = 7
spawn_lane(0, 2)
assert(snapshot(0).overflow_remaining == 20 and snapshot(1).overflow_remaining == 15,
    "a recovered lane starts a fresh warning without resetting another player")
active_players = {0, 2, 3}
bus.emit(events.PLAYER_DISCONNECTED, { player_id = 1 })
assert(snapshot(1).alive == 0 and not snapshot(1).overflow_active)
assert(scheduled["wave_monster_overflow:1"] == nil and upvalue("wave_channels")[1] == nil)
assert(snapshot(0).alive == 91 and snapshot(0).overflow_remaining == 20)
assert(snapshot().alive == 250 and #winners == 0,
    "disconnect removes only the disconnected lane's registered enemies")

-- A personal deadline defeats only that player. Other players keep their channels and timers.
state = restart("N1", false, {0, 1, 2, 3})
prepare_lanes()
local old_zero_channel = upvalue("wave_channels")[0]
spawn_lane(0, 91)
clock = 2
spawn_lane(2, 91)
tick(19.99, 0)
assert(snapshot(0).overflow_remaining == 1 and #defeated == 0)
tick(20, 0)
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
assert(snapshot(1).alive == 91 and snapshot(1).overflow_remaining == 20,
    "surviving players must continue real generation after another player's defeat")
tick(22, 2)
assert(#defeated == 2 and snapshot(2).player_defeated and #winners == 0)
assert(snapshot(1).alive == 91 and snapshot(1).overflow_remaining == 18)
spawn_lane(3, 91)
tick(40, 1)
assert(#defeated == 3 and #winners == 0 and not state.defeat_settled)
tick(42, 3)
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
tick(20, 0)
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
tick(20, 0)
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
assert(cooperative_payloads[1] == 0, "defeated teammate cannot turn a lone winner into cooperative victory")
assert(archive.finish(surviving_challenges[1].hubs[3]))
assert(#winners == 1 and winners[1] == DOTA_TEAM_GOODGUYS)
-- Expiring inside other scheduler callbacks must not resurrect tasks after the last player's loss.
state = restart("N1", false, {0})
prepare_lanes()
upvalue("start_countdown")(60)
spawn_lane(0, 91)
clock = 20
assert(scheduled.wave_countdown() == false)
assert(state.status == "defeat" and scheduled.wave_countdown == nil and #winners == 1)
state = restart("N1", false, {0})
prepare_lanes()
spawn_lane(0, 91)
assert(upvalue("start_wave")(state.total_waves, "fixture"))
clock = 20
scheduled.wave_generation_complete()
assert(state.status == "defeat" and state.defeat_settled and #winners == 1)

-- A real death at the deadline restores that player's safe count before evaluation.
state = restart("N1", false, {0, 1})
prepare_lanes()
local victims = spawn_lane(0, 91)
clock = 19.99
kill(victims[1])
assert(snapshot(0).alive == 90 and snapshot(0).overflow_active)
clock = 20
kill(victims[2])
assert(snapshot(0).alive == 89 and not snapshot(0).overflow_active and #defeated == 0)
assert(#winners == 0)

-- Removal without a death event and forced cleanup cannot strand private counts or warnings.
state = restart("N1", false, {0, 1})
prepare_lanes()
local orphaned = spawn_lane(0, 91)
spawn_lane(1, 91)
orphaned[1].removed = true
orphaned[3].removed = true
upvalue("update_targets")()
assert(snapshot(0).alive == 89 and not snapshot(0).overflow_active)
assert(snapshot(1).alive == 91 and snapshot(1).overflow_active)
assert(snapshot().alive == 180)
assert(upvalue("clear_normal_wave_enemies")() == 180)
assert(snapshot().alive == 0 and #defeated == 0 and #archive_clears == 0)
local cleaned=orphaned[2]
assert(visual_cleanups[cleaned]==1 and visual_deaths[cleaned]==nil and hero_visual_deaths[cleaned]==nil,
    "forced removal uses immediate cleanup, never normal corpse on_death")
kill(cleaned); kill(cleaned)
assert(visual_cleanups[cleaned]==1 and visual_deaths[cleaned]==nil and hero_visual_deaths[cleaned]==nil,
    "late deaths after forced removal cannot clean or reward a retired enemy twice")
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

-- Cooperative victory uses the final connected human roster, not the number of lanes at start.
for _, case in ipairs({
    {players={0}, expected={[0]=0}},
    {players={0,1}, fake={[1]=true}, expected={[0]=0,[1]=0}},
    {players={0,1,2}, fake={[2]=true}, expected={[0]=1,[1]=1,[2]=0}},
    {players={0,1,2,3}, expected={[0]=1,[1]=1,[2]=1,[3]=1}},
    {players={0,1}, disconnected=1, expected={[0]=0}},
}) do
    local state=restart("N1",false,case.players)
    fake_players=case.fake or {}
    if case.disconnected then upvalue("disconnected_players")[case.disconnected]=true end
    final_ready(state);final_check()
    assert(state.victory_settled)
    for id, expected in pairs(case.expected) do assert(cooperative_payloads[id]==expected) end
    if case.disconnected then assert(cooperative_payloads[case.disconnected]==nil) end
    local count=#archive_clears;final_check();assert(#archive_clears==count)
end
print("PASS cooperative winner roster: solo, two humans, four humans, bots, defeated/disconnected teammate, duplicate victory")
print("PASS wave death visuals: separate corpse-preserving on_death, original metadata, one native retirement and reward, duplicate wave/archive death guards")

-- Fishing is a separate playable mode, not an empty difficulty that can clear
-- wave zero. Use the real event handlers with a selected mode and ready host.
local original_print, handler_errors = print, {}
print = function(...)
    local message = tostring(select(1, ...))
    if message:find("[EventBus] handler error", 1, true) then handler_errors[#handler_errors + 1] = message end
    original_print(...)
end
local fishing_state = restart(false, false, {0, 1}, "fishing")
local function fishing_idle(label)
    local view = snapshot(0)
    assert(view.game_mode == "fishing" and view.mode_selected and view.status == "fishing", label .. ": fishing projection")
    assert(view.difficulty_id == "" and view.difficulty_selected == false
        and view.can_confirm_difficulty == false and next(view.difficulty_options) == nil,
        label .. ": no difficulty or confirmation")
    assert(view.total_waves == 0 and view.current_wave == 0 and view.alive == 0
        and fishing_state.timer == 0 and fishing_state.pending == 0 and fishing_state.spawned == 0,
        label .. ": no countdown or wave population")
    assert(view.next_wave_number == nil and view.next_special_wave_number == nil, label .. ": no next-wave target")
    assert(not view.victory_settled and not view.defeat_settled and not view.post_clear_frozen
        and not view.early_final_used and not wave.is_dev_mode(), label .. ": no combat settlement")
    assert(not require("systems/gameplay_phase_guard").post_clear_frozen(), label .. ": gameplay remains available")
    assert(next(wave._wave_channels_for_test()) == nil, label .. ": no combat lane allocation")
    local resources = wave._resource_snapshot_for_test()
    assert(resources.session_count == 0 and resources.lease_count == 0 and preload_calls == 0,
        label .. ": no wave preload or model lease")
    local challenge = bus.request("archive.challenge_state", {})
    assert(challenge.active == 0 and challenge.ended == 0 and challenge.expired == 0 and challenge.deadline == 0
        and next(archive._test.players()) == nil, label .. ": no automatic archive challenge phase")
    assert(#created == 0 and #winners == 0 and #granted == 0 and #archive_clears == 0
        and #finalized == 0 and #defeated == 0, label .. ": no spawn, reward, clear record or victory")
    assert(scheduled_count == 0 and next(scheduled) == nil, label .. ": no wave or challenge timers")
end
local function reject_fishing_combat(label)
    local ok, reason = wave.set_difficulty("N1")
    assert(ok == false and reason == "fishing_mode_no_difficulty", label .. ": direct difficulty rejected")
    local requested = bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, {player_id = 0, difficulty_id = "N1"})
    assert(requested and requested.ok == false and requested.error == "fishing_mode_no_difficulty",
        label .. ": authorized host cannot choose a fishing difficulty")
    ok, reason = wave.debug_spawn_wave(1)
    assert(ok == false and reason == "fishing_mode_no_waves", label .. ": direct debug wave rejected")
    ok, reason = wave.debug_spawn_wave_for_players(1, {0, 1})
    assert(ok == false and reason == "fishing_mode_no_waves", label .. ": explicit debug lanes rejected")
    bus.emit(events.WAVE_START_NEXT, {})
    local early = bus.request(events.WAVE_EARLY_FINAL_REQUEST, {})
    assert(early and early.ok == false and early.error == "摸鱼模式没有波次", label .. ": early clear rejected")
    upvalue("start_countdown")(0)
    final_check()
    fishing_idle(label)
end
fishing_idle("before game start")
assert(snapshot().game_started == false)
reject_fishing_combat("before game start")
bus.emit(events.GAME_STARTED, {})
assert(snapshot().game_started == true, "fishing still receives the ordinary game-start lifecycle")
fishing_idle("after game start")
for _, at in ipairs({60, 1801, 7200}) do
    clock = at
    -- If a regression schedules combat or a challenge timeout, execute it in
    -- this standalone Lua fixture; this never calls an in-engine Tools command.
    local callbacks = {}
    for _, callback in pairs(scheduled) do callbacks[#callbacks + 1] = callback end
    for _, callback in ipairs(callbacks) do callback() end
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
    reject_fishing_combat("fishing at " .. at .. " seconds")
end
bus.emit(events.BUILDING_CREATED, {building_id = "wall", player_id = 0, entindex = 42})
kill(unit("unrelated_fishing_encounter"))
bus.emit(events.PLAYER_DISCONNECTED, {player_id = 1})
fishing_idle("unrelated death, wall creation and disconnect")

-- Both combat modes retain the real difficulty selection, countdown, wave
-- preloading and first-wave spawning after a fishing match is reinitialized.
for _, mode in ipairs({"standard", "pure"}) do
    local combat_state = restart(false, false, {0}, mode)
    bus.emit(events.GAME_STARTED, {})
    assert(snapshot().status == "selecting_difficulty" and snapshot().can_confirm_difficulty)
    assert(next(scheduled) == nil and #created == 0, mode .. ": combat waits for difficulty confirmation")
    local chosen = bus.request(events.WAVE_DIFFICULTY_SET_REQUEST, {player_id = 0, difficulty_id = "N1"})
    assert(chosen and chosen.ok and chosen.total_waves == 25, mode .. ": N1 difficulty remains selectable")
    assert(snapshot().game_mode == mode and snapshot().difficulty_selected and combat_state.status == "countdown")
    assert(type(scheduled.wave_countdown) == "function" and #created == 0)
    clock = require("config/wave_timing_config").initial_delay_seconds
    assert(scheduled.wave_countdown() == false)
    assert(combat_state.current_wave == 1 and combat_state.planned > 0 and preload_calls > 0,
        mode .. ": countdown starts wave one and queues the following wave")
    local callbacks = {}
    for key, callback in pairs(scheduled) do if type(key) == "number" then callbacks[#callbacks + 1] = callback end end
    for _, callback in ipairs(callbacks) do callback() end
    assert(#created == combat_state.planned and combat_state.spawned == combat_state.planned
        and combat_state.alive == combat_state.planned, mode .. ": actual configured first-wave population spawns")
    assert(#winners == 0 and #archive_clears == 0, mode .. ": first wave does not settle the match")
end
print = original_print
assert(#handler_errors == 0, table.concat(handler_errors, "\n"))
print("PASS fishing wave isolation: no difficulty/countdown/preload/spawn/challenge/clear; direct, event and debug requests denied; two-hour lifecycle stays playable; standard/pure still start real waves")
