-- Production reward selection/runtime, local wallet and building-challenge
-- settlement. Fixtures are limited to engine entities, profile input and the
-- downstream technology projection sink; no online archive/payment requests.
package.path = "scripts/vscripts/?.lua;" .. package.path
local clock, entity_id, checks = 0, 1000, 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function near(actual, expected, message)
    check(math.abs(actual - expected) < 0.00001,
        message .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
GameRules = {GetGameTime = function() return clock end}
PlayerResource = {GetPlayer = function() return {} end, GetTeam = function() return 2 end}
RandomFloat = function() return 0 end
RandomInt = function() return 1 end
local snapshots, stats_sink, resources_changed, reward_events = {}, {}, {}, {}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    if name == "survival_rogue_reward" then snapshots[key] = copy(value) end
end}
package.loaded["systems/player_context_service"] = {is_defeated = function() return false end}
package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen = function() return false end}
package.loaded["systems/rogue_builder_start_effect_service"] = {init = function() end}
package.loaded["systems/player_profile_service"] = {get_profile = function(id)
    return {save = {gameplay_stats = {initial_wood = id == 0 and 101 or 237,
        initial_gold = id == 0 and 19 or 83, initial_population_cap = 30}}}
end}
package.loaded["systems/hero_return_home_service"] = {return_unit = function() error("building challenge must not return a hero") end}
package.loaded["systems/monster_hero_visual_service"] = {clear = function() end, on_death = function() end}
local function entity(owner)
    entity_id = entity_id + 1
    local unit = {index = entity_id, survival_player_id = owner, health = 100, max_health = 100}
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return not self.dead and not self.removed end
    function unit:entindex() return self.index end
    function unit:GetHealth() return self.health end
    function unit:GetMaxHealth() return self.max_health end
    function unit:GetTeamNumber() return 2 end
    return unit
