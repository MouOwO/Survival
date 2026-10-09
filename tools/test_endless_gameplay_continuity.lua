-- Integration coverage for ordinary gameplay across the post-wave challenge phase.
-- Keep the real challenge, endless, resource, phase guard and scheduler services;
-- substitute only the engine, map/config fixtures and archive HTTP boundary.
package.path = "scripts/vscripts/?.lua;" .. package.path

local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local guard = require("systems/gameplay_phase_guard")
local noop = function() end
local clock, serial, units, pending, winners, rewards, finalizations, fail_spawn, fail_setter
local late_cleanup_write
DOTA_TEAM_GOODGUYS = 2
Vector = function(x, y, z) return {x = x, y = y, z = z} end
PlayerResource = {GetTeam = function() return DOTA_TEAM_GOODGUYS end}

package.loaded["config/resources_config"] = {
    initial_wood = 100, initial_gold = 50,
    initial_population = 0, initial_max_population = 10,
}
package.loaded["config/generated/archive_challenge_definitions"] = {rows = {}, by_id = {}}
package.loaded["config/generated/archive_challenge_stats"] = {by_id = {}}
package.loaded["config/generated/archive_challenge_rules"] = {by_id = {default = {
    building_unlock_difficulty = 1, building_spacing = 240, building_offset_y = 360,
    building_model = "test.vmdl", building_model_scale = 1, phase_duration_seconds = 10,
}}}
package.loaded["systems/archive_endless_config"] = {
    rules = {monsters_per_wave = 1, time_limit_seconds = 4},
    group = function() return {} end,
    wave = function() return {health = 100, attack = 1, war3_armor = 0} end,
    score = function() return 1 end,
}
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return false end,
    register_unit = function(id, unit) unit.owner = id end,
    unregister_unit = noop,
    owner_player_id = function(unit) return unit.owner end,
}
package.loaded["systems/player_profile_service"] = {
    get_profile = function() return {save = {gameplay_stats = {}}} end,
}
package.loaded["systems/archive_service"] = {
    has_pending = function() return pending end,
    record_endless_wave = function() rewards = rewards + 1 end,
    begin_finalization = function()
        assert(guard.post_clear_frozen(), "freeze before starting the final archive save")
        finalizations = finalizations + 1
        pending = true
    end,
}
package.loaded["systems/monster_hero_visual_service"] = {clear = noop, on_death = noop}
package.loaded["systems/challenge_guardian_visual_service"] = {clear = noop, apply = noop}

local function unit(name, position)
    serial = serial + 1
    local body = {id = serial, name = name, position = position, abilities = {}}
    function body:IsNull() return self.removed == true end
    function body:IsAlive() return not self.removed end
    function body:entindex() return self.id end
    function body:GetAbsOrigin() return self.position end
    function body:FindAbilityByName(ability_name) return self.abilities[ability_name] end
    function body:AddAbility(ability_name)
        local ability = {IsNull = function() return false end,
            SetLevel = noop, SetActivated = noop, StartCooldown = noop,
            GetCaster = function() return body end,
            GetAbilityName = function() return ability_name end}
        self.abilities[ability_name] = ability
        return ability
    end
    function body:SetControllableByPlayer(id) self.owner = id end
    body.SetModel, body.SetOriginalModel, body.SetModelScale = noop, noop, noop
    body.AddNewModifier = noop
    function body:SetDeathXP()
        if fail_setter then error("engine unit setter failed") end
    end
    units[#units + 1] = body
    return body
end
package.loaded["systems/wave_system"] = {
    get_player_spawn_marker = function(id)
        return {IsNull = function() return false end,
            GetAbsOrigin = function() return Vector(id * 2000, 0, 0) end}
    end,
    spawn_challenge_monster = function()
        if fail_spawn then return nil end
        return unit("endless_monster", Vector(0, 0, 0))
    end,
}

local challenge = require("systems/archive_challenge_service")
local endless = require("systems/archive_endless_service")
local resources = require("systems/resource_system")
local payload = {difficulty_id = "N1", player_ids = {0, 1}}
local function balance(id)
    return bus.request(events.RESOURCE_GET_REQUEST, {player_id = id or 0})
end
local function tick(time)
    clock = time
    scheduler.think()
end
local function setup()
    clock, serial, units, pending, winners, rewards, finalizations, fail_spawn, fail_setter =
        0, 0, {}, false, 0, 0, 0, false, false
    late_cleanup_write = false
    package.loaded["systems/archive_endless_config"].rules.time_limit_seconds = 4
    bus.reset()
    scheduler.clear()
    guard.reset()
    GameRules = {GetGameTime = function() return clock end,
        SetGameWinner = function(_, team)
            assert(team == DOTA_TEAM_GOODGUYS)
            winners = winners + 1
        end}
    CreateUnitByName = unit
    UTIL_Remove = function(body)
        body.removed = true
        if challenge.phase_snapshot().ended == 1 then
            local result = bus.request(events.RESOURCE_ADD_REQUEST,
                {player_id = 0, wood = 1, reason = "late_cleanup_callback"})
            if result.ok then late_cleanup_write = true end
        end
        bus.emit(events.ENGINE_ENTITY_KILLED, {victim = body, victim_entindex = body.id})
    end
    bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function()
        return {ok = true, totals = {initial_wood = 100, initial_population_cap = 10,
            wood_per_second = 2, gold_per_second = 3}}
    end)
    resources.init()
    for _, id in ipairs(payload.player_ids) do
        bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = id})
    end
    challenge.init()
    -- This is the transition guard established when the final normal wave clears.
    guard.set_post_clear_frozen(true)
