-- Production CSV grants, lifecycle dispatch, modifier callbacks and damage
-- filtering. Engine entities/events are simulated; no running game is touched.
package.path = "scripts/vscripts/?.lua;" .. package.path
function class(base) base.__index = base; return base end
function LinkLuaModifier() end
local server = true
function IsServer() return server end
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_MAGICAL, DAMAGE_TYPE_PURE = 1, 2, 4
DOTA_DAMAGE_CATEGORY_ATTACK, DOTA_DAMAGE_CATEGORY_SPELL = 1, 0
DOTA_DAMAGE_FLAG_IGNORES_PHYSICAL_ARMOR = 2
MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE = 1
MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE = 2
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE = 3
MODIFIER_EVENT_ON_ATTACK, MODIFIER_EVENT_ON_TAKEDAMAGE = 4, 5
MODIFIER_EVENT_ON_ATTACK_LANDED, MODIFIER_PROPERTY_MIN_HEALTH = 6, 7
MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE = 8
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_STATE_MAGIC_IMMUNE = 1
local now, serial, checks = 0, 0, 0
GameRules = {GetGameTime = function() return now end}
PlayerResource = {GetPlayer = function() return {} end, GetTeam = function() return 2 end}
RandomFloat = function() return 1 end
local entities, roster, heroes, workers, hero_attacks = {}, {}, {}, {}, {}
Entities = {FindAllByClassname = function() local result = {}
    for _, u in pairs(entities) do result[#result + 1] = u end; return result end}
EntIndexToHScript = function(index) return entities[index] end
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return false end,
    is_owned_by = function(id, u) return u.survival_player_id == id end,
    owner_player_id = function(u) return u.survival_player_id end,
    active_player_ids = function() return {0, 1, 2, 3, 4, 5} end,
}
local bus, events = require("core/event_bus"), require("core/events")
local scheduler = require("core/scheduler")
local runtime = require("systems/rogue_effect_runtime_service")
local state = require("systems/rogue_effect_state_service")
local routes = require("config/tower_route_config")
local armor = require("config/armor_balance")
require("modifiers/modifier_rogue_reward_effects")
require("modifiers/modifier_rogue_combat_effects")
require("modifiers/modifier_equipment_effects")
require("modifiers/modifier_research_technology")
require("modifiers/modifier_tower_attack_effects")
local function near(actual, expected, label)
    checks = checks + 1
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6,
        (label or "value") .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end
local function unit(player, building, level, tower_class)
    serial = serial + 1
    local u = {index = serial, survival_player_id = player,
        survival_building_id = building, survival_tower_class = tower_class,
        survival_level = level, team = 2, health = 750, maximum = 1000,
        base_damage = 100, modifiers = {}, alive = true}
    entities[serial] = u
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:IsRealHero() return self.real_hero == true end
    function u:entindex() return self.index end
    function u:GetTeamNumber() return self.team end
    function u:GetUnitName() return "npc_dota_creature" end
    function u:IsInvulnerable() return false end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.maximum end
    function u:SetHealth(value) self.health = value end
    function u:SetBaseMaxHealth(value) self.maximum = value end
    function u:SetMaxHealth(value) self.maximum = value end
    function u:SetBaseDamageMin(value) self.base_damage = value end
    function u:SetBaseDamageMax(value) self.base_damage = value end
    function u:GetBaseDamageMin() return self.base_damage end
    function u:SetBaseAttackTime(value) self.attack_time = value end
    function u:SetPhysicalArmorBaseValue(value) self.armor = value end
    function u:Script_SetAttackRange(value) self.attack_range = value end
    function u:SetAcquisitionRange(value) self.acquisition_range = value end
    function u:GetPhysicalArmorValue() return 0 end
    function u:Heal(value) self.health = math.min(self.maximum, self.health + value) end
    function u:FindModifierByName(name) return self.modifiers[name] end
    function u:FindAllModifiersByName(name)
        return self.modifiers[name] and {self.modifiers[name]} or {}
    end
    function u:HasModifier(name) return self.modifiers[name] ~= nil end
    function u:RemoveModifierByName(name)
        local m = self.modifiers[name]; if m then m:Destroy() end
    end
    function u:AddNewModifier(_, _, name, params)
        local m = self.modifiers[name]
        if m then
            m.refreshes = (m.refreshes or 0) + 1
            if m.OnRefresh then m:OnRefresh(params or {}) end
            return m
        end
        m = setmetatable({}, {__index = _G[name] or {}})
        function m:GetParent() return u end
        function m:IsNull() return false end
        function m:SetStackCount(value) self.stacks = value end
        function m:GetStackCount() return self.stacks or 0 end
        function m:SetHasCustomTransmitterData() end
        function m:SendBuffRefreshToClients() end
        function m:StartIntervalThink() end
        function m:Destroy()
            u.modifiers[name] = nil
            if self.OnDestroy then self:OnDestroy() end
        end
        self.modifiers[name] = m
        if m.OnCreated then m:OnCreated(params or {}) end
        return m
    end
    function u:GetAverageTrueAttackDamage()
        local pct, flat = 0, 0
        for _, m in pairs(self.modifiers) do
            if m.GetModifierBaseDamageOutgoing_Percentage then
                pct = pct + m:GetModifierBaseDamageOutgoing_Percentage()
            end
            if m.GetModifierPreAttack_BonusDamage then flat = flat + m:GetModifierPreAttack_BonusDamage() end
        end
        return self.base_damage * (1 + pct / 100) + flat
    end
    return u
end
local function building(player, level, tower_class)
    local u = unit(player, "arrow_tower", level, tower_class)
    local b = {unit = u, player_id = player, building_id = "arrow_tower",
        level = level, tower_class = tower_class}
    local row = assert(routes.current(b))
    u.survival_tower_stage_id, b.record_id = row.stage_id, row.record_id
    roster[player] = roster[player] or {}; table.insert(roster[player], b)
    return b
end
local function change(b, level, reason)
    b.level, b.unit.survival_level = level, level
    local row = assert(routes.current(b))
    b.record_id, b.unit.survival_tower_stage_id = row.record_id, row.stage_id
    b.reason = reason or "tower_upgraded_one"
    bus.emit(events.BUILDING_CHANGED, b)
end
local function grant(player, card)
    local result = runtime.grant(player, card, "combat:" .. player .. ":" .. card, "boss")
    assert(result.ok, tostring(card) .. ": " .. tostring(result.error)); return result
end
bus.handle_request(events.BUILDING_LIST_REQUEST, function(p) return {buildings = roster[p.player_id] or {}} end)
bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(p) return {unit = heroes[p.player_id]} end)
bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function(p)
    return {snapshot = {attack_min = hero_attacks[p.player_id] or 0, attack_max = hero_attacks[p.player_id] or 0}}
