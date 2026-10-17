package.path = "scripts/vscripts/?.lua;" .. package.path

-- Exercise real fusion, card grants, technology snapshots and modifier getters.
-- Only engine entities, placement and the seven route CSV rows are mocked.
class = function(value) return value end
LinkLuaModifier = function() end
IsServer = function() return true end
LUA_MODIFIER_MOTION_NONE, DOTA_UNIT_CAP_RANGED_ATTACK = 0, 2
MODIFIER_PROPERTY_BASEDAMAGEOUTGOING_PERCENTAGE = 1
MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE = 2
GameRules = {GetGameTime = function() return 0 end}
PlayerResource = {GetPlayer = function() return {} end, GetTeam = function() return 2 end}
package.loaded["systems/player_context_service"] = {is_defeated = function() return false end}
package.loaded["config/tower_route_config"] = {
    get_route = function() return {{level = 10, base_attack_damage = 10}} end,
    get = function() return {display_name = "test tower"} end,
    display_name = function(row) return row.display_name end,
    current = function(state) return state.level == 10 and {level = 10} or nil end,
    row_at_level = function(_, level) return level <= 10 and {level = level} or nil end,
}
package.loaded["systems/tower_skill_runtime"] = {apply = function() end}
package.loaded["systems/tower_ability_sync"] = {sync = function() end}
local vector_mt = {}
Vector = function(x, y, z) return setmetatable({x = x, y = y, z = z or 0}, vector_mt) end
vector_mt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector_mt.__index = {Length2D = function(v) return math.sqrt(v.x * v.x + v.y * v.y) end}
local bus, events = require("core/event_bus"), require("core/events")
require("modifiers/modifier_rogue_combat_effects")
require("modifiers/modifier_rogue_reward_effects")
local ultimate_modifier = require("modifiers/modifier_rogue_ultimate_tower_effects")
local range_modifier = require("modifiers/modifier_survival_hero_attack_range")
local runtime = require("systems/rogue_effect_runtime_service")
local technology = require("systems/technology_stat_manager")
local fusion = require("systems/tower_fusion_service")
local rules = require("config/tower_combat_rules")
local material, extra, hero, created, next_index, consumed
local function close(actual, expected, reason)
    assert(math.abs(actual - expected) < 0.00001,
        (reason or "value") .. ": actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
end
local function unit(index, owner, is_hero)
    local result = {index = index, survival_player_id = owner, hero = is_hero,
        base_damage = is_hero and 100 or 10, modifiers = {}, abilities = {}, position = Vector(0, 0, 0)}
    function result:IsNull() return self.removed == true end
    function result:IsAlive() return not self.removed and not self.dead end
    function result:IsRealHero() return self.hero == true end
    function result:entindex() return self.index end
    function result:GetTeamNumber() return 2 end
    function result:GetAbsOrigin() return self.position end
    function result:SetAbsOrigin(value) self.position = value end
    function result:GetMaxHealth() return 100 end
    function result:GetHealth() return 100 end
    function result:GetPhysicalArmorBaseValue() return 2 end
    function result:SetBaseDamageMin(value) self.base_damage = value end
    function result:SetBaseDamageMax(value) close(self.base_damage, value) end
    function result:SetBaseAttackTime(value) self.bat = value end
    function result:SetAcquisitionRange(value) self.acquisition = value end
    function result:GetAttackRange()
        local modifier = self.modifiers.modifier_survival_hero_attack_range
        return modifier and modifier:GetModifierAttackRangeOverride() or 800
    end
    function result:HasModifier(name) return self.modifiers[name] ~= nil end
    function result:FindModifierByName(name) return self.modifiers[name] end
    function result:GetAverageTrueAttackDamage()
        local pct, flat = 0, 0
        for _, modifier in pairs(self.modifiers) do
            if modifier.GetModifierBaseDamageOutgoing_Percentage then
                pct = pct + modifier:GetModifierBaseDamageOutgoing_Percentage()
            end
            if modifier.GetModifierPreAttack_BonusDamage then
                flat = flat + modifier:GetModifierPreAttack_BonusDamage()
            end
        end
        return self.base_damage * (1 + pct / 100) + flat
    end
    function result:AddNewModifier(_, _, name, kv)
        local prototype = name == "modifier_rogue_combat_bonus" and modifier_rogue_combat_bonus
            or name == "modifier_rogue_tower_attack_projection" and modifier_rogue_tower_attack_projection
            or name == "modifier_rogue_ultimate_tower_effects" and ultimate_modifier
            or name == "modifier_survival_hero_attack_range" and range_modifier or {}
        local modifier = setmetatable({GetParent = function() return self end,
            SetStackCount = function(m, value) m.stack = value end,
            GetStackCount = function(m) return m.stack or 0 end,
            Destroy = function() self.modifiers[name] = nil end}, {__index = prototype})
        self.modifiers[name] = modifier
        if modifier.OnCreated then modifier:OnCreated(kv or {}) end
        return modifier
    end
    function result:AddAbility(name)
        local ability = {SetLevel = function() end, SetHidden = function() end, SetActivated = function() end}
        self.abilities[name] = ability
        return ability
    end
    function result:RemoveSelf() self.removed = true end
    for _, name in ipairs({"SetPlayerID", "SetOwner", "SetControllableByPlayer", "SetAttackCapability",
        "SetModel", "SetOriginalModel", "SetBaseMaxHealth", "SetMaxHealth", "SetHealth",
        "SetPhysicalArmorBaseValue"}) do result[name] = function() end end
    if not is_hero then result.survival_building_id = "arrow_tower" end
    return result
end
CreateUnitByName = function()
    next_index = next_index + 1
    created = unit(next_index, 0)
    created.survival_building_id = nil
    return created
end
local function row(index, owner)
    return {unit = unit(index, owner), entindex = index, player_id = owner,
        building_id = "arrow_tower", tower_class = "class_" .. index,
        route_level = 10, level = 10, definition = {footprint = {x = 2, y = 2}}}
end
local function reset()
    material, extra, next_index, consumed = {}, {}, 200, false
    for index = 1, 7 do material[index] = row(index, 0) end
    hero = unit(500, 0, true)
    bus.reset(); technology.init(); runtime.init(); fusion.init()
    bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
        local result = {}
        for _, source in ipairs(consumed and extra or material) do
            if source.player_id == payload.player_id then result[#result + 1] = source end
        end
        return {buildings = result}
    end)
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST, function(payload)
        return {unit = payload.player_id == 0 and hero or nil}
    end)
    bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function() return {snapshot = {}} end)
    bus.handle_request(events.GRID_CAN_PLACE_REQUEST, function(payload)
        return {ok = true, grid_x = 0, grid_y = 0, world_position = payload.position}
    end)
    bus.handle_request(events.GRID_OCCUPY_REQUEST, function() return {ok = true} end)
    bus.handle_request(events.BUILDING_FUSION_CONSUME_REQUEST, function(payload)
        assert(#payload.entindexes == 7); consumed = true; return {ok = true}
    end)
end
local function grant(card, owner, kind)
    local result = runtime.grant(owner or 0, card, "test:" .. card .. ":" .. tostring(owner or 0), kind or "boss")
    assert(result and result.ok, tostring(result and result.error))
end
local function fuse()
    local result = bus.request(events.TOWER_FUSION_REQUEST, {caster = material[1].unit})
    assert(result and result.ok)
    assert(result.unit.survival_building_id == nil and result.unit.survival_ultimate_tower)
    assert(not result.unit:HasModifier("modifier_rogue_combat_bonus"))
    return result.unit
end

reset()
grant("sharp_volley", 0, "builder_start"); grant("fortifications")
grant("high_morale"); grant("tower_network"); grant("in_step")
close(material[1].unit:GetAverageTrueAttackDamage(), 29.5)
local tower = fuse()
local baked = tower.base_damage
close(baked, 346.5, "seven actual material attacks remain inherited")
close(tower:GetAverageTrueAttackDamage(), baked, "pre-fusion bonuses are not applied twice")
close(tower.survival_attack_speed, 3 * 1.26, "final technology includes both speed cards once")
local bat_writes, initial_bat_setter = 0, tower.SetBaseAttackTime
tower.SetBaseAttackTime = function(self, value)
    bat_writes = bat_writes + 1
    initial_bat_setter(self, value)
end
for i = 1, 100 do
    bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0, changed_section = "lumberjack",
        snapshot = {final = {tower = {attack_speed_bonus_pct = 999, attack_flat = 999}}}})