end
local function assert_frozen(id)
    local before = balance(id)
    for _, request in ipairs({
        {events.RESOURCE_ADD_REQUEST, {player_id = id or 0, wood = 7, reason = "lumberjack"}},
        {events.RESOURCE_CAN_SPEND_REQUEST, {player_id = id or 0, wood = 3, gold = 4}},
        {events.RESOURCE_TRY_SPEND_REQUEST, {player_id = id or 0, wood = 3, gold = 4}},
    }) do
        local result = bus.request(request[1], request[2])
        assert(result.ok == false and result.error == "post_clear_frozen",
            "final settlement must reject resource changes")
    end
    local after = balance(id)
    assert(after.wood == before.wood and after.gold == before.gold)
    return before
end
local function ordinary_gameplay(id)
    id = id or 0
    local before = balance(id)
    local harvested = bus.request(events.RESOURCE_ADD_REQUEST,
        {player_id = id, wood = 7, reason = "lumberjack"})
    assert(harvested.ok, "lumber income must be credited during challenges")
    assert(balance(id).wood == before.wood + 7)
    assert(bus.request(events.RESOURCE_CAN_SPEND_REQUEST,
        {player_id = id, wood = 3, gold = 4}).ok,
        "ordinary upgrade affordability must remain available")
    assert(bus.request(events.RESOURCE_TRY_SPEND_REQUEST,
        {player_id = id, wood = 3, gold = 4, reason = "upgrade"}).ok,
        "ordinary upgrade spending must remain available")
    local after = balance(id)
    assert(after.wood == before.wood + 4 and after.gold == before.gold - 4,
        "harvesting and upgrade spending must update the existing wallet")
end
local function start_endless(id)
    local hub = challenge._test.players()[id].hubs[2]
    assert(challenge.start_endless(hub, hub:FindAbilityByName("ability_archive_endless")))
    assert(endless.is_running(id))
end
local function assert_saved_settlement()
    assert(finalizations == 1 and pending and winners == 0)
    assert(not late_cleanup_write, "final settlement must freeze before any cleanup callback")
    assert(challenge.phase_snapshot().saving == 1)
    local frozen = assert_frozen()
    assert(not challenge.begin(payload).keep_running,
        "duplicate begin cannot reopen a phase waiting for its final save")
    assert(guard.post_clear_frozen())
    tick(clock + 1)
    assert(balance().wood == frozen.wood and balance().gold == frozen.gold,
        "passive income must also stop while finalization is pending")
    assert(winners == 0)
    pending = false
    tick(clock + 0.25)
    assert(winners == 1 and challenge.phase_snapshot().saving == 0)
    assert(not challenge.begin(payload).keep_running and guard.post_clear_frozen(),
        "duplicate begin cannot reopen a completed game")
    assert_frozen()
end

setup()
assert_frozen()
local initial = balance()
tick(1)
assert(balance().wood == initial.wood and balance().gold == initial.gold,
    "income waits while the post-wave handoff is frozen")
assert(challenge.begin(payload).keep_running)
assert_frozen()
tick(2)
assert(balance().wood == initial.wood and balance().gold == initial.gold,
    "waiting for an endless challenge must preserve the post-wave freeze")
start_endless(0)
ordinary_gameplay()
local before_income = balance()
tick(3)
assert(balance().wood == before_income.wood + 2 and balance().gold == before_income.gold + 3,
    "passive income continues while endless monsters are alive")
local monster = units[#units]
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = monster, victim_entindex = monster.id})
assert(rewards == 1)
tick(3.1)
assert(endless.snapshot(0).wave == 2 and endless.is_running(0))
ordinary_gameplay()
local deadline = challenge.phase_snapshot().deadline
assert(challenge.begin(payload).keep_running and challenge.phase_snapshot().deadline == deadline,
    "retrying begin cannot extend the phase")
tick(deadline)
assert(challenge.phase_snapshot().expired == 1 and not endless.is_running(0))
assert(rewards == 1, "timeout cleanup must not award another endless wave")
assert_saved_settlement()

setup()
assert(challenge.begin(payload).keep_running)
start_endless(0)
start_endless(1)
assert(not endless.start(0, 1), "duplicate start cannot open another gameplay window")
assert(challenge.finish(challenge._test.players()[0].hubs[3]))
endless.cancel(0, "duplicate finish")
endless.cancel(0, "duplicate finish")
assert(not guard.post_clear_frozen() and endless.is_running(1),
    "one player finishing must not freeze the other player's ongoing challenge")
