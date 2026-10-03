-- Fixture ownership, async cancellation and timeout tests; no Dota process.
package.path = "scripts/vscripts/?.lua;" .. package.path
local now, server, tools_mode, next_id = 0, true, true, 0
local units, removed, loaded, thoughts, outsiders = {}, {}, {}, {}, {}
local calls = { visual_clear = 0, moves = 0, modifiers = 0 }
local mt = {}
Vector = function(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, mt) end
mt.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__index = { Length2D = function(v) return math.sqrt(v.x*v.x+v.y*v.y) end }
local world = { SetContextThink = function(_, key, callback) thoughts[key] = callback end }
GameRules = { GetGameTime = function() return now end, GetGameModeEntity = function() return world end }
Time = function() return now end
IsServer = function() return server end
IsInToolsMode = function() return tools_mode end
GetGroundHeight = function() return 640 end
GridNav = { IsTraversable = function() return true end, IsBlocked = function() return false end }
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO = 3, 1
DOTA_UNIT_TARGET_TEAM_ENEMY = 2
DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 2, 4
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 0, 2
DOTA_UNIT_CAP_MOVE_NONE, DOTA_UNIT_CAP_MOVE_GROUND = 0, 1
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 16, 32
DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD, FIND_ANY_ORDER, LUA_MODIFIER_MOTION_NONE = 64, 0, 0
LinkLuaModifier = function() end
FindUnitsInRadius = function()
    local result = {}
    for _, unit in ipairs(units) do if not unit.removed then result[#result+1] = unit end end
    for _, unit in ipairs(outsiders) do result[#result+1] = unit end
    return result
end
PrecacheUnitByNameAsync = function(name, callback, owner)
    assert(owner == -1, "fixture acquired a player owner")
    loaded[#loaded+1] = callback
end
local noop = function() end
CreateUnitByName = function(name, point, _, owner, source, team)
    assert(owner == nil and source == nil, "fixture acquired gameplay ownership")
    next_id = next_id + 1
    local unit = { id = next_id, point = point, team = team, modifiers = {}, removed_modifiers = {}, hp = 1 }
    function unit:entindex() return self.id end
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return not self.removed end
    function unit:GetAbsOrigin() return self.point end
    function unit:SetEntityName(value) self.name = value end
    function unit:SetHealth(value) self.hp = value end
    function unit:GetHealth() return self.hp end
    function unit:GetModelName() return self.model end
    function unit:GetUnitName() return name end
    function unit:GetTeamNumber() return self.team end
    function unit:GetAttackTarget() return nil end
    function unit:AddAbility(skill) return { SetLevel = noop } end
    function unit:AddNewModifier(_, _, name)
        calls.modifiers = calls.modifiers + 1
        self.modifiers[name] = { laser_ticks = 0, laser_particles = {} }
        return self.modifiers[name]
    end
    function unit:FindModifierByName(name) return self.modifiers[name] end
    function unit:RemoveModifierByName(name)
        self.modifiers[name] = nil
        self.removed_modifiers[name] = true
    end
    function unit:IsMoving() return self.moving == true end
    function unit:MoveToPosition(point)
        self.destination, self.moving = point, true
        calls.moves = calls.moves + 1
    end
    for _, method in ipairs({ "SetBaseMaxHealth", "SetMaxHealth", "SetBaseHealthRegen", "SetIdleAcquire",
        "SetAcquisitionRange", "SetAttackCapability", "SetMoveCapability", "SetBaseMoveSpeed",
        "SetDayTimeVisionRange", "SetNightTimeVisionRange", "SetBaseDamageMin", "SetBaseDamageMax",
        "SetBaseAttackTime", "Stop" }) do unit[method] = noop end
    units[#units+1] = unit
    return unit
end
UTIL_Remove = function(unit)
    assert(not unit.removed, "fixture removed an owned unit twice")
    assert(unit.survival_laser_fixture_role, "fixture removed an unrelated unit")
    removed[#removed+1], unit.removed = unit, true
end
package.loaded["systems/building_visual_service"] = {
    apply = function(unit, row) unit.model = row.model_name; return true end,
    clear = function() calls.visual_clear = calls.visual_clear + 1 end,
}
package.loaded["config/tower_combat_rules"] = { attack_range = function() return 1000 end,
    current_attack_range = function(unit) return unit.range end,
    set_attack_range = function(unit, range) unit.range = range end }
-- Forbidden fixture shortcuts must fail immediately if introduced later.
ApplyDamage = function() error("fixture dealt direct damage") end
package.loaded["core/event_bus"] = { emit = function() error("fixture emitted a global event") end,
    request = function() error("fixture changed player/business state") end }
local skills = require("systems/tower_skill_runtime")
local review = require("tests/manual_laser_follow_review")
local function tick(seconds)
    now = now + (seconds or .1)
    local queue = {}
    for key, callback in pairs(thoughts) do queue[#queue+1] = { key, callback } end
    for _, item in ipairs(queue) do
        if thoughts[item[1]] == item[2] and item[2]() == nil then thoughts[item[1]] = nil end
    end
end
local function finish_loading()
    while #loaded > 0 do table.remove(loaded,1)() end
    tick()
end

tools_mode = false
assert(not review.run().ok and #units == 0)
tools_mode = true
assert(not review.run({count=2}).ok and #units == 0)
assert(not review.run({attack_shell="building_arrow_tower"}).ok and #units == 0,
    "fixture accepted a gameplay building shell")
outsiders = { { IsNull = function() return false end } }
assert(not review.run().ok and #units == 0)
outsiders = {}

local fixture = review.run({count=1,seconds=5})
assert(fixture.ok and fixture.phase == "loading")
assert(not review.run().ok, "duplicate run was accepted")
review.cleanup()
finish_loading()
assert(#units == 0, "late precache callback resurrected a cancelled fixture")

fixture = review.run({count=4,seconds=5})
finish_loading()
assert(fixture.phase == "running" and #fixture.slots == 4 and #units == 8)
assert(calls.modifiers == 8 and calls.moves == 4)
for _, slot in ipairs(fixture.slots) do
    assert(slot.tower:GetUnitName() == "npc_dota_creep_goodguys_ranged"
        and slot.tower.removed_modifiers.modifier_creep_piercing,
        "fixture must initialize native ranged attacks without creep damage-class modifiers")
    assert(slot.tower.survival_is_building == false and slot.tower.survival_building_id == nil
        and slot.tower.survival_player_id == nil, "fixture masqueraded as a saved building")
    assert(skills.get_skill(slot.tower, "laser_lv01"), "production skill runtime was bypassed")
    slot.enemy.point = slot.destination
end
tick()
assert(calls.moves == 8 and fixture.slots[1].turns == 1)
assert(fixture.slots[1].travelled == 220, "motion stats did not record actual displacement")
fixture.slots[1].enemy.moving = false -- engine damage interrupts this target's order
tick(0.2)
assert(calls.moves == 8, "dropped movement order retried before the throttle")
tick(0.16)
assert(calls.moves == 9 and fixture.slots[1].move_retries == 1,
    "interrupted native movement did not resume")
tick(0.4)
assert(calls.moves == 9, "healthy walking was restarted by the fixture")
local state = fixture:status()
assert(#state.slots == 4 and state.slots[1].tower ~= state.slots[1].enemy)
assert(state.slots[1].move_retries == 1 and state.slots[1].travelled == 220)
assert(fixture:diagnose().ok, "read-only diagnostic failed")
tick(5)
assert(fixture.finished and fixture.phase == "complete" and #removed == 8)
assert(_G.SURVIVAL_LASER_FOLLOW_REVIEW == nil and next(thoughts) == nil)
review.cleanup()
assert(#removed == 8 and calls.visual_clear == 4)

fixture = review.run({seconds=5})
finish_loading()
local own_units = #removed
outsiders = { { IsNull = function() return false end } }
tick()
assert(fixture.finished and fixture.error == "foreign_unit_entered" and #removed == own_units + 2)
outsiders = {}

fixture = review.run()
tick(21)
assert(fixture.finished and fixture.error == "loading_timeout")
local before = #units
finish_loading()
assert(#units == before, "timed-out precache callback created units")

fixture = review.run()
finish_loading()
fixture.slots[1].enemy.GetHealth = function() error("injected stats failure") end
local before = #removed
review.cleanup()
assert(#removed == before + 2, "stats failure prevented independent cleanup")

fixture = review.run({attack_shell="native_ranged",seconds=5})
finish_loading()
assert(fixture.phase == "running" and fixture.attack_shell == "npc_dota_creep_goodguys_ranged")
assert(fixture.slots[1].tower:GetUnitName() == "npc_dota_creep_goodguys_ranged")
assert(skills.get_skill(fixture.slots[1].tower, "laser_lv01"),
    "native shell bypassed production laser skill runtime")
local before = #removed
tick(5)
assert(fixture.finished and #removed == before + 2 and next(thoughts) == nil,
    "native-shell fixture did not clean up at its deadline")
print("MANUAL_LASER_FOLLOW_FIXTURE_PASS")