end
assert(bat_writes == 0, "per-hit worker growth cannot rewrite ultimate cadence")
close(tower:GetAverageTrueAttackDamage(), baked, "worker growth cannot replace cached tower flat damage")
for i = 1, 100 do
    bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0, changed_section = "tower",
        snapshot = technology.get(0)})
end
assert(bat_writes == 0, "identical tower totals cannot repeatedly rewrite native attack timing")
close(tower.bat, 1 / (3 * 1.26))
hero.base_damage = 200
close(tower:GetAverageTrueAttackDamage(), baked + 13, "hero growth projects only the new ultimate delta")
hero.survival_endless_attack_scale, hero.base_damage = 10, 20
close(tower:GetAverageTrueAttackDamage(), baked + 13, "hero native scaling restores the same logical projection")
tower.survival_endless_attack_scale = 10
close(tower:FindModifierByName("modifier_rogue_ultimate_tower_effects"):GetModifierPreAttack_BonusDamage(), 1.3)
tower.survival_endless_attack_scale = nil
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {researcher_super_tower_range = 2}})
close(rules.current_attack_range(tower), 860, "research changes native range through range override")
for i = 1, 3 do
    bus.emit(events.TOWER_FUSION_RUNTIME_CHANGED, {unit = tower, player_id = 0, building_id = "ultimate_tower"})
    close(tower.survival_attack_speed, 3 * 1.26)
    close(tower.base_damage, baked, "movement/technology preserve inherited base attack")
    close(tower:GetAverageTrueAttackDamage(), baked + 13)
