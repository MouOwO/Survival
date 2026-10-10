-- Real shop transaction, technology grant, mine owner routing and visual playback.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local noop = function() end
local now = 10
GameRules = {GetGameTime = function() return now end}
PlayerResource = {IsValidPlayerID = function(_, id) return id == 0 or id == 1 end,
 GetTeam = function() return 2 end}
package.loaded["core/scheduler"] = {after = noop, cancel = noop}
package.loaded["systems/building_visual_service"] = {apply = noop}
package.loaded["systems/building_sound_service"] = {upgrade_completed = noop}
package.loaded["systems/building_upgrade_process"] = {is_active = function() return false end}
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
local first, second, other = make_mine(101, 0), make_mine(102, 0), make_mine(201, 1)
local function buy(owner, index, group, id)
 return assert(bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, {
  player_id = owner, entindex = index, technology_group = group,
  source = "gold_mine_ability", request_id = id,
 }))
end
assert(buy(0, 101, "gold_mine_efficiency", "mine_efficiency_1").ok)
assert(#effects == 1 and effects[1].unit == first and releases[1])
assert(effects[1].path:find("omniknight_purification", 1, true))
assert(notices[#notices].message == "研究【提高采金效率】科技成功"
 and notices[#notices].player_id == 0 and notices[#notices].kind == "research_success"
 and notices[#notices].audience == "player")
assert(buy(0, 101, "gold_mine_efficiency", "mine_efficiency_1").ok)
assert(#effects == 1 and #completions == 1, "idempotent request must not replay completion")
assert(buy(0, 102, "gold_mine_crit", "mine_crit_1").ok)
assert(#effects == 2 and effects[2].unit == second and releases[2])
assert(effects[2].path:find("phantom_assassin_crit_impact", 1, true))
assert(notices[#notices].message == "研究【提升采金暴击】科技成功")
assert(not buy(0, 201, "gold_mine_efficiency", "foreign_mine").ok and #effects == 2)
money[0].wood, money[0].gold = 0, 0
assert(not buy(0, 101, "gold_mine_efficiency", "poor_mine").ok and #effects == 2)
bus.emit(events.TECHNOLOGY_RESEARCH_STATE_CHANGED, {player_id = 0, researching = 1})
assert(#effects == 2, "queue progress never plays completion visual")
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, completions[1])
assert(#effects == 2, "duplicate completion never repeats")
first.dead = true
bus.emit(events.GOLD_MINE_TECHNOLOGY_COMPLETED, {player_id = 0, entindex = 101,
 unit = first, technology_group = "gold_mine_crit", level = 1})
assert(#effects == 2, "dead gold mine never receives completion effect")
assert(buy(1, 201, "gold_mine_efficiency", "other_owner").ok)
assert(#effects == 3 and effects[3].unit == other and notices[#notices].player_id == 1)
local precached = {}
PrecacheResource = function(kind, path) assert(kind == "particle"); precached[path] = true end
require("systems/gold_mine_research_visual").precache({})
for _, effect in ipairs(effects) do assert(precached[effect.path]) end
print("GOLD_MINE_RESEARCH_VISUAL_PASS: real grant completion, healing/crit visuals, one source mine, owner isolation, no failure/queue replay, native precache")

-- Panorama's batch dispatcher intentionally silences shop notices and must
-- publish exactly one styled success itself. Its selected mine owns the effect.
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
 assert(#effects == prior_effects + 1 and effects[#effects].unit == second
  and #completions == prior_completions + 1, "primary mine receives the single completion effect")
 assert(#notices == prior_notices + 1 and notices[#notices].kind == "research_success"
  and notices[#notices].subject == case[2] and notices[#notices].ability_icon == ability_name
  and notices[#notices].audience == "player" and notices[#notices].player_id == 0
  and notices[#notices].message == "研究【" .. case[2] .. "】科技成功",
  "batch has one personal styled notice, no duplicated shop notification")
 assert(first.abilities[ability_name].cooldowns == 1 and second.abilities[ability_name].cooldowns == 1
  and other.abilities[ability_name].cooldowns == 0, "cooldown applies only to eligible owned mines")
 assert(not batch.execute(payload).ok and #effects == prior_effects + 1
  and #notices == prior_notices + 1, "duplicate click during cooldown cannot replay success")
 first.abilities[ability_name].cooling, second.abilities[ability_name].cooling = false, false
 money[0].wood, money[0].gold = 0, 0
 prior_notices = #notices
 assert(not batch.execute(payload).ok and #effects == prior_effects + 1
  and #notices == prior_notices + 1 and notices[#notices].level == "error"
  and notices[#notices].kind ~= "research_success", "failed batch shows one error and no completion effect")
 assert(first.abilities[ability_name].cooldowns == 1 and second.abilities[ability_name].cooldowns == 1,
  "resource failure never starts additional cooldowns")
 money[0].wood, money[0].gold = 10000000, 10000000
end
print("GOLD_MINE_BATCH_RESEARCH_PASS: primary mine binding, one personal styled notice, single charge, shared cooldown, foreign/duplicate selection, failure/repeat isolation")
