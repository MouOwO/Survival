-- Real generated parameters, builder handlers, event bus, technology totals and
-- tree settlement. The resource request and native entities are engine doubles.
package.path = "scripts/vscripts/?.lua;" .. package.path
local real_print = print
print = function(message)
    if tostring(message):find("handler error") then error(message) end
end
local bus, events = require("core/event_bus"), require("core/events")
local tasks, accounts = {}, {}
package.loaded["core/scheduler"] = {
    every = function(interval, callback, key) tasks[key] = {callback = callback, interval = interval} end,
    cancel = function(key) tasks[key] = nil end,
}
package.loaded["core/particle_manager"] = {show_green_number = function() end}
package.loaded["systems/harvest_feedback_service"] = {reset = function() end, add = function() end}
package.loaded["systems/player_context_service"] = {
    owner_player_id = function(unit) return unit and unit.survival_player_id end,
}
PlayerResource = {GetTeam = function() return 2 end, GetPlayer = function() return nil end}
local clock = 0
GameRules = {GetGameTime = function() return clock end}
local wave = {current_wave = 3, difficulty_id = "n3"}
bus.handle_request(events.WAVE_STATE_GET_REQUEST, function() return wave end)
bus.handle_request(events.RESOURCE_ADD_REQUEST, function(payload)
    local account = accounts[payload.player_id] or {wood = 0, gold = 0, max_population = 0}
    accounts[payload.player_id] = account
    for _, key in ipairs({"wood", "gold", "max_population"}) do
        account[key] = account[key] + (payload[key] or 0)
    end
    return {ok = true}
end)
local function near(actual, expected, label)
    assert(math.abs(actual - expected) < 1e-8,
        label .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local wall = {health = 980, maximum = 1000, survival_player_id = 0}
function wall:IsNull() return false end
function wall:IsAlive() return true end
function wall:GetHealth() return self.health end
function wall:GetMaxHealth() return self.maximum end
function wall:Heal(value) self.health = self.health + value end
bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
    return {buildings = payload.player_id == 0 and {{building_id = "wall", unit = wall}} or {}}
end)
local technology = require("systems/technology_stat_manager")
technology.init()
local builder = require("systems/rogue_builder_start_effect_service")
builder.init()
local effects = require("config/generated/rogue_reward_effects")
local parameter_rows = require("config/generated/rogue_reward_effect_params").rows
local function grant(card, player_id)
    local effect = assert(effects.by_id[card .. "_effect"])
    local parameters = {}
    for _, row in ipairs(parameter_rows) do
        if row.effect_id == effect.effect_id and row.enabled then
            parameters[row.param_name] = row.number_value or row.string_value
        end
    end
    local instance = {player_id = player_id or 0, card_id = card, reward_type = "builder_start",
        effect_instance_id = card .. ":" .. tostring(player_id or 0), effect = effect, params = parameters}
    assert(builder.apply(instance))
    return instance
end
grant("instant_wood")
near(accounts[0].wood, 300, "instant wood at n3")
grant("population_expansion")
near(accounts[0].max_population, 5, "population cap")
local nature = grant("natures_gift")
local before = accounts[0].wood
near(tasks[nature.builder_task_id].interval, 1, "nature interval")
tasks[nature.builder_task_id].callback()
near(accounts[0].wood - before, 3, "nature payout")
builder.remove(nature)
assert(tasks[nature.builder_task_id] == nil, "removed instance must cancel its income timer")
grant("wealthy_start")
bus.emit(events.WAVE_CHANGED, {reason = "wave_started", current_wave = 3})
near(accounts[0].gold, 90, "wave 3 gold")
bus.emit(events.WAVE_CHANGED, {reason = "wave_started", current_wave = 3})
near(accounts[0].gold, 90, "duplicate wave cannot pay again")
grant("woodcutting_bounty")
local victim = {survival_is_wave_monster = true}
function victim:IsNull() return false end
before = accounts[0].wood
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = victim, attacker = {survival_player_id = 0}})
near(accounts[0].wood - before, 15, "wave 3 kill wood")
bus.emit(events.ENGINE_ENTITY_KILLED, {victim = victim, attacker = {survival_player_id = 1}})
assert(accounts[1] == nil, "another player's kill cannot consume this player's talent")
local recovery = grant("wall_recovery")
near(tasks[recovery.builder_task_id].interval, 1, "wall recovery interval")
for _ = 1, 60 do tasks[recovery.builder_task_id].callback() end
near(wall.health, 1000, "healing caps at current maximum")
near(wall.maximum, 1000, "recovery does not grow maximum HP")
near(technology.get(0).final.wall.technology_armor_bonus, 1 / 3, "one War3 armor at 60 seconds")
grant("peaceful_labor")
grant("heavy_hand")
local trees = require("systems/tree_system")
trees.init()
local tree = {}
function tree:IsNull() return false end
function tree:GetHealth() return 100 end
function tree:GetUnitName() return "enemy_tree" end
local worker = {survival_player_id = 0, survival_super_lumberjack = true}
function worker:IsNull() return false end
function worker:IsRealHero() return false end
function worker:GetUnitName() return "npc_survival_lumberjack" end
local enemy = {survival_is_wave_monster = true}
function enemy:IsNull() return false end
function enemy:IsAlive() return true end
function enemy:GetAttackTarget() return self.target end
Entities = {FindAllByClassname = function() return {enemy} end}
trees._reset_for_test(1, tree, 0)
local roll = 100
RandomFloat = function() return roll end
local function hit(base, source, critical_chance)
    local old = accounts[0].wood
    clock = clock + 1
    bus.emit(events.TREE_HIT, {player_id = 0, team = 2, attacker = worker, target = tree,
        source = source or "lumberjack", base_lumber_efficiency = base,
        critical_chance_pct = critical_chance or 0})
    return accounts[0].wood - old
end
near(hit(10), 12, "peaceful harvest")
enemy.target = wall
near(hit(10), 10, "wall targeted cancels peaceful harvest")
roll = 4.99
near(hit(10), 20, "heavy hand chance below 5")
roll = 5
near(hit(10), 10, "heavy hand chance at 5")
worker.survival_super_lumberjack = false
roll = 0
near(hit(10), 10, "ordinary worker excluded")
worker.survival_super_lumberjack = true
roll = 24.99
near(hit(10, "lumberjack", 20), 20, "heavy hand adds 5 percentage points to technology")
worker.IsRealHero = function() return true end
local hero_base = hit(10, "hero")
grant("first_to_strike")
near(hit(10, "hero"), hero_base * 2, "hero tree harvest doubles")
print = real_print
print("BUILDER_RESOURCE_HARVEST_PASS generated params; immediate/wave/kill/timed payouts; cancellation; owner isolation; heal cap; armor tick; peaceful condition; critical boundaries; ordinary/fused workers; hero harvest")