end
grant("fortifications", 1)
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 1, levels = {researcher_super_tower_range = 4}})
close(rules.current_attack_range(tower), 860, "same-team other owner research stays isolated")
close(tower.survival_attack_speed, 3 * 1.26)
hero = nil
close(tower:GetAverageTrueAttackDamage(), baked - 13, "missing hero removes new dynamic projection without resetting inheritance")
tower.survival_tower_personal_attack_growth = 100
bus.emit("tower.personal_attack_changed", {tower = tower, player_id = 0})
close(tower.base_damage, baked + 100, "personal growth still uses original fusion inheritance path")

reset(); tower = fuse(); close(tower.base_damage, 210)
grant("high_morale")
close(tower:GetAverageTrueAttackDamage(), 273, "morale first received after fusion applies immediately")
for i = 1, 3 do extra[#extra + 1] = row(20 + i, 0) end
extra[#extra + 1] = row(30, 1)
grant("tower_network")
close(tower:GetAverageTrueAttackDamage(), 304.5, "new network snapshot reaches ultimate and counts only own final towers")
grant("in_step")
close(tower:GetAverageTrueAttackDamage(), 317.5, "new in-step card adds one current logical hero projection")
grant("fortifications")
close(tower.survival_attack_speed, 3 * 1.06, "late fortifications refreshes a registered ultimate")
grant("sharp_volley", 0, "builder_start")
close(tower.survival_attack_speed, 3 * 1.26)
hero.base_damage = 200
close(tower:GetAverageTrueAttackDamage(), 330.5, "late in-step tracks hero growth without another reward event")
local server_modifier = tower:FindModifierByName("modifier_rogue_ultimate_tower_effects")
server_modifier:OnIntervalThink()
local client_modifier = setmetatable({}, {__index = ultimate_modifier})
client_modifier:HandleCustomTransmitterData(server_modifier:AddCustomTransmitterData())
IsServer = function() return false end
close(client_modifier:GetModifierBaseDamageOutgoing_Percentage(), 45, "client receives new attack percentages")
close(client_modifier:GetModifierPreAttack_BonusDamage(), 26, "client receives dynamic logical projection")
IsServer = function() return true end
extra = {}
bus.emit(events.BUILDING_DESTROYED, {player_id = 0, unit = unit(23, 0)})
close(tower:GetAverageTrueAttackDamage(), 330.5, "network stays frozen after source towers disappear")
local old_speed = tower.survival_attack_speed
bus.emit(events.TOWER_FUSION_RUNTIME_REMOVED, {entindex = tower:entindex(), player_id = 0})
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0, snapshot = {final = {tower = {attack_speed_bonus_pct = 99}}}})
close(tower.survival_attack_speed, old_speed, "removed ultimate stops receiving technology updates")

reset(); grant("high_morale"); tower = fuse()
close(tower.base_damage, 231, "morale baked only into material extras, not tripled CSV bases")
for i = 1, 3 do extra[#extra + 1] = row(20 + i, 0) end
grant("tower_network")
close(tower:GetAverageTrueAttackDamage(), 231 * 1.15,
    "mixed ordering adds new network percentages to preserved fusion attack")

reset()
bus.handle_request(events.HERO_SKILL_STATE_GET_REQUEST, function()
    return {snapshot = {skills = {{skill_id = "skill_monkey_king_agility", level = 1}}}}
end)
tower = fuse()
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0,
    snapshot = {engine_attack_min = 200, engine_attack_max = 400, critical_chance_pct = 30}})
close(tower.base_damage, 510, "hero R inheritance continues refreshing from fused base")
grant("fortifications")
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {researcher_super_tower_range = 1}})
close(tower.base_damage, 510, "technology refresh never overwrites inherited hero attack")
close(tower.survival_attack_speed, 3 * 1.06)
close(rules.current_attack_range(tower), 830)
close(tower.survival_inherited_critical_chance_pct, 30)