end)
bus.handle_request(events.EQUIPMENT_STATS_GET_REQUEST, function()
    return {snapshot = {values = {attack_flat = 100, lifesteal_pct = 100}}}
end)
bus.handle_request(events.WORKER_LIST_REQUEST, function(p) return workers[p.player_id] or {} end)
bus.handle_request(events.WAVE_STATE_GET_REQUEST, function()
    return {next_special_wave_number = 6, next_special_role = "wave_leader"}
end)
require("systems/technology_stat_manager").init()
runtime.init()

-- Both grant orders, mixed route stages, creation, stage entry/exit, snapshot
-- stability after another final tower is built and the counted tower dies.
for player = 0, 1 do
    local base, ordinary, final, ballista = building(player, 4), building(player, 6, "class_5"),
        building(player, 25, "class_5"), building(player, 11, "class_5")
    if player == 0 then grant(player, "gunpowder_splash"); grant(player, "tower_network")
    else grant(player, "tower_network"); grant(player, "gunpowder_splash") end
    near(base.unit:GetAverageTrueAttackDamage(), 105, "base never inherits ballista bonus")
    near(ordinary.unit:GetAverageTrueAttackDamage(), 105, "converted tower is not final")
    near(final.unit:GetAverageTrueAttackDamage(), 105, "one true final tower")
    near(ballista.unit:GetAverageTrueAttackDamage(), 135, "ballista + frozen network snapshot")
    local stable = ballista.unit.modifiers.modifier_rogue_tower_attack_projection
    local refreshes = stable.refreshes or 0
    change(ballista, 11, "technology_changed")
    near(stable.refreshes or 0, refreshes, "same projection skips modifier refresh")
    assert(ballista.unit.modifiers.modifier_rogue_tower_attack_projection == stable,
        "same projection preserves modifier identity")
    local late = building(player, 1)
    bus.emit(events.BUILDING_CREATED, late)
    near(late.unit:GetAverageTrueAttackDamage(), 105, "later tower inherits network")
    local updated = ordinary.unit.modifiers.modifier_rogue_tower_attack_projection
    change(ordinary, 11)
    near(ordinary.unit:GetAverageTrueAttackDamage(), 135, "enter ballista stage")
    assert(ordinary.unit.modifiers.modifier_rogue_tower_attack_projection == updated,
        "changed projection refreshes existing modifier")
    change(ordinary, 16)
    near(ordinary.unit:GetAverageTrueAttackDamage(), 105, "leave ballista stage")
    local later_final = building(player, 25, "class_4")
    bus.emit(events.BUILDING_CREATED, later_final)
    near(later_final.unit:GetAverageTrueAttackDamage(), 105, "later final cannot change snapshot")
    final.unit.alive = false; bus.emit(events.BUILDING_DESTROYED, final)
    near(ballista.unit:GetAverageTrueAttackDamage(), 135, "destroyed final cannot change snapshot")
