-- Run from the addon root. Model the real CDOTA_BaseNPC API: it has
-- GetProjectileSpeed and modifier bonuses, but no SetProjectileSpeed.
package.path = "scripts/vscripts/?.lua;" .. package.path
-- Optional candidate config permits regression checks before production edits.
if arg and arg[1] then
    package.loaded["config/generated/arrow_tower_base"] = dofile(arg[1])
end
class = function(base) base.__index = base; return base end
IsServer = function() return true end
LUA_MODIFIER_MOTION_NONE = 0
MODIFIER_ATTRIBUTE_PERMANENT = 1
MODIFIER_PROPERTY_PROJECTILE_SPEED_BONUS = 2
local links = {}
LinkLuaModifier = function(name, path) links[name] = path end

local speed_service = require("systems/tower_projectile_speed")
local speed_modifier = require("modifiers/modifier_tower_projectile_speed")
local rules = require("config/tower_combat_rules")
local global_rules = require("config/global_rules")
local modifier_name = "modifier_tower_projectile_speed"
assert(links[modifier_name] == "modifiers/modifier_tower_projectile_speed")

local function engine_unit()
    local unit = {native_speed = 5000, modifiers = {}, additions = 0, recalculations = 0}
    function unit:FindModifierByName(name) return self.modifiers[name] end
    function unit:GetProjectileSpeed()
        local modifier = self:FindModifierByName(modifier_name)
        local bonus = 0
        if modifier then
            assert(modifier:DeclareFunctions()[1] == MODIFIER_PROPERTY_PROJECTILE_SPEED_BONUS,
                "engine must receive the projectile speed property")
            bonus = modifier:GetModifierProjectileSpeedBonus()
        end
        return self.native_speed + bonus
    end
    function unit:AddNewModifier(caster, ability, name, kv)
        assert(caster == self and ability == nil and name == modifier_name)
        assert(not self.modifiers[name], "refresh must reuse the existing modifier")
        local modifier = setmetatable({parent = self, stack = 0}, speed_modifier)
        function modifier:SetStackCount(value) self.stack = value end
        function modifier:GetStackCount() return self.stack end
        function modifier:GetParent() return self.parent end
        self.modifiers[name] = modifier
        self.additions = self.additions + 1
        modifier:OnCreated(kv)
        return modifier
    end
    function unit:CalculateStatBonus(force)
        assert(force == true)
        self.recalculations = self.recalculations + 1
    end
    return unit
end

-- Exercise production entry points without loading unrelated event handlers.
-- Their complete function bodies and dependencies come from the current code.
local function production_function(path, name, environment)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local body = assert(source:match("(local function " .. name .. "%b().-\nend)"), name)
    local code = body .. "\nreturn " .. name
    local chunk
    environment = setmetatable(environment, {__index = _G})
    if setfenv then
        chunk = assert(loadstring(code, "@" .. path .. ":" .. name))
        setfenv(chunk, environment)
    else
        chunk = assert(load(code, "@" .. path .. ":" .. name, "t", environment))
    end
    return chunk()
end

local apply_building_speed = production_function(
    "scripts/vscripts/systems/building_upgrade_system.lua", "set_tower_projectile_speed", {
        tower_projectile_speed = speed_service,
        tower_combat_rules = rules,
        global_rules = global_rules,
    })


-- Base arrows previously changed speed after an upgrade: creation fell back
-- to the base global value, while route_unit_data used a route fallback.
-- Exercise both actual code paths with a native engine lacking a setter.
local base_arrow = require("config/generated/arrow_tower_base")
local death_route = require("config/generated/tower_class_death")
local critical_speed = rules.projectile_speed(death_route.rows[1].projectile_speed, "class_1")
assert(critical_speed and critical_speed > 0)
for _, row in ipairs(death_route.rows) do
    assert(rules.projectile_speed(row.projectile_speed, "class_1") == critical_speed,
        row.record_id .. " defines the authoritative current critical-tower speed")
end
local route_data = production_function(
    "scripts/vscripts/systems/building_upgrade_system.lua", "route_unit_data", {
        global_rules = global_rules,
    })
local apply_tower_level_data = production_function(
    "scripts/vscripts/systems/building_upgrade_system.lua", "apply_tower", {
        apply_common = function() end,
        arrow_data = function(level) return base_arrow.rows[level] end,
        set_tower_projectile_speed = apply_building_speed,
        tower_fixed_facing = require("systems/tower_fixed_facing"),
        set_attack_range = function() end,
        global_rules = global_rules,
    })