-- Commerce uses seven synthetic rows, so pre-owned cards have no baked baseline.
reset(); grant("high_morale"); grant("tower_network"); grant("in_step"); grant("fortifications")
package.loaded["systems/commerce_effects"] = {owned = function() return true end}
bus.handle_request(events.BUILDING_COUNTS_REQUEST, function() return {ok = true, counts = {arrow_tower = 0}} end)
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function() return {ok = true} end)
local commerce = fusion.commerce_build(0, hero, Vector(0, 0, 0))
assert(commerce and commerce.ok)
close(created.base_damage, 210)
close(created:GetAverageTrueAttackDamage(), 359.5, "commerce applies pre-owned morale/network/in-step once")
close(created.survival_attack_speed, 3 * 1.06)
assert(created.survival_building_id == nil)

-- Technology flat damage must survive a reward received after real fusion.
-- This assertion fails against the old range/cadence-only ultimate consumer.
reset(); tower = fuse()
grant("long_range_volley", 0, "builder_start")
close(technology.get(0).final.tower.attack_flat, 800)
close(tower:GetAverageTrueAttackDamage(), 1010,
    "post-fusion long-range reward projects its real 800 attack once")
close(rules.current_attack_range(tower), 1300)
grant("in_step")
close(tower:GetAverageTrueAttackDamage(), 1020, "technology and live hero projection coexist")
hero.survival_endless_attack_scale, hero.base_damage = 10, 20
close(tower:GetAverageTrueAttackDamage(), 1030, "hero growth preserves the technology delta")
tower.survival_endless_attack_scale = 10
server_modifier = tower:FindModifierByName("modifier_rogue_ultimate_tower_effects")
close(server_modifier:GetModifierPreAttack_BonusDamage(), 82, "both logical flat sources use actual ultimate scale")
server_modifier:OnIntervalThink()
client_modifier = setmetatable({}, {__index = ultimate_modifier})
client_modifier:HandleCustomTransmitterData(server_modifier:AddCustomTransmitterData())
IsServer = function() return false end
close(client_modifier:GetModifierPreAttack_BonusDamage(), 82, "client receives technology plus hero flat damage")
IsServer = function() return true end
tower.survival_endless_attack_scale = nil
local unchanged_base = tower.base_damage
for i = 1, 20 do
    bus.emit(events.TOWER_FUSION_RUNTIME_CHANGED, {unit = tower, player_id = 0})
    bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0, changed_section = "tower", snapshot = technology.get(0)})
end
close(tower.base_damage, unchanged_base, "repeated refresh cannot rebake technology damage")
close(tower:GetAverageTrueAttackDamage(), 1030)
grant("long_range_volley", 1, "builder_start")
close(tower:GetAverageTrueAttackDamage(), 1030, "another owner cannot change the live technology delta")
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {tower_attack = 1}})
close(tower:GetAverageTrueAttackDamage(), 1230, "later genuine tower research also reaches ultimate")

-- Real materials already include pre-owned technology; record its baseline.
reset(); grant("long_range_volley", 0, "builder_start")
for _, source in ipairs(material) do source.unit.base_damage = 810 end
tower = fuse()
close(tower.base_damage, 5810, "seven existing native material bonuses remain baked")
close(tower:GetAverageTrueAttackDamage(), 5810, "pre-owned technology is not added for an eighth time")
close(tower.survival_ultimate_rogue_baseline.technology_attack_flat, 800)
bus.emit(events.TECHNOLOGY_CHANGED, {player_id = 0, levels = {tower_attack = 1}})
close(tower:GetAverageTrueAttackDamage(), 6010, "only post-fusion research delta is projected")

-- Commerce's synthetic materials contain no native technology bonus.
reset(); grant("long_range_volley", 0, "builder_start")
bus.handle_request(events.BUILDING_COUNTS_REQUEST, function() return {ok = true, counts = {arrow_tower = 0}} end)
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST, function() return {ok = true} end)
commerce = fusion.commerce_build(0, hero, Vector(0, 0, 0))
assert(commerce and commerce.ok)
close(created.survival_ultimate_rogue_baseline.technology_attack_flat, 0)
close(created:GetAverageTrueAttackDamage(), 1010, "commerce applies pre-owned technology exactly once")
print("ULTIMATE_TOWER_ROGUE_EFFECTS_PASS: real fusion/grants, preserved material inheritance, before/after deltas, native scaling, final speed/range, owner isolation, idempotent runtime, removal and commerce")