end
for index = 1, 12 do building(2, 25, "class_" .. ((index - 1) % 7 + 1)) end
grant(2, "tower_network")
near(roster[2][1].unit:GetAverageTrueAttackDamage(), 150, "network cap")
grant(3, "tower_network")
local after_empty = building(3, 25, "class_1"); bus.emit(events.BUILDING_CREATED, after_empty)
near(after_empty.unit:GetAverageTrueAttackDamage(), 100, "empty snapshot persists")
after_empty.unit.survival_rogue_tower_projection = 99
change(after_empty, 25, "technology_changed")
assert(after_empty.unit.survival_rogue_tower_projection == nil,
    "zero projection clears stale cache even without a modifier")

-- Record-ID recruitment refreshes existing and later base towers; growth is
-- attached only to successful owned upgrade events, never a stats refresh.
local recruit = building(4, 1); grant(4, "recruit_training")
near(recruit.unit:GetAverageTrueAttackDamage(), 200, "existing recruit tower")
local new_recruit = building(4, 4); bus.emit(events.BUILDING_CREATED, new_recruit)
near(new_recruit.unit:GetAverageTrueAttackDamage(), 200, "later recruit tower")
change(new_recruit, 5)
near(new_recruit.unit:GetAverageTrueAttackDamage(), 100, "recruit stops above LV4")
grant(4, "tower_growth")
change(recruit, 2); near(recruit.unit:GetAverageTrueAttackDamage(), 210, "one completed upgrade")
change(recruit, 3); near(recruit.unit:GetAverageTrueAttackDamage(), 220, "two completed upgrades")
change(recruit, 3, "technology_changed")
near(recruit.unit:GetAverageTrueAttackDamage(), 220, "refresh does not grow tower")
change(roster[0][1], 5)
assert(not roster[0][1].unit:HasModifier("modifier_rogue_tower_growth"), "other owner cannot grow")

local enemy = unit(-1); enemy.team = 3; enemy.survival_is_wave_monster = true
local challenge = unit(-1); challenge.team = 3; challenge.survival_is_challenge_monster = true
grant(4, "frozen_wall")
near(enemy.modifiers.modifier_rogue_enemy_attack_speed:GetModifierAttackSpeedPercentage(), -15)
near(challenge.modifiers.modifier_rogue_enemy_attack_speed:GetModifierAttackSpeedPercentage(), -15)
local late_enemy = unit(-1); late_enemy.team = 3; late_enemy.survival_is_wave_monster = true
bus.emit(events.MONSTER_SPAWNED, {unit = late_enemy, player_id = 5})
near(late_enemy.modifiers.modifier_rogue_enemy_attack_speed:GetModifierAttackSpeedPercentage(), -15)

-- One player channel must never consume another player's next-special grant.
grant(4, "weakening_orb"); grant(5, "weakening_orb")
bus.emit(events.MONSTER_SPAWNED, {unit = enemy, monster_source = "wave", player_id = 4,
    wave_number = 6, member_role = "normal"})
assert(not enemy:HasModifier("modifier_rogue_weakening_attack"))
bus.emit(events.MONSTER_SPAWNED, {unit = enemy, monster_source = "wave", player_id = 4,
    wave_number = 6, member_role = "wave_leader"})
near(enemy.modifiers.modifier_rogue_weakening_attack:GetModifierBaseDamageOutgoing_Percentage(), -50)
bus.emit(events.MONSTER_SPAWNED, {unit = late_enemy, monster_source = "wave", player_id = 5,
    wave_number = 6, member_role = "wave_leader"})
