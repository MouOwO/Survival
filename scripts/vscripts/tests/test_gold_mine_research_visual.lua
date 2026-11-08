-- Real shop transaction, technology grant, mine owner routing and visual playback.
package.path = "scripts/vscripts/?.lua;" .. package.path
-- Synthetic players in this isolated process have no Steam admission API.
package.loaded["config/test_access"] = {enabled = false}
local original_print = print
print = function(...)
 local message = tostring(select(1, ...))
 assert(not message:find("handler error", 1, true), message)
 original_print(...)
end
local bus, events = require("core/event_bus"), require("core/events")
local noop = function() end
local now = 10
GameRules = {GetGameTime = function() return now end}
PlayerResource = {IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
 GetTeam = function() return 2 end}
package.loaded["core/scheduler"] = {after = noop, cancel = noop}
package.loaded["systems/building_visual_service"] = {apply = noop}
package.loaded["systems/building_sound_service"] = {upgrade_completed = noop}
package.loaded["systems/building_upgrade_process"] = {is_active = function() return false end,
 cancel_by_entindex = noop}
package.loaded["systems/technology_stat_manager"] = {get = function() return {final = {gold_mine = {}}} end}
Vector = function(x, y, z) return {x = x, y = y, z = z} end
PATTACH_ABSORIGIN_FOLLOW = 1
local effects, releases, notices, completions = {}, {}, {}, {}
ParticleManager = {
 CreateParticle = function(_, path, attach, unit)
  effects[#effects + 1] = {path = path, unit = unit, attach = attach}; return #effects
 end,
 SetParticleControl = noop,
 ReleaseParticleIndex = function(_, id) releases[id] = true end,
}
local shop = require("systems/shop_system")
local mine = require("systems/gold_mine_system")
shop.init(); mine.init()
local buildings = {}
local money = {[0] = {wood = 10000000, gold = 10000000}, [1] = {wood = 10000000, gold = 10000000}}
bus.handle_request(events.RESOURCE_GET_REQUEST, function(p) return money[p.player_id] end)
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function(p)
 local wallet = money[p.player_id]
 if wallet.wood < (p.wood or 0) then return {ok = false, error = "wood_not_enough"} end
 if wallet.gold < (p.gold or 0) then return {ok = false, error = "gold_not_enough"} end
 wallet.wood = wallet.wood - (p.wood or 0); wallet.gold = wallet.gold - (p.gold or 0)
 return {ok = true}
end)
bus.handle_request(events.BUILDING_QUERY_REQUEST, function(p) return buildings[p.entindex] end)
bus.subscribe(events.UI_NOTIFICATION, function(p) notices[#notices + 1] = p end)
bus.subscribe(events.GOLD_MINE_TECHNOLOGY_COMPLETED, function(p) completions[#completions + 1] = p end)
local function make_mine(index, owner)
 local unit = {}
 function unit:IsNull() return false end
 function unit:IsAlive() return not self.dead end
 function unit:entindex() return index end
 function unit:GetAbsOrigin() return Vector(index, 0, 0) end
 function unit:FindAbilityByName() return nil end
 buildings[index] = {unit = unit, entindex = index, player_id = owner, team = 2,
  building_id = "gold_mine", level = 1, definition = {}}
 bus.emit(events.BUILDING_CREATED, buildings[index])
 return unit
end
local first, second, unselected, other = make_mine(101, 0), make_mine(102, 0),
 make_mine(103, 0), make_mine(201, 1)
local function assert_effects_since(previous, units, path)
 local expected = {}
 for _, unit in ipairs(units) do expected[unit] = true end
 assert(#effects == previous + #units, "each living owned mine receives one completion effect")
 for index = previous + 1, #effects do
  local effect = effects[index]
  assert(expected[effect.unit], "no duplicate or foreign mine effect")
  expected[effect.unit] = nil
  assert(releases[index] and effect.path:find(path, 1, true))
 end
end
local function buy(owner, index, group, id)
 return assert(bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, {
  player_id = owner, entindex = index, technology_group = group,
  source = "gold_mine_ability", request_id = id,
 }))
end
assert(buy(0, 101, "gold_mine_efficiency", "mine_efficiency_1").ok)
assert_effects_since(0, {first, second, unselected}, "omniknight_purification")
assert(notices[#notices].message == "研究【提高采金效率】科技成功"
 and notices[#notices].player_id == 0 and notices[#notices].kind == "research_success"
 and notices[#notices].audience == "player")
assert(buy(0, 101, "gold_mine_efficiency", "mine_efficiency_1").ok)
assert(#effects == 3 and #completions == 1, "idempotent request must not replay completion")
assert(buy(0, 102, "gold_mine_crit", "mine_crit_1").ok)
assert_effects_since(3, {first, second, unselected}, "phantom_assassin_crit_impact")
assert(notices[#notices].message == "研究【提升采金暴击】科技成功")
assert(not buy(0, 201, "gold_mine_efficiency", "foreign_mine").ok and #effects == 6)
money[0].wood, money[0].gold = 0, 0
assert(not buy(0, 101, "gold_mine_efficiency", "poor_mine").ok and #effects == 6)
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, {player_id = 0, researching = 1})
assert(#effects == 6, "queue progress never plays completion visual")
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, completions[1])
assert(#effects == 6, "duplicate completion never repeats")
first.dead = true
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, {player_id = 0, entindex = 101,
 unit = first, technology_group = "gold_mine_crit", level = 1})
assert(#effects == 6, "dead source never authorizes completion effects")
assert(buy(1, 201, "gold_mine_efficiency", "other_owner").ok)
assert_effects_since(6, {other}, "omniknight_purification")
assert(notices[#notices].player_id == 1)
local precached = {}
PrecacheResource = function(kind, path) assert(kind == "particle"); precached[path] = true end
require("systems/gold_mine_research_visual").precache({})
for _, effect in ipairs(effects) do assert(precached[effect.path]) end
print("GOLD_MINE_RESEARCH_VISUAL_PASS: real grant completion, all owned mines including unselected, owner isolation, no failure/queue replay, native precache")

-- Panorama's batch dispatcher intentionally silences shop notices and must
-- publish exactly one styled success itself. All owned mines receive the effect.
local batch = require("systems/gold_mine_batch_upgrade_service")
local gold_config = require("config/gold_mine_technology_config")
EntIndexToHScript = function(index) return buildings[index] and buildings[index].unit end
for index, building in pairs(buildings) do
 local unit = building.unit
 unit.dead = false
 unit.survival_player_id = building.player_id
 unit.survival_building_id = "gold_mine"
 unit.abilities = {}
 function unit:FindAbilityByName(name) return self.abilities[name] end
 for _, ability_name in ipairs({"ability_upgrade_gold_mine_efficiency", "ability_upgrade_gold_mine_crit"}) do
  local ability = {active = true, hidden = false, cooldowns = 0, name = ability_name}
  function ability:IsNull() return false end
  function ability:GetCaster() return unit end
  function ability:GetAbilityName() return self.name end
  function ability:IsPassive() return false end
  function ability:IsHidden() return self.hidden end
  function ability:IsActivated() return self.active end
  function ability:IsFullyCastable() return not self.cooling end
  function ability:GetLevel() return 1 end
  function ability:GetCooldown() return 1 end
  function ability:SetHidden(value) self.hidden = value end
  function ability:SetActivated(value) self.active = value end
  function ability:StartCooldown() self.cooling = true; self.cooldowns = self.cooldowns + 1 end
  unit.abilities[ability_name] = ability
 end
end
money[0].wood, money[0].gold = 10000000, 10000000
for _, case in ipairs({{"gold_mine_efficiency", "提高采金效率", gold_config.efficiency_cost},
 {"gold_mine_crit", "提升采金暴击", gold_config.crit_cost}}) do
 local ability_name = case[1] == "gold_mine_efficiency"
  and "ability_upgrade_gold_mine_efficiency" or "ability_upgrade_gold_mine_crit"
 local payload = {player_id = 0, primary = second, primary_ability = second.abilities[ability_name],
  ability_name = ability_name, selected_entindexes = {101, 102, 101, 201}}
 local prior_effects, prior_notices, prior_completions = #effects, #notices, #completions
 local prior_wood, prior_gold = money[0].wood, money[0].gold
 local quote = case[3](2)
 local result = batch.execute(payload)
 assert(result.ok and result.success_count == 2 and result.skipped_count == 1
  and result.technology_levels_purchased == 1, "batch buys one shared technology level")
 assert(money[0].wood == prior_wood - quote.wood and money[0].gold == prior_gold - quote.gold,
  "selected mines never multiply shared technology cost")
 assert_effects_since(prior_effects, {first, second, unselected},
  case[1] == "gold_mine_efficiency" and "omniknight_purification" or "phantom_assassin_crit_impact")
 assert(#completions == prior_completions + 1, "shared technology completes once")
 assert(#notices == prior_notices + 1 and notices[#notices].kind == "research_success"
  and notices[#notices].subject == case[2] and notices[#notices].ability_icon == ability_name
  and notices[#notices].audience == "player" and notices[#notices].player_id == 0
  and notices[#notices].message == "研究【" .. case[2] .. "】科技成功",
  "batch has one personal styled notice, no duplicated shop notification")
 assert(first.abilities[ability_name].cooldowns == 1 and second.abilities[ability_name].cooldowns == 1
  and other.abilities[ability_name].cooldowns == 0, "cooldown applies only to eligible owned mines")
 assert(not batch.execute(payload).ok and #effects == prior_effects + 3
  and #notices == prior_notices + 1, "duplicate click during cooldown cannot replay success")
 first.abilities[ability_name].cooling, second.abilities[ability_name].cooling = false, false
 money[0].wood, money[0].gold = 0, 0
 prior_notices = #notices
 assert(not batch.execute(payload).ok and #effects == prior_effects + 3
  and #notices == prior_notices + 1 and notices[#notices].level == "error"
  and notices[#notices].kind ~= "research_success", "failed batch shows one error and no completion effect")
 assert(first.abilities[ability_name].cooldowns == 1 and second.abilities[ability_name].cooldowns == 1,
  "resource failure never starts additional cooldowns")
 money[0].wood, money[0].gold = 10000000, 10000000
end
print("GOLD_MINE_BATCH_RESEARCH_PASS: all owned mines, one personal styled notice, single charge, shared cooldown, foreign/duplicate selection, failure/repeat isolation")

-- Completion deduplication belongs to the player, so rebuilding a mine cannot
-- replay a past research result. Live handles removed from the index stay out.
local previous = #effects
local late = make_mine(104, 0)
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, completions[#completions])
assert(#effects == previous, "new mine cannot replay an old shared completion")
first.dead = true
bus.emit(events.BUILDING_DESTROYED, {building_id = "gold_mine", entindex = "103",
 player_id = 0, team = 2, unit = unselected})
assert(buy(0, 102, "gold_mine_efficiency", "dead_removed_mines").ok)
assert_effects_since(previous, {second, late}, "omniknight_purification")
previous = #effects
first.dead = false
local replacement = make_mine(101, 1)
assert(buy(0, 102, "gold_mine_efficiency", "replaced_mine_owner").ok)
assert_effects_since(previous, {second, late}, "omniknight_purification")
previous = #effects
assert(buy(1, 101, "gold_mine_crit", "replacement_owner").ok)
assert_effects_since(previous, {other, replacement}, "phantom_assassin_crit_impact")

-- A new world clears both membership and the shared completion watermark.
bus.reset(); mine.init()
bus.handle_request(events.TECHNOLOGY_STATE_GET_REQUEST, function() return {levels = {}} end)
local fresh = make_mine(301, 0)
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {gold_mine_efficiency = 1}})
previous = #effects
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, {player_id = 0, entindex = 301,
 unit = fresh, technology_group = "gold_mine_efficiency", level = 1})
assert_effects_since(previous, {fresh}, "omniknight_purification")
print("GOLD_MINE_RESEARCH_LIFECYCLE_PASS: death, destruction, replacement, new mine replay and new world isolation")

-- One failed particle must not prevent other mines from playing or refund a
-- completed technology. The next real level retries that mine normally.
local failing = make_mine(302, 0)
local create_particle = ParticleManager.CreateParticle
ParticleManager.CreateParticle = function(manager, path, attach, unit)
 if unit == failing then error("injected particle failure") end
 return create_particle(manager, path, attach, unit)
end
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {gold_mine_efficiency = 2}})
previous = #effects
local completion = {player_id = 0, entindex = 301, unit = fresh,
 technology_group = "gold_mine_efficiency", level = 2}
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, completion)
assert_effects_since(previous, {fresh}, "omniknight_purification")
ParticleManager.CreateParticle = create_particle
previous = #effects
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, completion)
assert(#effects == previous, "visual failure cannot replay a completed level")
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {gold_mine_efficiency = 3}})
completion.level = 3
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, completion)
assert_effects_since(previous, {fresh, failing}, "omniknight_purification")
print("GOLD_MINE_RESEARCH_FAILURE_ISOLATION_PASS")
