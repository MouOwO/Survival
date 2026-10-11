-- Run from the addon root with Lua 5.1. The fixture exposes only static
-- parenting APIs; skeleton merging, world scans and positioning timers fail.
package.path = "scripts/vscripts/?.lua;" .. package.path
local function equal(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end
Vector = function(x, y, z) return { x = x, y = y, z = z } end
IsValidEntity = function(entity) return not entity.removed end
local props, spawn_calls, fail_at, attach_fail_at, after_spawn = {}, 0, nil, nil, nil
local removes = 0
UTIL_Remove = function(entity)
    assert(not entity.removed, "a prop must not be removed twice")
    entity.removed = true
    removes = removes + 1
end
local function forbidden() error("must not scan, bone merge or schedule positioning") end
Entities = { FindAllByClassname = forbidden, FindByClassname = forbidden }
Timers = { CreateTimer = forbidden }
package.loaded["core/scheduler"] = { after = forbidden, every = forbidden }
local function unit(index)
    local u = { index = index, alive = true, position = Vector(0, 0, 0),
        attachments = { attach_hitloc = 1, attach_attack1 = 2 } }
    function u:IsNull() return self.removed == true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.index end
    function u:ScriptLookupAttachment(name) return self.attachments[name] or 0 end
    function u:SetThink() forbidden() end
    return u
end
SpawnEntityFromTableSynchronous = function(class, data)
    spawn_calls = spawn_calls + 1
    equal(class, "prop_dynamic")
    equal(data.solid, "0")
    equal(data.DisableBoneFollowers, "1")
    equal(data.origin, "0 0 -2048", "new props stay out of view until attached")
    if spawn_calls == fail_at then return nil end
    local p = { spawn_call = spawn_calls, model = data.model }
    function p:IsNull() return self.removed == true end
    function p:SetOwner(owner) self.owner = owner end
    function p:SetParent(parent, attachment)
        if self.spawn_call == attach_fail_at then error("simulated native attach error") end
        self.parent, self.attachment = parent, attachment
    end
    function p:SetLocalOrigin(origin) self.origin = origin end
    function p:SetLocalAngles(pitch, yaw, roll) self.angles = { pitch, yaw, roll } end
    function p:SetModelScale(scale) self.scale = scale end
    function p:FollowEntity() forbidden() end
    function p:AddEffects() forbidden() end
    function p:SetThink() forbidden() end
    function p:world_position()
        return Vector(self.parent.position.x + self.origin.x,
            self.parent.position.y + self.origin.y, self.parent.position.z + self.origin.z)
    end
    props[#props + 1] = p
    if after_spawn then after_spawn(p) end
    return p
end
local function live_count()
    local count = 0
    for _, p in ipairs(props) do if not p.removed then count = count + 1 end end
    return count
end
local function appearance(scale, model)
    return { model_scale = scale or 1.2, ornaments = {
        { model_path = model or "crystal.vmdl", attachment = "attach_hitloc",
            local_origin = { 0, 8, 12 }, root_origin = { 1, 2, 70 },
            local_angles = { 0, 10, 20 }, model_scale = 0.05 },
        { model_path = "gem.vmdl", attachment = "attach_attack1",
            local_origin = { x = 2, y = 0, z = 3 }, root_origin = { 40, 0, 60 },
            local_angles = { pitch = 5, yaw = 0, roll = -10 }, model_scale = 0.02 },
    } }
end
local module = require("visual/endless_monster_ornaments")
local first = unit(1)
local ok, status, pieces = module.apply(first, appearance())
assert(ok)
equal(status, "applied")
equal(live_count(), 2)
equal(pieces[1].parent, first)
equal(pieces[1].owner, first)
equal(pieces[1].attachment, "attach_hitloc")
near(pieces[1].scale, 0.06)
near(pieces[1].origin.y, 9.6)
near(pieces[1].origin.z, 14.4)
equal(pieces[1].angles[2], 10)
-- Static native parenting must follow movement without another Apply or tick.
first.position = Vector(200, -300, 30)
local world = pieces[1]:world_position()
near(world.x, 200); near(world.y, -290.4); near(world.z, 44.4)
for _ = 1, 20 do
    local stable, result, retained = module.apply(first, appearance())
    assert(stable and result == "unchanged" and retained == pieces)
end
equal(spawn_calls, 2, "stable reapply must not allocate")
-- Reload keeps the captured state on the owner, without scanning the world.
package.loaded["visual/endless_monster_ornaments"] = nil
module = require("visual/endless_monster_ornaments")
local _, reloaded, retained = module.apply(first, appearance())
assert(reloaded == "unchanged" and retained == pieces and spawn_calls == 2)
-- The 1.5 size multiplier is applied once to both geometry and local offsets.
local grown = appearance(1.8)
ok, _, retained = module.apply(first, grown)
assert(ok and pieces[1].removed and pieces[2].removed)
near(retained[1].scale, 0.09)
near(retained[1].origin.y, 14.4)
near(retained[1].origin.z, 21.6)
equal(live_count(), 2)
-- A failed second prop rolls back the partial birth and preserves the outfit.
local before = live_count()
fail_at = spawn_calls + 2
local failed, reason = module.apply(first, appearance(1.8, "replacement.vmdl"))
assert(not failed and reason == "ornament_spawn_failed")
equal(live_count(), before)
assert(not retained[1].removed and not retained[2].removed)
fail_at = nil
attach_fail_at = spawn_calls + 2
failed, reason = module.apply(first, appearance(1.8, "replacement.vmdl"))
assert(not failed and reason == "ornament_attach_failed")
equal(live_count(), before)
attach_fail_at = nil
-- A dead or missing attachment falls back to the configured body surface.
local fallback = unit(2)
fallback.ScriptLookupAttachment = nil
function fallback:LookupAttachment(name) return name == "attach_hitloc" and 1 or 0 end
local fallback_visual = appearance(1.5)
fallback_visual.ornaments[1].attachment = "not_a_real_attachment"
ok, _, pieces = module.apply(fallback, fallback_visual)
assert(ok)
equal(pieces[1].attachment, "")
near(pieces[1].origin.x, 1.5); near(pieces[1].origin.y, 3); near(pieces[1].origin.z, 105)
equal(pieces[1].angles[1], 0); equal(pieces[1].angles[2], 0); equal(pieces[1].angles[3], 0)
equal(pieces[2].attachment, "", "missing mouth attachment must also use the root")
equal(pieces[2].angles[1], 0); equal(pieces[2].angles[3], 0)
-- Explicit root-space orientation is supported without reusing bind-pose
-- compensation from the missing attachment.
fallback_visual.ornaments[1].root_angles = { pitch = 30, yaw = 45, roll = -15 }
local fallback_old = pieces[1]
ok, _, pieces = module.apply(fallback, fallback_visual)
assert(ok and fallback_old.removed)
equal(pieces[1].angles[1], 30); equal(pieces[1].angles[2], 45); equal(pieces[1].angles[3], -15)
fallback_visual.ornaments[1].root_angles = nil
-- Bounds provide a safe above-body fallback when a caller omits root_origin.
fallback_visual.ornaments[1].root_origin = nil
fallback_visual.bounds = { min = { -20, -10, 0 }, max = { 60, 10, 80 } }
ok, _, pieces = module.apply(fallback, fallback_visual)
assert(ok)
near(pieces[1].origin.x, 30); near(pieces[1].origin.z, 120)
-- A native skin or the first outfit round clears custom props instead of
-- reusing the previous round's ornaments over the native bundle.
local empty = { model_scale = 1.5, ornaments = {} }
assert(module.apply(fallback, empty))
assert(pieces[1].removed and pieces[2].removed)
equal(live_count(), 2)
assert(module.clear(fallback)); assert(module.clear(fallback))
-- Engine index reuse never borrows another unit's captured ornaments.
local reused = unit(1)
ok, _, pieces = module.apply(reused, appearance())
assert(ok and live_count() == 4)
assert(module.clear(first))
equal(live_count(), 2)
assert(not pieces[1].removed and not pieces[2].removed)
-- An externally removed prop repairs the complete pair and retires the old
-- surviving prop, rather than accumulating another ornament each retry.
UTIL_Remove(pieces[1])
local old_second = pieces[2]
ok, _, pieces = module.apply(reused, appearance())
assert(ok and old_second.removed and live_count() == 2)
reused.alive = false
failed, reason = module.apply(reused, appearance())
assert(not failed and reason == "unit_dead" and live_count() == 0)
-- Clearing during an in-flight spawn cannot publish a new orphan afterward.
local interrupted = unit(3)
after_spawn = function() after_spawn = nil; module.clear(interrupted) end
failed, reason = module.apply(interrupted, appearance())
assert(not failed and reason == "superseded" and live_count() == 0)
-- A nested replacement wins; the older call only retires its own partial prop.
local nested = unit(4)
after_spawn = function()
    after_spawn = nil
    assert(module.apply(nested, appearance(1.5, "nested.vmdl")))
end
failed, reason = module.apply(nested, appearance())
assert(not failed and reason == "superseded" and live_count() == 2)
assert(module.clear(nested) and live_count() == 0)
local clean = unit(5)
fail_at = spawn_calls + 2
assert(not module.apply(clean, appearance()))
equal(live_count(), 0, "failed first birth must not leak a world prop")
fail_at = nil
assert(module.clear(clean))
-- Death while replacing an existing outfit retires both the captured outfit
-- and the partial replacement even if no separate death callback has run yet.
local dying = unit(6)
assert(module.apply(dying, appearance()))
after_spawn = function() after_spawn = nil; dying.alive = false end
failed, reason = module.apply(dying, appearance(1.5, "last.vmdl"))
assert(not failed and reason == "unit_dead" and live_count() == 0)
local invalid = unit(7)
failed, reason = module.apply(invalid, { ornaments = "not_a_list" })
assert(not failed and reason == "ornaments_invalid" and live_count() == 0)
failed, reason = module.apply(invalid, { ornaments = {
    { model_path = "gem.vmdl", local_origin = { 0 / 0, 0, 0 } },
} })
assert(not failed and reason == "invalid_ornament_transform" and live_count() == 0)
assert(module.clear(nil))
print("ENDLESS_ORNAMENTS_PASS parent movement, scale, stable/reload reuse, rollback, attachment fallback, death cleanup, index reuse, reentrant cleanup; spawns=" .. spawn_calls .. " removals=" .. removes)