near(late_enemy.modifiers.modifier_rogue_weakening_attack:GetModifierBaseDamageOutgoing_Percentage(), -50)
local no_second = unit(-1)
bus.emit(events.MONSTER_SPAWNED, {unit = no_second, monster_source = "wave", player_id = 5,
    wave_number = 6, member_role = "wave_leader"})
assert(not no_second:HasModifier("modifier_rogue_weakening_attack"), "weakening consumes once")

-- Real armor-reduction modifier converts runtime armor back to game units.
enemy.survival_armor_mapping_version = armor.CUSTOM_WAR3_MAPPING_VERSION
enemy.survival_war3_armor_target = true
enemy.survival_war3_armor, enemy.survival_effective_war3_armor = 100, 100
grant(4, "corrosive_shield")
local corrosion = enemy.modifiers.modifier_rogue_corrosive_shield_attack
corrosion:OnAttack({attacker = enemy, target = recruit.unit, record = 101})
near(enemy.survival_effective_war3_armor, 99, "one attack removes one game armor")
corrosion:OnAttack({attacker = enemy, target = recruit.unit, record = 101})
near(enemy.survival_effective_war3_armor, 99, "duplicate event is ignored")
corrosion:OnAttack({attacker = enemy, target = roster[0][1].unit, record = 102})
near(enemy.survival_effective_war3_armor, 99, "other player's target has no corrosion")
corrosion:OnAttack({attacker = enemy, target = recruit.unit, record = 103})
near(enemy.survival_effective_war3_armor, 98, "corrosion stacks")
local newly_spawned = unit(-1); newly_spawned.team = 3; newly_spawned.survival_is_wave_monster = true
bus.emit(events.MONSTER_SPAWNED, {unit = newly_spawned})
near(newly_spawned.modifiers.modifier_rogue_corrosive_shield_attack.armor_reduction_per_attack, 1 / 3)

local wall = unit(4, "wall"); table.insert(roster[4], {unit = wall, building_id = "wall", player_id = 4})
grant(4, "feast"); near(wall:GetHealth(), 1500); near(wall:GetMaxHealth(), 2000)
near(state.wall_health_flat(4), 1000, "feast retained for later wall stat refresh")
local upgrades = require("systems/building_upgrade_system")
local function private(fn, wanted, seen)
    seen = seen or {}; if seen[fn] then return end; seen[fn] = true
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index); if not name then break end
        if name == wanted then return value end
    end
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index); if not name then break end
        if type(value) == "function" then
            local result = private(value, wanted, seen); if result ~= nil then return result end
        end
    end
end
local registered_buildings = assert(private(upgrades.init, "buildings"))
local refresh_building = assert(private(upgrades.init, "apply_research_technology"))
local wall_state = {unit = wall, player_id = 4, building_id = "wall", level = 1,
    definition = {levels = {{health = 1000, war3_armor = 10}}}}
registered_buildings[wall:entindex()] = wall_state
refresh_building(wall_state, "audit", {technology = {wall = {}}, permanent = {}, profile_stats = {}})
near(wall:GetMaxHealth(), 2000, "real wall refresh retains feast")
near(wall:GetHealth(), 1500, "real wall refresh retains current health")
grant(5, "fortifications")
local fort_tower = unit(5, "arrow_tower", 1); fort_tower.survival_research_base_attack_time = 2
local fort_state = {unit = fort_tower, player_id = 5, building_id = "arrow_tower", level = 1,
    research_base_attack_damage = 100, definition = {levels = {{health = 1000}}}}
registered_buildings[fort_tower:entindex()] = fort_state
refresh_building(fort_state, "audit", {
    technology = require("systems/technology_stat_manager").get(5).final,
    permanent = {}, profile_stats = {},
})
near(fort_tower.attack_time, 2 / 1.06, "technology bonus reaches real tower BAT setter")
grant(4, "ion_shield")
local filter = require("combat/damage_filter_service")
filter.init({event_bus = bus, events = events, repository = {consume_pending = function() end},
    config = {boss_rules = {enabled = false}, minimum_post_multiplier = 0}})