local function tower_for_level()
    local tower = engine_unit()
    function tower:IsNull() return false end
    function tower:GetUnitName() return "building_arrow_tower" end
    function tower:RemoveModifierByName(name) self.modifiers[name] = nil end
    function tower:GetMaxHealth() return 1500 end
    function tower:GetPhysicalArmorBaseValue() return 5 end
    function tower:SetAttackCapability(value) self.attack_capability = value end
    function tower:SetBaseDamageMin(value) self.damage_min = value end
    function tower:SetBaseDamageMax(value) self.damage_max = value end
    function tower:SetBaseAttackTime(value) self.attack_time = value end
    function tower:SetRangedProjectileName(value) self.projectile_name = value end
    function tower:HasModifier(name) return self.modifiers[name] ~= nil end
    local speed_modifier_add = tower.AddNewModifier
    function tower:AddNewModifier(caster, ability, name, kv)
        if name == modifier_name then return speed_modifier_add(self, caster, ability, name, kv) end
        self.modifiers[name] = {}; return self.modifiers[name]
    end
    return tower
end
local function assert_arrow_speed(tower, label)
    assert(tower:GetProjectileSpeed() == critical_speed,
        label .. " native arrow must match critical speed " .. tostring(critical_speed)
            .. ", got " .. tostring(tower:GetProjectileSpeed()))
    assert(tower.survival_projectile_speed == critical_speed,
        label .. " custom/projected arrow speed must agree with the engine")
