-- Exercise the real request router, selected push, NetTable publisher and
-- modifier getters. Native stat-frame reads deliberately disagree with the
-- authoritative hero snapshot to reproduce the former 95%/100% alternation.
package.path = "scripts/vscripts/?.lua;" .. package.path

local listeners, sent, tables, entities = {}, {}, {}, {}
local clock, native_reads, full_modifier_scans = 0, 0, 0
local player = {}
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    GetPlayer = function(_, id) if id == 0 then return player end end,
    GetTeam = function() return 2 end,
}
GameRules = {GetGameTime = function() return clock end}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback) listeners[name] = callback end,
    Send_ServerToPlayer = function(_, handle, name, snapshot)
        assert(handle == player)
        sent[#sent + 1] = {name = name, snapshot = snapshot}
    end,
}
CustomNetTables = {SetTableValue = function(_, name, key, snapshot)
    if name == "survival_combat_stats" then tables[#tables + 1] = snapshot end
end}
EntIndexToHScript = function(index) return entities[index] end
for _, name in ipairs({"systems/building_system", "ui/weapon_synthesis_snapshot_service",
    "systems/hero_summon_projection", "systems/building_batch_upgrade_service",
    "systems/gold_mine_batch_upgrade_service"}) do package.loaded[name] = {} end
package.loaded["systems/startup_loading_service"] = {is_player_ready = function() return true end}
class = function(definition) return definition or {} end
IsServer = function() return true end

local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local router = require("ui/ui_request_router")
local publisher = require("ui/combat_stats_ui_service")
local managed = require("modifiers/modifier_survival_managed_buff")
local passive = require("modifiers/modifier_hero_passive_skill_effects")
-- Supply one stat-skill row so this exercises the real definition/level/
-- activation getter, rather than replacing it with a fixed-return mock.
local skill_definitions = require("config/generated/hero_skill_definitions")
skill_definitions.rows[#skill_definitions.rows + 1] = {
    ability_name = "ability_test_cadence_skill", enabled = true,
    effect_type = "attack_speed_bonus", effect_value_per_level = 15,
}
local stat_skill = require("modifiers/modifier_survival_hero_skill")
table.remove(skill_definitions.rows)
local raw, hero

local function near(value, expected, message)
    assert(type(value) == "number" and math.abs(value - expected) < 0.000001,
        (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(value))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, nested in pairs(value) do result[key] = clone(nested) end
    return result
end
local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function unit(index)
    local result = {index = index, modifiers = {}, factor = .95, alive = true, owner = 0}
    function result:entindex() return self.index end
    function result:IsNull() return self.invalid == true end
    function result:IsAlive() return self.alive end
    function result:GetPlayerOwnerID() return self.owner end
    function result:FindModifierByName(name) return (self.modifiers[name] or {})[1] end
    function result:FindAllModifiersByName(name)
        assert(name == "modifier_survival_managed_buff" or name == "modifier_hero_passive_skill_effect"
            or name == "modifier_survival_hero_skill",
            "hero projection must only query its temporary effect families: " .. name)
        return self.modifiers[name] or {}
    end
    function result:FindAllModifiers() full_modifier_scans = full_modifier_scans + 1; error("full modifier scan") end
    function result:GetAttackSpeed(ignore) assert(ignore == false); native_reads = native_reads + 1; return self.factor end
    function result:GetAttacksPerSecond(ignore) assert(ignore == false); native_reads = native_reads + 1; return self.factor / 1.5 end
    entities[index] = result
    return result
end
local function advance(delay) clock = clock + delay; scheduler.think() end
local function initialize(publisher_first)
    scheduler.clear(); bus.reset()
    listeners, sent, tables, entities = {}, {}, {}, {}
    hero = unit(201)
    bus.handle_request(events.HERO_COMBAT_STATS_GET_REQUEST, function(payload)
        assert(payload.player_id == 0)
        return {ok = true, snapshot = raw}
    end)
    if publisher_first then publisher.init(); router.init() else router.init(); publisher.init() end
end
local function snapshot(pct, old_cheer, legacy_interval)
    local base = 1.5
    return {hero_id = "hero_doom", entindex = 201, refresh_version = 7,
        unit_name = "npc_dota_hero_doom_bringer", display_name = "Doom", level = 1,
        attack_min = 40, attack_max = 50, health = 100, max_health = 100,
        armor = 10, runtime_armor = 3, stat_units_version = 2,
        strength = 12, agility = 6, intellect = 4, base_attack_time = base,
        attack_speed = pct / (base * 100),
        attack_cadence = {base_interval = base, reduced_interval = base,
            percentage = pct, cheer_bonus = old_cheer or 0,
            engine_interval = legacy_interval or base * 100 / pct,
            interval_reductions = {}, speed_bonuses = {{label = "装备", value = 150},
                {label = "科技与存档", value = 0}, {label = "欢呼光环", value = old_cheer or 0}}}}
end
local function selected(index)
    local count = #sent
    listeners.ui_selected_unit_stats_request(nil, {PlayerID = 0, entindex = index or 201})
    assert(#sent == count + 1 and sent[#sent].name == "ui_selected_unit_stats_snapshot")
    assert(sent[#sent].snapshot.success == 1)
    return sent[#sent].snapshot
end
local function check(value, pct, message)
    near(value.attack_speed_percentage, pct, message .. " percent")
    near(value.stat_tooltips.attack_speed.percentage, pct, message .. " tooltip percent")
    near(value.attack_speed, pct / 150, message .. " frequency")
    near(value.stat_tooltips.attack_speed.attack_interval, 150 / pct, message .. " interval")
    assert(value.refresh_version == 7, "projection must retain authoritative version")
end
local function channels(pct, message)
    local before = clone(raw)
    local requested = selected()
    check(requested, pct, message .. " request")
    local count = #sent
    bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = raw})
    check(tables[#tables], pct, message .. " NetTable")
    advance(.11)
    if #sent > count then check(sent[#sent].snapshot, pct, message .. " push") end
    assert(equal(raw, before), "UI projection mutated authoritative frequency/cadence")
    return requested
end
local function unit_change(pct, message, duplicate)
    local before, table_count, send_count = clone(raw), #tables, #sent
    bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {entindex = hero:entindex(), unit = hero,
        reason = "test_skill_cadence_changed"})
    assert(#tables == table_count + 1, "one UNIT event must refresh the regular hero table")
    check(tables[#tables], pct, message .. " NetTable")
    advance(.11)
    if not duplicate then assert(#sent == send_count + 1, "changed UNIT cadence must push selected UI") end
    check(sent[#sent].snapshot, pct, message .. " selected push")
    assert(equal(raw, before), "UNIT event must reuse immutable raw authority")
end
local function effect(class_definition, fields)
    local result = setmetatable(fields or {}, {__index = class_definition})
    function result:IsNull() return false end
    function result:GetParent() return hero end
    function result:SetStackCount(value) self.stack = value end
    function result:GetStackCount() return self.stack or 0 end
    function result:SetDuration() end
    return result
end

for _, publisher_first in ipairs({false, true}) do
    initialize(publisher_first)
    raw = snapshot(100)
    bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {entindex = 201, unit = hero})
    assert(#tables == 0, "a UNIT event before the first authority snapshot must do no work")
    for _, factor in ipairs({.95, 1, .95, 1}) do
        hero.factor = factor
        channels(100, "same version, native frame " .. factor)
    end
    -- Already accelerated snapshots must not have equipment/technology/cheer
    -- applied twice; live cheer changes reach both transports before recalc.
    raw = snapshot(300, 20)
    raw.equipment_attack_speed_pct, raw.hero_attack_speed_bonus_pct = 80, 70
    raw.attack_cadence.speed_bonuses[1].value, raw.attack_cadence.speed_bonuses[2].value = 80, 70
    hero.survival_cheer_attack_speed_pct = 20
    channels(300, "equipment/technology/cheer already included")
    local ability = {level = 2, activated = true, removed = false}
    function ability:IsNull() return self.removed end
    function ability:IsActivated() return self.activated end
    function ability:GetAbilityName() return "ability_test_cadence_skill" end
    function ability:GetLevel() return self.level end
    local attack_skill = effect(stat_skill)
    function attack_skill:GetAbility() return ability end
    hero.modifiers.modifier_survival_hero_skill = {attack_skill}
    unit_change(336, "actual skill adds 30 IAS to equipment/technology exactly once")
    ability.level = 3
    unit_change(354, "actual skill level changes its bonus")
    ability.activated = false
    unit_change(300, "inactive skill contributes zero")
    ability.activated, ability.removed = true, true
    unit_change(300, "removed skill ability contributes zero", true)
    hero.modifiers.modifier_survival_hero_skill = nil
    hero.survival_cheer_attack_speed_pct = 40
    local cheer = channels(350, "current cheer replaces stored cheer once")
    near(cheer.attack_cadence.cheer_bonus, 40)
    near(cheer.attack_cadence.speed_bonuses[3].value, 40)
    hero.survival_cheer_attack_speed_pct = 0
    channels(250, "cheer removal restores static cadence")

    local flat = effect(managed, {definition = {effect_type = "attack_speed_bonus"}, value = 30})
    local slow = effect(managed, {definition = {effect_type = "attack_speed_pct"}, value = -20})
    local skill = effect(passive, {effect_type = "attack_slow", effect_value = 5})
    hero.modifiers.modifier_survival_managed_buff = {flat, slow}
    hero.modifiers.modifier_hero_passive_skill_effect = {skill}
    hero.survival_cheer_attack_speed_pct = 40
    channels(322, "constant IAS plus combined cheer/managed/skill percentages")
    hero.modifiers = {}; hero.survival_cheer_attack_speed_pct = 0
    raw = snapshot(100)
    hero.modifiers.modifier_hero_passive_skill_effect = {skill}
    channels(95, "real 5 percent skill slow is retained")
    hero.modifiers = {}
    channels(100, "skill slow removal")

    -- Only the real UNIT lifecycle event updates both transports here. No
    -- synthetic HERO change may disguise a stale NetTable after a live buff.
    selected()
    local five_percent = effect(managed)
    hero.modifiers.modifier_survival_managed_buff = {five_percent}
    local table_count, before = #tables, clone(raw)
    five_percent:OnCreated({buff_id = "debuff_hero_ice_cone_attack_slow", managed_value = -5})
    advance(.001); advance(.11)
    assert(#tables == table_count + 1)
    check(tables[#tables], 95, "actual five-percent managed apply NetTable")
    check(sent[#sent].snapshot, 95, "actual five-percent managed apply push")
    unit_change(95, "duplicate buff event does not multiply projected 95 again", true)
    unit_change(95, "third buff event still starts from raw 100", true)
    assert(equal(raw, before), "buff events must not replace the cached raw authority with 95")
    hero.modifiers.modifier_survival_managed_buff = nil
    table_count = #tables
    five_percent:OnDestroy(); advance(.001); advance(.11)
    assert(#tables == table_count + 1)
    check(tables[#tables], 100, "actual five-percent removal NetTable")
    check(sent[#sent].snapshot, 100, "actual five-percent removal push")
    local ice = effect(managed)
    hero.modifiers.modifier_survival_managed_buff = {ice}
    table_count = #tables
    ice:OnCreated({buff_id = "debuff_hero_ice_cone_attack_slow", managed_value = -40})
    advance(.001); advance(.11)
    assert(#tables == table_count + 1)
    check(tables[#tables], 60, "actual ice-cone apply NetTable")
    check(sent[#sent].snapshot, 60, "actual ice-cone apply push")
    hero.modifiers.modifier_survival_managed_buff = nil
    table_count = #tables
    ice:OnDestroy(); advance(.001); advance(.11)
    assert(#tables == table_count + 1)
    check(tables[#tables], 100, "actual ice-cone removal NetTable")
    check(sent[#sent].snapshot, 100, "actual ice-cone removal push")

    -- Legacy engine_interval metadata has a different meaning. Its already
    -- calculated frequency remains authoritative through both transports.
    raw = snapshot(220, 10, 1.2)
    hero.survival_cheer_attack_speed_pct = 10
    channels(220, "legacy cadence metadata, no duplicate scaling")
    hero.survival_cheer_attack_speed_pct = 30
    channels(260, "legacy cadence supports live cheer")
    hero.modifiers.modifier_survival_managed_buff = {slow}
    channels(220, "legacy cadence supports real slow")

    raw = snapshot(1500)
    hero.modifiers.modifier_debug_fixed_attack_rate = {{GetModifierFixedAttackRate = function() return .1 end}}
    channels(1500, "fixed native cadence ignores IAS effects")
    hero.modifiers.modifier_debug_fixed_attack_rate = nil
    raw.debug_attack_speed_override = 10
    channels(1500, "debug override retains complete frequency")

    local monkey = unit(202)
    monkey.survival_monkey_king_clone, monkey.survival_attack_speed = true, 3.5
    local original = clone(raw)
    local cloned = selected(202)
    near(cloned.attack_speed, 3.5, "clone uses its cached frequency")
    near(cloned.attack_speed_percentage, 525, "clone cadence uses its own frequency")
    assert(cloned.entindex == 202 and equal(raw, original), "clone must preserve owner's snapshot")
end
-- Stale/dead handles, hero replacement and init reuse must not republish a
-- previous hero's cached values or install duplicate regular/UNIT listeners.
raw = snapshot(100)
hero.modifiers, hero.survival_cheer_attack_speed_pct = {}, 0
channels(100, "lifecycle baseline")
local table_count = #tables
local function ignored_unit(target, message)
    bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {entindex = target:entindex(), unit = target})
    assert(#tables == table_count, message)
end
hero.modifiers.modifier_survival_managed_buff = {
    effect(managed, {definition = {effect_type = "attack_speed_pct"}, value = -5}),
}
hero.alive = false; ignored_unit(hero, "dead hero must not refresh via delayed buff event")
hero.alive = true
bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {entindex = 201, unit = hero})
assert(#tables == table_count + 1, "revived same entity must retain raw authority for UNIT refresh")
check(tables[#tables], 95, "revived hero UNIT NetTable")
advance(.11); check(sent[#sent].snapshot, 95, "revived hero UNIT selected push")
hero.modifiers.modifier_survival_managed_buff = nil
bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {entindex = 201, unit = hero})
assert(#tables == table_count + 2, "revived hero buff removal must refresh without HERO recalculation")
check(tables[#tables], 100, "revived hero removal NetTable")
advance(.11); check(sent[#sent].snapshot, 100, "revived hero removal selected push")
table_count = #tables
hero.owner = 1; ignored_unit(hero, "transferred hero must not refresh old owner")
hero.owner = 0; hero.invalid = true; ignored_unit(hero, "invalid cached hero must not refresh")
hero.invalid = false
local reused = unit(201)
ignored_unit(hero, "reused entity index must reject stale cached handle")
ignored_unit(reused, "new handle at same index must not inherit old hero authority")
entities[201] = hero
bus.emit(events.HERO_REMOVED, {player_id = 0, unit = hero})
ignored_unit(hero, "removed hero must clear cache even without debug state")
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = raw})
table_count = #tables
local old_hero, replacement = hero, unit(203)
bus.emit(events.HERO_SUMMONED, {player_id = 0, unit = replacement})
ignored_unit(old_hero, "new summon must retire old hero cache")
hero, raw = replacement, snapshot(100)
raw.entindex = 203
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = raw})
table_count = #tables
bus.emit(events.HERO_SUMMONED, {player_id = 0, unit = replacement})
bus.emit(events.HERO_REMOVED, {player_id = 0, unit = old_hero})
ignored_unit(old_hero, "old hero removal/event must not refresh the replacement")
bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {entindex = 203, unit = replacement})
assert(#tables == table_count + 1, "same-hero summon/removal ordering must retain new raw snapshot")
publisher.init(); publisher.init()
table_count = #tables
ignored_unit(replacement, "reinitialization must start with no cached authority")
bus.emit(events.HERO_COMBAT_STATS_CHANGED, {player_id = 0, snapshot = raw})
assert(#tables == table_count + 1, "reinitialization must not duplicate regular listeners")
table_count = #tables
bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {entindex = 203, unit = replacement})
assert(#tables == table_count + 1, "reinitialization must install only one UNIT listener")
assert(native_reads == 0 and full_modifier_scans == 0,
    "hero UI must neither reread native attack-speed frames nor scan all modifiers")
print("HERO_ATTACK_CADENCE_CHANNELS_PASS: same-version NetTable/request/push, 95/100 native frame disagreement, additive equipment/technology, real skill IAS/levels/activation, live cheer, UNIT-only managed 95/60 apply/remove across both transports, repeated events use raw authority, legacy metadata, fixed/debug rates, clone isolation, dead/removed/transferred/reused entity safeguards, replacement/init listener lifecycle, no native rereads/full modifier scans")