local function hit(attacker, victim, amount, damage_type, category)
    local keys = {entindex_attacker_const = attacker:entindex(), entindex_victim_const = victim:entindex(),
        damage = amount, damagetype_const = damage_type or DAMAGE_TYPE_MAGICAL,
        damage_category_const = category or DOTA_DAMAGE_CATEGORY_ATTACK}
    assert(filter._filter_for_test(filter, keys), "filter blocked test hit"); return keys.damage
end
near(hit(enemy, wall, 10000), 400, "wall final hit cap")
near(hit(enemy, wall, 50), 50, "small wall hit")
local other_wall = unit(5, "wall")
near(hit(enemy, other_wall, 10000), 10000, "wall owner isolation")
local hero = unit(4); hero.real_hero = true; heroes[4] = hero
grant(4, "kick_when_down")
near(hit(hero, challenge, 100), 100, "no movement slow")
challenge:AddNewModifier(challenge, nil, "modifier_tower_frost_slow", {slow_pct = 25})
near(hit(hero, challenge, 100), 150, "actual frost modifier")
challenge:RemoveModifierByName("modifier_tower_frost_slow")
challenge:AddNewModifier(challenge, nil, "modifier_tower_blizzard_slow", {slow_pct = 25})
near(hit(hero, challenge, 100), 150, "actual blizzard modifier")
challenge.modifiers.modifier_survival_managed_buff = {
    definition = {effect_type = "move_speed_pct"}, value = -30, IsNull = function() return false end}
near(hit(hero, challenge, 100), 150, "multiple slows still apply only once")
near(hit(roster[0][1].unit, challenge, 100), 100, "slow bonus owner isolation")
challenge.modifiers.modifier_tower_blizzard_slow = nil
challenge.modifiers.modifier_survival_managed_buff = {
    definition = {effect_type = "attack_speed_pct"}, value = -30, IsNull = function() return false end}
near(hit(hero, challenge, 100), 100, "attack slow is not movement slow")
grant(4, "iron_fist_policy")
near(hit(hero, enemy, 100, DAMAGE_TYPE_PHYSICAL),
    100 * armor.war3_physical_damage_multiplier(98, 40), "physical basic attack ignores armor")
near(hit(hero, enemy, 100, DAMAGE_TYPE_PHYSICAL, DOTA_DAMAGE_CATEGORY_SPELL),
    100 * armor.war3_physical_damage_multiplier(98, 0), "physical spell retains armor")

local worker, repairer = unit(4), unit(4)
workers[4] = {{unit = worker, player_id = 4, worker_type = "lumberjack"},
    {unit = repairer, player_id = 4, worker_type = "repairer"}}
grant(4, "boss_promise")
near(worker.modifiers.modifier_rogue_lumberjack_attack_speed:GetModifierAttackSpeedPercentage(), 100)
assert(not repairer:HasModifier("modifier_rogue_lumberjack_attack_speed"))
now = 119
local late_worker = unit(4); local late_state = {unit = late_worker, player_id = 4, worker_type = "lumberjack"}
table.insert(workers[4], late_state); bus.emit(events.WORKER_CHANGED, late_state)
near(late_worker.modifiers.modifier_rogue_lumberjack_attack_speed:GetModifierAttackSpeedPercentage(), 100)
now = 120; scheduler.think()
assert(not worker:HasModifier("modifier_rogue_lumberjack_attack_speed"))
assert(not late_worker:HasModifier("modifier_rogue_lumberjack_attack_speed"), "late worker uses original deadline")