end
UTIL_Remove = function(unit) unit.removed = true end
local difficulty = "N3"
package.loaded["systems/wave_system"] = {
    get_difficulty = function() return "N1" end,
    spawn_challenge_monster = function(_, _, owner) return entity(owner) end,
}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local resource_system = require("systems/resource_system")
local service = require("systems/rogue_reward_service")
local runtime = require("systems/rogue_effect_runtime_service")
local effect_state = require("systems/rogue_effect_state_service")
local challenges = require("systems/building_challenge_service")
local monster_rewards = require("systems/monster_reward_service")
local definitions = require("config/generated/building_challenge_definitions")
local reward_effects = require("config/generated/reward_effects")
local registry = require("systems/rogue_effect_registry")
local buildings, challenge_buildings, walls, failure_mode = {}, {}, {}, nil
local function reset()
    bus.reset(); scheduler.clear(); clock = 0
    snapshots, stats_sink, resources_changed, reward_events = {}, {}, {}, {}
    buildings, challenge_buildings, walls, failure_mode = {}, {}, {}, nil
    service.init(); resource_system.init(); challenges.init(); monster_rewards.init()
    bus.handle_request(events.WAVE_STATE_GET_REQUEST, function() return {difficulty_id = difficulty} end)
    bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
        local result = {}
        for _, building in ipairs(buildings) do
            if building.player_id == payload.player_id and building.unit:IsAlive()
                and not building.unit.constructing then result[#result + 1] = building end
        end
        return {buildings = result}
    end)
    bus.handle_request(events.TECHNOLOGY_STATS_CHALLENGE_ADD_REQUEST, function(payload)
        stats_sink[#stats_sink + 1] = copy(payload)
        if failure_mode == "copy_failed" and #stats_sink % 2 == 0 then return {ok = false, error = "projection_failed"} end
        return {ok = true}
    end)
    bus.handle_request(events.HERO_PROGRESSION_APPLY_REQUEST, function(payload)
        stats_sink[#stats_sink + 1] = copy(payload)
        if failure_mode == "copy_failed" and #stats_sink % 2 == 0 then return {ok = false, error = "projection_failed"} end
        return {ok = true}
    end)
    bus.subscribe(events.RESOURCE_CHANGED, function(payload) resources_changed[#resources_changed + 1] = copy(payload) end)
    bus.subscribe(events.MONSTER_REWARD_GRANTED, function(payload) reward_events[#reward_events + 1] = copy(payload) end)
    for owner = 0, 1 do
        bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = owner})
        local wall = entity(owner); walls[owner] = wall
        buildings[#buildings + 1] = {building_id = "wall", unit = wall, level = 1, player_id = owner}
        buildings[#buildings + 1] = {building_id = "main_city", unit = entity(owner), level = 5, player_id = owner}
        local building = entity(owner); building.survival_building_id = "building_challenge"
        function building:FindAbilityByName() return nil end
        challenge_buildings[owner] = building
        bus.emit(events.BUILDING_CREATED, {unit = building, entindex = building:entindex(),
            building_id = "building_challenge", player_id = owner, team = 2})
    end
end
local function wallet(owner) return bus.request(events.RESOURCE_GET_REQUEST, {player_id = owner}) end
local function select_card(owner, card_id)
    local fillers = {"tower_growth", "corrosive_shield", "iron_fist"}
    local ids = {card_id}
    for _, id in ipairs(fillers) do if id ~= card_id and #ids < 3 then ids[#ids + 1] = id end end
    local offer = service.debug_offer(owner, ids)
    check(offer and offer.ok, "debug offer " .. card_id)
    local payload = {player_id = owner, card_id = card_id, token = offer.token, reward_type = "boss"}
    local result = bus.request(events.ROGUE_REWARD_SELECT_REQUEST, payload)
    check(result and result.ok, "production selection " .. card_id)
    local history = snapshots[tostring(owner)].history
    check(history[1].card_id == card_id, "real history records selection")
    return payload, result
end
reset()
local before, foreign = wallet(0), wallet(1)
local stale = select_card(0, "radiant_sapling")
near(wallet(0).wood, before.wood + math.floor(before.wood * 0.20), "sapling +20%, floored")
near(wallet(0).gold, before.gold, "sapling does not change gold")
near(wallet(1).wood, foreign.wood, "sapling is owner-local")
check(not bus.request(events.ROGUE_REWARD_SELECT_REQUEST, stale).ok, "stale sapling token rejected")
near(wallet(0).wood, 121, "stale selection cannot regrant")
check(runtime.snapshot(0)[1].status == "completed", "sapling one-shot complete")

reset(); before, foreign = wallet(0), wallet(1)
stale = select_card(0, "fiscal_subsidy")
near(wallet(0).gold, before.gold + 10000, "fiscal gold +10000")
near(wallet(0).wood, before.wood, "fiscal does not change wood")
near(wallet(1).gold, foreign.gold, "fiscal isolates same-team owner")
check(not bus.request(events.ROGUE_REWARD_SELECT_REQUEST, stale).ok, "stale fiscal token rejected")
near(wallet(0).gold, before.gold + 10000, "fiscal applies once")

for level = 1, 6 do
    reset(); difficulty = "N" .. tostring(level)
    buildings[#buildings + 1] = {building_id = "gold_mine", unit = entity(0), level = 1, player_id = 0}
    local dead = entity(0); dead.dead = true
    buildings[#buildings + 1] = {building_id = "arrow_tower", unit = dead, level = 1, player_id = 0}
    local pending = entity(0); pending.constructing = true
    buildings[#buildings + 1] = {building_id = "arrow_tower", unit = pending, level = 1, player_id = 0}
    before, foreign = wallet(0), wallet(1)
    select_card(0, "infrastructure_outsourcing")
    near(wallet(0).gold, before.gold + 3 * level * 100, "outsourcing alive built count × difficulty N" .. level)
    near(wallet(1).gold, foreign.gold, "outsourcing owner-local")
    near(wallet(0).wood, before.wood, "outsourcing does not change wood")
end

reset(); select_card(0, "command_change")
near(effect_state.numeric(0, "next_rogue_reroll_count:boss"), 1, "command queues one future reroll")
near(effect_state.numeric(1, "next_rogue_reroll_count:boss"), 0, "command owner-local")
check(bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {player_id = 0, reward_type = "boss"}).ok, "open next natural offer")
near(snapshots["0"].rerolls_remaining, 2, "next offer uses default one + command one")
near(effect_state.numeric(0, "next_rogue_reroll_count:boss"), 0, "consume once at page creation")
check(bus.request(events.ROGUE_REWARD_REROLL_REQUEST, {player_id = 0, token = snapshots["0"].token}).ok, "reroll real reward page")
near(snapshots["0"].rerolls_remaining, 1, "reroll preserves remaining quota")
check(bus.request(events.ROGUE_REWARD_REROLL_REQUEST, {player_id = 0, token = snapshots["0"].token}).ok, "second reroll real reward page")
near(snapshots["0"].rerolls_remaining, 0, "two rolls exhausted")
check(not bus.request(events.ROGUE_REWARD_REROLL_REQUEST, {player_id = 0, token = snapshots["0"].token}).ok, "third rejected")

local function summon(owner, definition)
    local building = challenge_buildings[owner]
    local ability = {GetCaster = function() return building end,
        IsNull = function() return false end,
        GetAbilityName = function() return definition.ability_name end}
    local result = bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST,
        {building_entindex = building:entindex(), building = building,
            challenge_id = definition.challenge_id, source_ability = ability})
    check(result and result.ok, "production challenge summon " .. definition.challenge_id)
    return result.unit
end
local function killed(unit, killer_owner)
    unit.dead = true
    bus.emit(events.ENGINE_ENTITY_KILLED, {victim = unit, victim_entindex = unit:entindex(), player_id = killer_owner})
end
reset(); select_card(0, "bounty_order")
near(effect_state.numeric(0, "building_challenge_reward_doubles"), 5, "bounty grants five successful rewards")
near(effect_state.numeric(1, "building_challenge_reward_doubles"), 0, "bounty owner-local")
for index, definition in ipairs(definitions.rows) do
    local monster = summon(0, definition)
    local old_events, old_sink = #reward_events, #stats_sink
    killed(monster, 1)
    near(#reward_events - old_events, 2, "original + copy reward " .. definition.challenge_id)
    near(#stats_sink - old_sink, 2, "both downstream projections " .. definition.challenge_id)
    local original, extra = reward_events[old_events + 1], reward_events[old_events + 2]
    check(original.ok and extra.ok, "both grants succeed")
    check(original.player_id == 0 and extra.player_id == 0, "owner retained even foreign killer")
    check(original.reward_profile_id == definition.reward_profile_id
        and extra.reward_profile_id == original.reward_profile_id, "identical reward profile")
    near(original.resources.gold, extra.resources.gold, "copy gold identical")
    near(original.resources.wood, extra.resources.wood, "copy wood identical")
    check(#original.effects == #extra.effects, "copy effect count identical")
    for key, effect in ipairs(original.effects) do
        check(extra.effects[key].effect_type == effect.effect_type and extra.effects[key].value == effect.value,
            "copy exact effect/value")
    end
    near(effect_state.numeric(0, "building_challenge_reward_doubles"), 5 - index, "one use per successful challenge")
    killed(monster, 1)
    near(#reward_events, old_events + 2, "duplicate death cannot regrant")
end
local old_events = #reward_events
killed(summon(0, definitions.rows[1]), 0)
near(#reward_events - old_events, 1, "sixth success normal reward only")

reset(); select_card(0, "bounty_order")
old_events = #reward_events
killed(summon(1, definitions.rows[1]), 0)
near(#reward_events - old_events, 1, "other owner's challenge not doubled")
near(effect_state.numeric(0, "building_challenge_reward_doubles"), 5, "foreign challenge cannot consume")
local timeout_target = summon(0, definitions.rows[1]); clock = 61; killed(timeout_target, 0)
near(effect_state.numeric(0, "building_challenge_reward_doubles"), 5, "timeout cannot consume")
near(#reward_events, old_events + 1, "timeout no reward")
clock = 62
local wall_target = summon(0, definitions.rows[2]); walls[0].health = 49; killed(wall_target, 0)
near(effect_state.numeric(0, "building_challenge_reward_doubles"), 5, "failed wall-health check cannot consume")
near(#reward_events, old_events + 1, "wall failure no reward")

reset(); select_card(0, "bounty_order"); failure_mode = "copy_failed"
killed(summon(0, definitions.rows[1]), 0)
near(effect_state.numeric(0, "building_challenge_reward_doubles"), 5, "failed copy retains quota")
check(reward_events[1].ok and not reward_events[2].ok, "failed copy is explicitly reported")

-- An unrelated hero reward uses the reward service directly and cannot drain
-- the building-challenge domain quota.
local profile = definitions.rows[1].reward_profile_id
failure_mode = nil
check(bus.request(events.MONSTER_REWARD_GRANT_REQUEST,
    {player_id = 0, team = 2, reward_profile_id = profile, encounter_id = "encounter_hero_test"}).ok,
    "unrelated reward succeeds")
near(effect_state.numeric(0, "building_challenge_reward_doubles"), 5, "hero/unrelated reward cannot consume")
print("ROGUE_BOSS_ACTIONS_FULL_PASS " .. checks .. " checks: real selection/runtime; local wood/gold; N1-N6 building count; next-page rerolls; five challenge copies, isolation, timeout, wall failure, deduplication and failed-copy quota")
