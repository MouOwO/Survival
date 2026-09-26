-- Reproduce expired handles and retained death-animation corpses.
-- Keep the real upgrade event consumers, route config and reward arithmetic.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/buildings_config")
local noop = function() end
for _, name in ipairs({"tower_skill_runtime", "tower_ability_sync", "building_population_service",
    "building_visual_service", "asset_preload_service", "building_sound_service", "tower_utility_ability_sync",
    "war3_armor_target"}) do
    package.loaded["systems/" .. name] = {reset = noop, apply = noop, sync = noop}
end
package.loaded["debug/dev_wall_stats"] = {apply = noop}
package.loaded["systems/rogue_effect_state_service"] = {wall_health_flat = function() return 0 end}
package.loaded["systems/technology_stat_manager"] = {get = function() return {final = {tower = {}}} end}
package.loaded["systems/player_profile_service"] = {get_profile = function() return nil end}
local cancelled = {}
package.loaded["systems/building_upgrade_process"] = {
    reset = noop, is_active = function() return false end,
    cancel_by_entindex = function(id) cancelled[#cancelled + 1] = id end,
}
local original_print, errors = print, {}
print = function(message, ...)
    if tostring(message):find("[EventBus] handler error", 1, true) then
        errors[#errors + 1] = tostring(message)
    else original_print(message, ...) end
end
PlayerResource = {GetTeam = function() return 2 end}
local world, published = {}, {}
Entities = {FindAllByClassname = function() return world end}
local function make_unit(id)
    local unit = {index = id, damage = 100, survival_player_id = 0, modifiers = {}, null_checks = 0, stat_writes = 0}
    local function live(self) assert(not self.removed, "Invalid object passed to native entity method.") end
    function unit:IsNull() self.null_checks = self.null_checks + 1; return self.removed == true end
    function unit:IsAlive() live(self); return self.dead ~= true end
    function unit:entindex() live(self); return self.index end
    function unit:GetUnitName() live(self); return "building_arrow_tower" end
    function unit:GetPlayerOwnerID() live(self); return 0 end
    function unit:GetTeamNumber() live(self); return 2 end
    function unit:GetBaseDamageMin() live(self); return self.damage end
    function unit:SetBaseDamageMin(value) live(self); self.stat_writes = self.stat_writes + 1; self.damage = value end
    function unit:GetMaxHealth() live(self); return 100 end
    function unit:HasModifier(name) live(self); return self.modifiers[name] ~= nil end
    function unit:AddNewModifier(_, _, name) live(self); self.modifiers[name] = {} end
    for _, method in ipairs({"SetBaseDamageMax", "SetBaseAttackTime", "Script_SetAttackRange",
        "SetAcquisitionRange", "SetProjectileSpeed"}) do unit[method] = live end
    return unit
end
local upgrade = require("systems/building_upgrade_system")
upgrade.init()
local reward = 7
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function()
    return {totals = {tower_attack_flat = reward}}
end)
bus.subscribe(events.BUILDING_CHANGED, function(payload) published[#published + 1] = payload end)
local function register(unit)
    bus.emit(events.BUILDING_CREATED, {unit = unit, entindex = unit.index,
        definition = config.arrow_tower, building_id = "arrow_tower", level = 1,
        team = 2, player_id = 0, base_attack_damage = 100})
end
local removed, survivor = make_unit(10), make_unit(11)
register(removed); register(survivor)
assert(removed.damage == 107 and survivor.damage == 107 and #errors == 0)
removed.removed = true -- No project destroy event, like direct UTIL_Remove.

-- A late availability event reaches publish before the periodic cache cleanup.
bus.emit(events.TOWER_CLASS_COUNTS_CHANGED, {player_id = 0})
assert(#errors == 0, table.concat(errors, "\n"))
assert(#published == 1 and published[1].entindex == 11, "expired state never publishes BUILDING_CHANGED")
published = {}
reward = 13
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, reason = "test_growth"})
assert(#errors == 0, table.concat(errors, "\n"))
assert(survivor.damage == 113 and #published == 1 and published[1].entindex == 11,
    "invalid cache entry must not abort rewards for surviving buildings")
local removed_checks = removed.null_checks
for _ = 1, 10 do
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0})
end
assert(removed.null_checks == removed_checks, "invalid state must be evicted, not rechecked forever")
assert(survivor.damage == 113, "periodic refresh must not compound permanent reward arithmetic")

-- Entity scans can briefly contain a removed handle too. Its owner getter is
-- deliberately unsafe and must run only after validity is established.
removed.survival_player_id = nil
world = {removed, survivor}
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0})
assert(#errors == 0, table.concat(errors, "\n"))
world = {}

-- Normal destroy remains compatible even after native removal; index reuse
-- must subsequently register and update the replacement independently.
survivor.removed = true
bus.emit(events.BUILDING_DESTROYED, {entindex = 11, building_id = "arrow_tower", team = 2})
assert(cancelled[1] == 11)
published = {}
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0})
assert(#published == 0)
local replacement = make_unit(10)
register(replacement)
reward = 19
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0})
assert(replacement.damage == 119 and #published == 1 and published[1].entindex == 10)
assert(#errors == 0, table.concat(errors, "\n"))

-- A tower corpse is still a valid engine entity for several seconds. Neither
-- availability events nor fallback scans may restore its modifiers/stats/UI.
local corpse = make_unit(50)
register(corpse)
corpse.dead = true
corpse.modifiers = {}
local corpse_writes = corpse.stat_writes
published = {}
bus.emit(events.TOWER_CLASS_COUNTS_CHANGED, {player_id = 0})
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {player_id = 0})
world = {corpse, replacement}
for _ = 1, 4 do bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0}) end
register(corpse) -- A delayed creation notification must be harmless too.
assert(corpse.stat_writes == corpse_writes and next(corpse.modifiers) == nil,
    "a retained corpse must never regain combat modifiers or receive stat writes")
