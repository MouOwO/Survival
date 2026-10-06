-- SIMULATION: actual fixture + weapon service + production CSV profiles.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local tasks, world, serial = {}, {}, 0
package.loaded["core/scheduler"] = {
    after = function(_, callback, id)
        serial = serial + 1
        id = id or tostring(serial)
        tasks[id] = callback
        return id
    end,
    every = function(_, callback, id)
        serial = serial + 1
        id = id or tostring(serial)
        tasks[id] = callback
        return id
    end,
    cancel = function(id) tasks[id] = nil end,
}
local vector_mt = {}
Vector = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, vector_mt) end
vector_mt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
GameRules = { GetGameTime = function() return 0 end, GetGameModeEntity = function() return world end }
local tools_mode, blocked, occupied, defeated = true, false, false, false
IsServer = function() return true end
IsInToolsMode = function() return tools_mode end
GetGroundHeight = function() return 384 end
GridNav = { IsTraversable = function() return not blocked end, IsBlocked = function() return blocked end }
FindUnitsInRadius = function() return occupied and { {} } or {} end
local owner = {}
PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    GetPlayer = function() return owner end,
    GetTeam = function() return 2 end,
}
package.loaded["systems/multiplayer_player_service"] = { is_defeated = function() return defeated end }
package.loaded["systems/unit_health_bar_service"] = {
    exclude = function(unit) unit.bar_excluded = true end,
}
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES = 1, 2
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3, 4, 8
DOTA_UNIT_TARGET_BUILDING, FIND_ANY_ORDER = 16, 1
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_MOVE_NONE, ACT_DOTA_ATTACK = 0, 0, 7
PATTACH_POINT_FOLLOW, PATTACH_ABSORIGIN_FOLLOW = 1, 2
local particles, next_particle = {}, 0
ParticleManager = {
    CreateParticle = function(_, path, _, hero)
        next_particle = next_particle + 1
        particles[next_particle] = { path = path, hero = hero, cp = {} }
        return next_particle
    end,
    SetParticleControlEnt = function() end,
    SetParticleControl = function(_, id, cp, value) particles[id].cp[cp] = value end,
    DestroyParticle = function(_, id)
        assert(not particles[id].destroyed, "double particle destruction")
        particles[id].destroyed = true
    end,
    ReleaseParticleIndex = function(_, id) assert(particles[id].destroyed) end,
}
local created, pending_load, load_count = {}, nil, 0
PrecacheUnitByNameAsync = function(name, callback, player_id)
    assert(name == "npc_dota_hero_juggernaut" and player_id == -1)
    load_count = load_count + 1
    pending_load = callback
end
CreateUnitByName = function(name, point)
    assert(name == "npc_dota_hero_juggernaut")
    local unit = { id = #created + 1, point = point }
    created[#created + 1] = unit
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return not self.dead end
    function unit:entindex() return self.id end
    function unit:GetAbsOrigin() return self.point end
    function unit:GetModelName() return self.model or "" end
    function unit:SetAbsOrigin(value) self.point = value end
    function unit:ScriptLookupAttachment(name)
        return name == "attach_sword" and 2 or (name == "attach_hitloc" and 5 or 0)
    end
    function unit:SetOwner(player) self.owner = player end
    function unit:SetControllableByPlayer(id, flag) self.player_id, self.controllable = id, flag end
    function unit:StartGesture() self.swings = (self.swings or 0) + 1 end
    for _, method in ipairs({ "SetRespawnsDisabled", "SetIdleAcquire", "SetAcquisitionRange",
        "SetAttackCapability", "SetMoveCapability", "SetHullRadius", "SetDayTimeVisionRange",
        "SetNightTimeVisionRange", "AddNewModifier", "SetForwardVector", "RemoveGesture" }) do
        unit[method] = function() end
    end
    return unit
end
UTIL_Remove = function(unit)
    assert(not unit.removed, "double fixture removal")
    unit.removed = true
end
local gameplay_events = 0
bus.subscribe(events.HERO_SUMMONED, function() gameplay_events = gameplay_events + 1 end)
bus.subscribe(events.WEAPON_EQUIPPED_CHANGED, function() gameplay_events = gameplay_events + 1 end)
local service = require("systems/weapon_visual_service")
service.init()
local fixture_api = require("tests/manual_weapon_visual_review")
tools_mode = false
assert(not fixture_api.run().ok and load_count == 0)
tools_mode, blocked = true, true
assert(not fixture_api.run().ok and load_count == 0)
blocked = false
local cancelled = fixture_api.run()
assert(cancelled.ok and cancelled.phase == "loading" and #created == 0)
assert(not fixture_api.run().ok, "prevent a concurrent duplicate fixture")
fixture_api.cleanup()
pending_load()
assert(#created == 0, "cancel before async completion must spawn nothing")
local fixture = fixture_api.run()
pending_load()
assert(fixture.phase == "binding" and #created == 5 and next_particle == 0,
    "native creation must wait for its model before visual binding")
tasks.weapon_visual_review_binding()
assert(fixture.phase == "binding" and next_particle == 0)
for _, unit in ipairs(created) do unit.model = "models/heroes/juggernaut/juggernaut.vmdl" end
tasks.weapon_visual_review_binding()
assert(fixture.phase == "ready" and #fixture.slots == 5 and #created == 5)
pending_load()
assert(#created == 5, "duplicate engine callback cannot duplicate display units")
local result = fixture:status()
local expected_radii = { 10, 15, 20, 25, 30 }
for index, slot in ipairs(fixture.slots) do
    local status = result.slots[index]
    assert(status.active and status.progress == 1 and status.anchor == "attach_sword"
        and status.anchor_index == 2)
    assert(particles[status.particle_ids[1]].cp[1].x == expected_radii[index])
    assert(slot.unit.owner == owner and slot.unit.bar_excluded)
    assert(not slot.unit.survival_is_building and not slot.unit.survival_hero_id)
end
assert(not service.debug_snapshot(0) and gameplay_events == 0,
    "fixture must never register player state or emit gameplay events")
fixture:swing()
for _, slot in ipairs(fixture.slots) do assert(slot.unit.swings == 1) end
local moving = fixture.slots[5]
local initial_x = moving.unit:GetAbsOrigin().x
fixture:move(5, 120, 0)
local motion = tasks[moving.motion_task]
for step = 1, 20 do
    local keep = motion()
    assert(step == 20 and keep == false or step < 20)
end
assert(moving.unit:GetAbsOrigin().x == initial_x + 120)
assert(fixture:status().slots[5].particle_count == 3, "moving does not recreate particles")
fixture_api.cleanup(); fixture_api.cleanup()
for _, unit in ipairs(created) do assert(unit.removed) end
for _, particle in pairs(particles) do assert(particle.destroyed) end
-- Loading may finish after somebody else occupies the selected row.
local occupied_fixture = fixture_api.run()
occupied = true
pending_load()
assert(occupied_fixture.finished and not occupied_fixture.ok and #created == 5)
occupied = false
local old_world_fixture = fixture_api.run()
world = {}
pending_load()
assert(#created == 5, "old-world callback must not create entities")
old_world_fixture:cleanup()
service.init()
local timed_out = fixture_api.run()
tasks.weapon_visual_review_timeout()
pending_load()
assert(timed_out.finished and not timed_out.ok and #created == 5)
assert(gameplay_events == 0)
print("MANUAL_WEAPON_FIXTURE_PASS tools/nav/async_cancel/stages/isolation/move/cleanup/world/timeout")