grant(4, "high_morale")
near(hero.modifiers.modifier_rogue_combat_bonus:GetModifierBaseDamageOutgoing_Percentage(), 30)
grant(4, "in_step"); hero_attacks[4] = 1000; hero.base_damage = 1000 / 1.3
near(recruit.unit.modifiers.modifier_rogue_combat_bonus:GetModifierPreAttack_BonusDamage(), 100)
hero_attacks[4] = 2500; hero.base_damage = 2500 / 1.3
near(recruit.unit.modifiers.modifier_rogue_combat_bonus:GetModifierPreAttack_BonusDamage(), 250)
grant(4, "bloodthirst_potion")
near(state.numeric(4, "hero_lifesteal_pct"), 100)
hero.health = 700
hero.modifiers.modifier_rogue_combat_bonus:OnTakeDamage({attacker = hero, unit = enemy,
    damage = 100, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
near(hero.health, 800, "burst lifesteal")
now = 180; scheduler.think(); near(state.numeric(4, "hero_lifesteal_pct"), 20)
hero.modifiers.modifier_rogue_combat_bonus:OnTakeDamage({attacker = hero, unit = enemy,
    damage = 100, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
near(hero.health, 820, "permanent lifesteal")
require("core/hero_health_guard").protect_value(hero, 700, "rogue_lifesteal_test")
hero.modifiers.modifier_rogue_combat_bonus:OnTakeDamage({attacker = hero, unit = enemy,
    damage = 2000, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
now = 181; scheduler.think()
near(hero.health, 1000, "legitimate full lifesteal survives delayed health guard")

-- Dummy callback grants every owned landed hit; opponent and spell damage do
-- not enter this attack event. Creation geometry is an engine integration check.
local dummy = unit(4); dummy.team = 3
local training = dummy:AddNewModifier(dummy, nil, "modifier_rogue_training_dummy", {value = 100})
training:OnAttackLanded({attacker = hero, target = dummy})
training:OnAttackLanded({attacker = hero, target = dummy})
near(hero.modifiers.modifier_rogue_training_attack:GetModifierPreAttack_BonusDamage(), 200)
training:OnAttackLanded({attacker = roster[0][1].unit, target = dummy})
assert(not roster[0][1].unit:HasModifier("modifier_rogue_training_attack"), "dummy owner isolation")
near(training:GetMinHealth(), 1, "dummy survives attacks")

-- OnTakeDamage uses the victim's compressed native health. Convert the
-- post-mitigation amount once into the healing hero's own native health units;
-- attack projection must never multiply this already-delivered damage again.
state.set_numeric(4, "hero_lifesteal_pct", 100)
enemy.survival_endless_health_scale = 100
hero.survival_endless_attack_scale = 1000
hero.health = 100
hero.modifiers.modifier_rogue_combat_bonus:OnTakeDamage({attacker = hero, unit = enemy,
    damage = 5, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
near(hero.health, 600, "rogue lifesteal restores victim health scale exactly once")
hero.survival_endless_health_scale = 10; hero.health = 100
hero.modifiers.modifier_rogue_combat_bonus:OnTakeDamage({attacker = hero, unit = enemy,
    damage = 5, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
near(hero.health, 150, "rogue lifesteal converts into hero native health")
hero.modifiers.modifier_rogue_combat_bonus:OnTakeDamage({attacker = hero, unit = enemy,
    damage = 5, damage_category = DOTA_DAMAGE_CATEGORY_SPELL})
near(hero.health, 150, "rogue lifesteal excludes spells under health projection")
local equipped = unit(4); equipped.real_hero = true
equipped.survival_endless_attack_scale = 1000; equipped.health = 100
local equipment = equipped:AddNewModifier(equipped, nil, "modifier_equipment_effects", {player_id = 4})
equipment:OnTakeDamage({attacker = equipped, unit = enemy,
    damage = 5, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
near(equipped.health, 600, "equipment lifesteal uses the same victim health conversion")
equipped.survival_endless_health_scale = 10; equipped.health = 100
equipment:OnTakeDamage({attacker = equipped, unit = enemy,
    damage = 5, damage_category = DOTA_DAMAGE_CATEGORY_ATTACK})
near(equipped.health, 150, "equipment lifesteal converts into hero native health")
equipment:OnTakeDamage({attacker = equipped, unit = enemy,
    damage = 5, damage_category = DOTA_DAMAGE_CATEGORY_SPELL})
near(equipped.health, 150, "equipment lifesteal excludes spells under health projection")
enemy.survival_endless_health_scale = nil
hero.survival_endless_health_scale, hero.survival_endless_attack_scale = nil, nil
state.set_numeric(4, "hero_lifesteal_pct", 20)

-- Training stores logical permanent attack. Its engine-facing callback tracks
-- later native projection changes; Step reads the summoned hero's true attack,
-- including morale/training/equipment, rather than a deliberately stale snapshot.
local trained = unit(4); trained.real_hero = true
trained.survival_endless_attack_scale = 10
training:OnAttackLanded({attacker = trained, target = dummy})
near(trained.survival_rogue_dummy_attack_bonus, 100, "training retains logical attack")
local training_attack = trained.modifiers.modifier_rogue_training_attack
near(training_attack:GetModifierPreAttack_BonusDamage(), 10, "training enters native attack units")
trained.survival_endless_attack_scale = 20
near(training_attack:GetModifierPreAttack_BonusDamage(), 5, "training follows later attack projection")
near(training_attack.value, 100, "projection never changes stored permanent attack")
trained.survival_endless_attack_scale = 10
trained:AddNewModifier(trained, nil, "modifier_rogue_combat_bonus", {player_id = 4})
local recipient = unit(4, "arrow_tower", 5)
recipient.survival_endless_attack_scale = 5
local step = recipient:AddNewModifier(recipient, nil, "modifier_rogue_combat_bonus", {player_id = 4})
heroes[4], hero_attacks[4] = trained, 9999
near(trained:GetAverageTrueAttackDamage(), 140, "true native hero attack includes morale and training")
near(step:GetModifierPreAttack_BonusDamage(), 28, "step prefers true hero attack and both native scales")
trained.survival_endless_attack_scale, trained.base_damage = 20, 50
near(step:GetModifierPreAttack_BonusDamage(), 28, "step preserves logical attack after hero reprojection")
local trained_equipment = trained:AddNewModifier(trained, nil, "modifier_equipment_effects", {player_id = 4})
near(step:GetModifierPreAttack_BonusDamage(), 30, "step includes real equipment flat attack")
local native_getter = trained.GetAverageTrueAttackDamage
hero_attacks[4] = 3000
trained.GetAverageTrueAttackDamage = function() error("native getter unavailable") end
near(step:GetModifierPreAttack_BonusDamage(), 60, "step safely falls back when native getter throws")
server = false
near(step:GetModifierPreAttack_BonusDamage(), 60, "client getter failure uses logical snapshot fallback")
server = true
trained.GetAverageTrueAttackDamage = function() return 0 / 0 end
near(step:GetModifierPreAttack_BonusDamage(), 60, "invalid native attack uses snapshot fallback")
trained.GetAverageTrueAttackDamage = native_getter
heroes[4], hero_attacks[4] = nil, 0
near(step:GetModifierPreAttack_BonusDamage(), 0, "unsummoned hero has no attack projection")
heroes[4], hero_attacks[4] = hero, 2500

-- Equipment also transmits its native flat value to the client, while a later
-- server-side attack scale update recomputes from the original logical amount.
near(trained_equipment:GetModifierPreAttack_BonusDamage(), 5, "equipment flat attack enters native units")
trained_equipment:HandleCustomTransmitterData(trained_equipment:AddCustomTransmitterData())
server = false
near(trained_equipment:GetModifierPreAttack_BonusDamage(), 5, "client receives equipment native flat attack")
server = true
trained.survival_endless_attack_scale = 10
near(trained_equipment:GetModifierPreAttack_BonusDamage(), 10, "equipment attack follows new native projection")

-- Sharp Volley grants logical +1 for each landed attack. Ordinary and ultimate
-- towers share the event consumer; neither may amplify the permanent gain by
-- its native attack projection, and later scale changes retain the hit count.
assert(runtime.grant(4, "sharp_volley", "combat:4:sharp_volley", "builder_start").ok)
local sharp_tower = unit(4, "arrow_tower", 5)
local sharp_ultimate = unit(4); sharp_ultimate.survival_ultimate_tower = true
for _, tower in ipairs({sharp_tower, sharp_ultimate}) do
    tower.survival_endless_attack_scale = 10
    bus.emit(events.TOWER_ATTACK_LANDED, {tower = tower, target = enemy})
    local growth = assert(tower.modifiers.modifier_rogue_sharp_volley_growth)
    near(growth:GetModifierPreAttack_BonusDamage(), 0.1, "sharp volley grants one logical attack")
    bus.emit(events.TOWER_ATTACK_LANDED, {tower = tower, target = enemy})
    near(growth:GetStackCount(), 2, "each landed event increments its own tower")
    near(growth:GetModifierPreAttack_BonusDamage(), 0.2, "two sharp hits restore two logical attack")
    tower.survival_endless_attack_scale = 20
    near(growth:GetModifierPreAttack_BonusDamage(), 0.1, "sharp growth follows later attack projection")
end
bus.emit(events.TOWER_ATTACK_LANDED, {tower = roster[0][1].unit, target = enemy})
assert(not roster[0][1].unit:HasModifier("modifier_rogue_sharp_volley_growth"), "sharp volley owner isolation")

-- Use real Deal/repository/adapter provenance, including a native SPELL=0
-- category. Trusted replacement attack tags pierce armor without restoring
-- the attacker's native scale; arbitrary script/spell transactions stay out.
local combat_events = require("combat/combat_events")
local rules = require("combat/damage_rule_config")
local repository = require("combat/damage_transaction_repository")
local damage_service = require("combat/damage_service")
repository.init(rules)
filter.init({event_bus = bus, events = combat_events, repository = repository, config = rules})
damage_service.init({event_bus = bus, events = combat_events, repository = repository,
    rules = rules, context = require("combat/damage_context"),
    adapter = require("adapters/dota_damage_adapter"), debug = {log = function() end}})
local submitted, requested, filtered
bus.subscribe(combat_events.DAMAGE_SUBMITTED, function(p) submitted = p end)
bus.subscribe(combat_events.DAMAGE_REQUESTED, function(p) requested = p end)
ApplyDamage = function(p)
    filtered = {entindex_attacker_const = p.attacker:entindex(),
        entindex_victim_const = p.victim:entindex(), damage = p.damage,
        damagetype_const = p.damage_type, damage_category_const = DOTA_DAMAGE_CATEGORY_SPELL}
    assert(filter._filter_for_test(filter, filtered))
    return filtered.damage
end
local machine_gun = unit(4, "arrow_tower", 6, "class_4")
machine_gun.survival_endless_attack_scale = 100
local piercing_hit = 100 * armor.war3_physical_damage_multiplier(98, 40)
assert(modifier_tower_attack_effects._fire_machine_gun_hit_for_test({}, machine_gun, enemy, 1))
assert(requested.tags[1] == "tower_machine_gun_attack", "real machine-gun tag")
near(submitted.final_damage, piercing_hit, "real machine-gun Deal honors iron fist")
for _, entry in ipairs({
    {source = "script", tag = "tower_laser_attack", pierce = 40},
    {source = "splash", tag = "tower_multi_arrow", pierce = 40},
    {source = "ability", tag = "tower_machine_gun_attack", pierce = 0},
    {source = "script", tag = "tower_ice_blizzard", pierce = 0},
    {source = "script", tag = "unknown_attack", pierce = 0},
    {source = "script", tag = "tower_multi_arrow", pierce = 0},
    {source = "splash", tag = "tower_laser_attack", pierce = 0},
}) do
    local result = damage_service:Deal({attacker = machine_gun, victim = enemy,
        base_damage = 100, damage_type = DAMAGE_TYPE_PHYSICAL, source_kind = entry.source,
        tags = {entry.tag}, can_crit = false})
    assert(result.success)
    near(result.final_damage, 100 * armor.war3_physical_damage_multiplier(98, entry.pierce),
        entry.tag .. "/" .. entry.source .. " respects provenance")
end
local spell = damage_service:Deal({attacker = machine_gun, victim = enemy,
    base_damage = 100, damage_type = DAMAGE_TYPE_MAGICAL, source_kind = "script",
    tags = {"tower_machine_gun_attack"}, can_crit = false})
near(spell.final_damage, 100, "magical damage does not use iron fist")
local combined = damage_service:Deal({attacker = machine_gun, victim = enemy,
    base_damage = 100, damage_type = DAMAGE_TYPE_PHYSICAL, source_kind = "splash",
    physical_armor_ignore_pct = 30, tags = {"tower_multi_arrow"}, can_crit = false})
near(combined.final_damage, 100 * armor.war3_physical_damage_multiplier(98, 70),
    "own piercing skill and iron fist combine once")
local ultimate = unit(4); ultimate.survival_ultimate_tower = true
ultimate.survival_endless_attack_scale = 10
near(hit(ultimate, enemy, 10, DAMAGE_TYPE_PHYSICAL), piercing_hit,
    "ultimate native attack restores scale and pierces armor")
local ultimate_hit = damage_service:Deal({attacker = ultimate, victim = enemy,
    base_damage = 100, damage_type = DAMAGE_TYPE_PHYSICAL, source_kind = "script",
    tags = {"tower_machine_gun_attack"}, can_crit = false})
near(ultimate_hit.final_damage, piercing_hit, "ultimate replacement attack pierces without restoring scale")
assert(ultimate.survival_building_id == nil, "ultimate business identity is preserved")
assert(repository.debug_snapshot().pending_records == 0, "no stranded damage provenance")
print("ROGUE_BOSS_COMBAT_PASS checks=" .. checks .. "; real config/lifecycle/modifiers/filter; engine boundary simulated")