for _, payload in ipairs(published) do
    assert(payload.unit ~= corpse and payload.entindex ~= 50,
        "retained corpses must never publish BUILDING_CHANGED")
end

-- Logical destruction also excludes a handle while native IsAlive still says
-- true (for example during a deferred engine death notification).
local logical_dead = make_unit(51)
register(logical_dead)
logical_dead.survival_building_destroyed = true
logical_dead.modifiers = {}
local logical_writes = logical_dead.stat_writes
world = {logical_dead, replacement}
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0})
bus.emit(events.TOWER_CLASS_COUNTS_CHANGED, {player_id = 0})
assert(logical_dead.stat_writes == logical_writes and next(logical_dead.modifiers) == nil,
    "the destruction marker must block recovery before native death completes")

-- A newly allocated unit can reuse an index while the old cache survives a
-- missed destruction event. Recovery must match the handle, not just index.
local stale = make_unit(60)
register(stale)
stale.dead = true
local reused = make_unit(60)
reused.survival_level = 3
world = {reused, replacement}
published = {}
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0})
assert(reused.stat_writes > 0 and reused:HasModifier("modifier_tower_auto_attack"),
    "a replacement must recover its own state rather than inherit the corpse cache")
local found_reused = false
for _, payload in ipairs(published) do
    if payload.entindex == 60 then
        assert(payload.unit == reused and payload.level == 3)
        found_reused = true
    end
end
assert(found_reused, "the surviving replacement must keep publishing normally")
local cancelled_before = #cancelled
bus.emit(events.BUILDING_DESTROYED, {unit = stale, entindex = 60, building_id = "arrow_tower", team = 2})
bus.emit(events.BUILDING_CHANGED, {unit = stale, entindex = 60, level = 99, building_id = "arrow_tower", team = 2})
register(stale)
assert(#cancelled == cancelled_before, "old death must not cancel the replacement's upgrade")
published = {}
bus.emit(events.TECHNOLOGY_STATS_CHANGED, {player_id = 0})
found_reused = false
for _, payload in ipairs(published) do
    if payload.entindex == 60 then
        assert(payload.unit == reused and payload.level == 3,
            "late events from the old handle must not corrupt the replacement")
        found_reused = true
    end
end
assert(found_reused and #errors == 0, table.concat(errors, "\n"))
print("BUILDING_UPGRADE_LIFECYCLE_PASS: expired handle/corpse exclusion/logical death/late publish/scan recovery/live rewards/index reuse/old-event isolation")

-- A teammate's LV5 city never unlocks another owner's farm upgrades.
local own_city, other_city, farm = make_unit(1001), make_unit(1002), make_unit(1003)
function own_city:GetUnitName() return "building_main_city" end
function other_city:GetUnitName() return "building_main_city" end
function farm:GetUnitName() return "building_farm" end
function farm:FindAbilityByName() return nil end
local function register_level(unit, owner, kind, level)
    bus.emit(events.BUILDING_CREATED, {unit = unit, entindex = unit.index,
        definition = kind == "main_city" and config.main_city or config.farm,
        building_id = kind, level = level, team = 2, player_id = owner})
end
register_level(other_city, 1, "main_city", 5)
for target = 2, 5 do
    assert(config.farm.levels[target].requires_city_level == target)
    register_level(own_city, 0, "main_city", target - 1)
    register_level(farm, 0, "building_farm", target - 1)
    local denied = bus.request(events.BUILDING_UPGRADE_QUOTE_REQUEST, {building = farm, player_id = 0})
    assert(denied and not denied.ok, "requires owner's city LV" .. target)
    register_level(own_city, 0, "main_city", target)
    local allowed = bus.request(events.BUILDING_UPGRADE_QUOTE_REQUEST, {building = farm, player_id = 0})
    assert(allowed and allowed.ok and allowed.target_level == target, "unlocks at own city LV" .. target)
end
assert(#errors == 0, table.concat(errors, "\n"))
print("FARM_CITY_GATE_PASS: LV1-5 and same-team owner isolation")


local scans=0
Entities.FindAllByClassname=function() scans=scans+1;return world end
published={}
for i=1,200 do
    bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0,changed_section="lumberjack",changed_field="attack",reason="lumberjack_attack_growth"})
end
assert(scans==0 and #published==0,"harvest growth must not rescan/rebuild unrelated buildings")
bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0,reason="research_completed"})
assert(scans>0 and #published>0,"normal research must still refresh buildings")
assert(#errors==0,table.concat(errors,"\n"))
print("LUMBERJACK_BUILDING_ISOLATION_PASS: 200 growth hits cause zero world scans and building refreshes")