end
assert(#base_arrow.rows == 5, "all five base arrow levels must be covered")
local arrow = tower_for_level()
-- on_created and state recovery select the arrow row's explicit speed.
apply_building_speed(arrow, base_arrow.rows[1].projectile_speed)
assert_arrow_speed(arrow, "base construction LV1")
for level, row in ipairs(base_arrow.rows) do
    local data = route_data({unit = arrow, tower_class = nil}, row)
    apply_tower_level_data(arrow, data, level)
    assert_arrow_speed(arrow, "base ordinary upgrade LV" .. tostring(level))
    assert(arrow:HasModifier("modifier_tower_fixed_facing"),
        "base upgrade must keep the actual facing helper active alongside its speed modifier")
    assert(arrow.survival_base_projectile_speed == row.projectile_speed,
        row.record_id .. " runtime must preserve the explicit raw configuration")
    for _ = 1, 3 do apply_building_speed(arrow, nil) end
    assert_arrow_speed(arrow, "base repeated refresh LV" .. tostring(level))
    -- Recovering an existing tower must overwrite stale pre-fix metadata.
    local recovered = tower_for_level()
    recovered.survival_base_projectile_speed = 5000
    apply_building_speed(recovered, row.projectile_speed)
    assert_arrow_speed(recovered, "base recovery LV" .. tostring(level))
end
assert(arrow.additions == 1, "ordinary levels and refreshes reuse one speed modifier")
local straight = tower_for_level()
apply_building_speed(straight, base_arrow.rows[1].projectile_speed)
apply_tower_level_data(straight, route_data({unit = straight}, base_arrow.rows[5]), 5)
assert_arrow_speed(straight, "base direct-to-max LV5")
local critical_row = death_route.rows[1]
-- During route application the entity still carries the previous class. The
-- explicit data class must prevent applying the base's 0.5 multiplier again.
apply_tower_level_data(straight,
    route_data({unit = straight, tower_class = "class_1"}, critical_row), 6)
straight.survival_tower_class = "class_1"
assert_arrow_speed(straight, "base-to-critical class transition")
assert(not straight:HasModifier("modifier_tower_fixed_facing"),
    "explicit future critical class removes the base-facing modifier before metadata updates")
assert(straight.additions == 1, "class transition updates the existing native modifier")
print("BASE_ARROW_PROJECTILE_SPEED_PASS: LV1–5 construction/upgrade/direct-max/recovery/refresh and critical transition, native/custom speed " .. tostring(critical_speed))

local route_count = 0
for _, route in ipairs({
    {"class_1", "tower_class_death"},
    {"class_5", "tower_class_multi"},
    {"class_6", "tower_class_frost"},
    {"class_7", "tower_class_anti_air"},
}) do
    local tower = engine_unit()
    tower.survival_tower_class = route[1]
    assert(tower.SetProjectileSpeed == nil, "regression requires the real engine API")
    for _, row in ipairs(require("config/generated/" .. route[2]).rows) do
        assert(row.projectile_speed == 1500, row.record_id .. " must share the configured speed")
        apply_building_speed(tower, row.projectile_speed)
        assert(tower.survival_projectile_speed == 1500,
            row.record_id .. " custom arrows must receive their speed without a setter")
        assert(tower:GetProjectileSpeed() == 1500,
            row.record_id .. " native and custom projectiles must travel at the same speed")
        assert(tower.survival_base_projectile_speed == 1500)
        apply_building_speed(tower, nil)
        assert(tower:GetProjectileSpeed() == 1500,
            "projection refresh must preserve configured speed without applying another multiplier")
    end
    assert(tower.additions == 1, "all upgrade levels reuse one modifier")
    assert(tower.survival_native_tower_projectile_speed == 5000)
    assert(tower.recalculations > 0, "native stats must be recalculated")
    local modifier = tower:FindModifierByName(modifier_name)
    assert(modifier:IsHidden() and not modifier:IsPurgable() and not modifier:RemoveOnDeath())
    assert(modifier:GetAttributes() == MODIFIER_ATTRIBUTE_PERMANENT)
    route_count = route_count + 1
end

-- Global slowdown still applies once to base/lightning routes, including when
-- upgrading the configured speed and repeatedly refreshing the same entity.
assert(global_rules.tower_projectile_speed_multiplier == 0.5)
local slowed = engine_unit()
slowed.survival_tower_class = "class_3"
apply_building_speed(slowed, 2500)
assert(slowed:GetProjectileSpeed() == 1250 and slowed.survival_projectile_speed == 1250)
for _ = 1, 100 do apply_building_speed(slowed, nil) end
assert(slowed:GetProjectileSpeed() == 1250 and slowed.survival_base_projectile_speed == 2500)
apply_building_speed(slowed, 4000)
assert(slowed:GetProjectileSpeed() == 2000 and slowed.survival_projectile_speed == 2000)
apply_building_speed(slowed, 1500, "class_5")
assert(slowed:GetProjectileSpeed() == 1500, "route change updates an existing bonus")

-- Metadata recovery must remove the old bonus before learning the native base.
slowed.survival_native_tower_projectile_speed = nil
apply_building_speed(slowed, 1500, "class_5")
assert(slowed:GetProjectileSpeed() == 1500 and slowed.survival_native_tower_projectile_speed == 5000)
slowed.modifiers[modifier_name] = nil
apply_building_speed(slowed, 1500, "class_5")
assert(slowed:GetProjectileSpeed() == 1500 and slowed.additions == 2,
    "a missing speed modifier must be restored")

-- A compatibility setter still populates the shared custom-projectile cache.
local compatibility = engine_unit()
function compatibility:SetProjectileSpeed(value) self.native_speed = value end
assert(speed_service.apply(compatibility, 1500, "class_5") == 1500)
assert(compatibility:GetProjectileSpeed() == 1500 and compatibility.survival_projectile_speed == 1500)
assert(compatibility.additions == 0)

-- Integrate the actual construction setter with the actual split-arrow flight
-- and visual code. No test manually fills survival_projectile_speed.
local projectiles, tasks, hits = {}, {}, {}
ProjectileManager = {CreateTrackingProjectile = function(_, shot)
    projectiles[#projectiles + 1] = shot
end}
local visual = require("systems/tower_projectile_visual")
local split_arrow = production_function(
    "scripts/vscripts/modifiers/modifier_tower_attack_effects.lua", "split_arrow", {
        valid = function(unit) return unit and not unit:IsNull() and unit:IsAlive() end,
        tower_combat_rules = rules,
        SPLIT_ARROW_SPEED = 500,
        projectile_visual = visual,
        scheduler = {after = function(delay, callback)
            tasks[#tasks + 1] = {delay = delay, callback = callback}
        end},
        detailed_log = function() end,
        roll_tower_critical = function() return 1 end,
        deal = function(caster, target, amount) hits[#hits + 1] = {target = target, amount = amount} end,
    })
local position_mt = {__sub = function(a, b)
    return {Length2D = function() return math.abs(a.x - b.x) end}
end}
local function combat_unit(tower, x, id)
    tower.position = setmetatable({x = x}, position_mt)
    function tower:GetAbsOrigin() return self.position end
    function tower:IsNull() return false end
    function tower:IsAlive() return true end
    function tower:entindex() return id end
    return tower
end
local archer = combat_unit(engine_unit(), 0, 1)
archer.survival_tower_class = "class_5"
local enemy = combat_unit({}, 600, 2)
for _, id in ipairs({"multi_tower_lv01", "multi_tower_lv05", "piercing_ballista_lv01",
    "piercing_ballista_lv05", "burning_great_arrow_lv01", "burning_great_arrow_lv10"}) do
    local row = require("config/generated/tower_class_multi").by_id[id]
    apply_building_speed(archer, row.projectile_speed)
    visual.clear(archer)
    split_arrow(archer, enemy, 100, row.projectile_model, 1)
    local shot, task = projectiles[#projectiles], tasks[#tasks]
    assert(shot.iMoveSpeed == 1500 and shot.iMoveSpeed == archer:GetProjectileSpeed(),
        id .. " split arrows must use the speed actually applied at construction/upgrade")
    assert(math.abs(task.delay - 0.4) < 1e-9,
        id .. " a target 600 units away must be hit after 0.4 seconds, not the old 1.2")
    assert(#hits == #tasks - 1, "split arrow damage must wait for projectile arrival")
    task.callback()
    assert(#hits == #tasks and hits[#hits].amount == 100)
end
print("TOWER_PROJECTILE_SPEED_PASS: " .. route_count .. " routes, real modifier property, no setter, upgrade/refresh/recovery, split-arrow speed and flight delay")