ordinary_gameplay(1)
assert(challenge.finish(challenge._test.players()[1].hubs[3]))
assert(challenge.phase_snapshot().ended == 1 and challenge.phase_snapshot().expired == 0)
assert_saved_settlement()

setup()
assert(challenge.begin(payload).keep_running)
package.loaded["systems/archive_endless_config"].rules.time_limit_seconds = 100
start_endless(0)
start_endless(1)
tick(challenge.phase_snapshot().deadline)
assert(not endless.is_running(0) and not endless.is_running(1))
assert_saved_settlement()

setup()
assert(challenge.begin(payload).keep_running)
start_endless(0)
ordinary_gameplay()
tick(4)
assert(not endless.is_running(0) and challenge.phase_snapshot().active == 1,
    "the endless wave timeout need not end the whole archive phase")
assert_frozen()
assert(challenge.begin(payload).keep_running)
assert_frozen()

setup()
assert(challenge.begin(payload).keep_running)
local endless_hub = challenge._test.players()[0].hubs[2]
fail_spawn = true
assert(not challenge.start_endless(endless_hub, endless_hub:FindAbilityByName("ability_archive_endless")))
assert(not endless.is_running(0))
assert_frozen()
fail_spawn = false
start_endless(0)
ordinary_gameplay()
endless.cancel(0, "test completion")
assert_frozen()

setup()
assert(challenge.begin(payload).keep_running)
endless_hub = challenge._test.players()[0].hubs[2]
fail_setter = true
local protected, started = pcall(challenge.start_endless, endless_hub,
    endless_hub:FindAbilityByName("ability_archive_endless"))
assert(protected and not started, "initial unit setup exceptions must become failed starts")
assert(not endless.is_running(0) and units[#units].removed,
    "initial unit setup failure must remove its partially configured monster")
assert(rewards == 0)
assert_frozen()
fail_setter = false
start_endless(0)
ordinary_gameplay()

setup()
assert(challenge.begin(payload).keep_running)
start_endless(0)
monster = units[#units]
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = monster, victim_entindex = monster.id})
ordinary_gameplay()
fail_setter = true
tick(0.1)
assert(not endless.is_running(0) and units[#units].removed,
    "a queued wave setup exception must stop endless and remove its partial monster")
assert(rewards == 1, "failed next-wave setup cannot grant another clear reward")
local failed_balance = assert_frozen()
tick(1.1)
assert(balance().wood == failed_balance.wood and balance().gold == failed_balance.gold,
    "passive income must stop after a queued wave setup failure")

setup()
assert(challenge.begin(payload).keep_running)
start_endless(0)
guard.set_endless_active(0, true)
guard.set_endless_active(0, true)
ordinary_gameplay()
endless.cancel(0, "duplicate lifecycle notifications")
endless.cancel(0, "duplicate lifecycle notifications")
assert_frozen()

setup()
assert(challenge.begin(payload).keep_running)
start_endless(0)
ordinary_gameplay()
guard.set_post_clear_frozen(true)
assert_frozen()
assert(challenge.begin(payload).keep_running)
assert_frozen()
endless.init()
assert_frozen()

setup()
assert(challenge.begin(payload).keep_running)
start_endless(0)
ordinary_gameplay()
guard.freeze_for_settlement()
local before_final_start = #units
local other_hub = challenge._test.players()[1].hubs[2]
assert(not challenge.start_endless(other_hub, other_hub:FindAbilityByName("ability_archive_endless")),
    "an unstarted player cannot reopen gameplay during final defeat/settlement")
assert(#units == before_final_start and not endless.is_running(1),
    "a rejected final-phase start cannot create another monster")
assert_frozen()
guard.set_post_clear_frozen(false)
assert_frozen()
assert(not endless.start(1, 1) and #units == before_final_start,
    "ordinary phase toggles cannot bypass the terminal settlement lock")
endless.cancel(0, "finish after terminal freeze")
assert_frozen()

setup()
assert(challenge.begin(payload).keep_running)
start_endless(1)
ordinary_gameplay(1)

setup()
assert(challenge.begin(payload).keep_running)
start_endless(0)
monster = units[#units]
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = monster, victim_entindex = monster.id})
local before_reset = #units
endless.init()
assert_frozen()
tick(0.1)
assert(#units == before_reset and not endless.is_running(0),
    "init must invalidate a queued next wave from the previous run")
assert_frozen()

setup()
assert(not challenge.begin({difficulty_id = "N0", player_ids = {0}}).keep_running)
assert_frozen()
assert(challenge.begin({difficulty_id = "N1", player_ids = {}}).ok == false)
assert_frozen()
print("ENDLESS_GAMEPLAY_CONTINUITY_PASS: endless harvesting, upgrade spending, passive income, wave rollover, multiplayer finish, save barriers, spawn/setup failures, terminal lock/reset, queued reset, duplicate lifecycle events")
