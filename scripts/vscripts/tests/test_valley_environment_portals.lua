package.path = "scripts/vscripts/?.lua;" .. package.path
local pending = {}
package.loaded["core/scheduler"] = {
    after = function(_, callback) pending[#pending + 1] = callback end,
}
local function vector(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
    })
end
local function near(a, b) assert(math.abs(a - b) < 1e-8, tostring(a) .. " ~= " .. tostring(b)) end
Vector = vector
PATTACH_ABSORIGIN_FOLLOW, PATTACH_POINT_FOLLOW, PATTACH_WORLDORIGIN = 1, 2, 3
local world, map, mode = {}, "template_map", nil
GameRules = { GetGameModeEntity = function() return world end }
GetMapName = function() return map end
package.loaded["systems/match_setup_service"] = { get_mode = function() return mode end }
local positions = {
    standard = { vector(88, 4096, 777), vector(-1024, 2984, 777),
        vector(-2136, 4096, 777), vector(-1024, 5208, 777) },
    rich = {}, cold = {}, scourge = {},
}
for index, name in ipairs({"rich", "cold", "scourge"}) do
    for lane = 1, 4 do positions[name][lane] = vector(index * 10000 + lane * 200, lane * -1000, 999) end
end
GetGroundHeight = function(position)
    -- Marker Z is intentionally wrong: portal clearance must follow terrain.
    return position.x > 10000 and 256 or 128
end
local expected = { {1, 0, 0}, {0, -1, 270}, {-1, 0, 180}, {0, 1, 90} }
local missing, searches = nil, {}
Entities = { FindByName = function(_, _, name)
    searches[#searches + 1] = name
    local name_mode, zero_lane = name:match("^mode_(%a+)_monster_(%d)_spawn$")
    local lane = tonumber(name:match("^monsterborn_player(%d)$"))
    if zero_lane then lane = tonumber(zero_lane) + 1 end
    if lane and lane ~= missing then
        local point = assert(positions[name_mode or "standard"])[lane]
        return { GetAbsOrigin = function() return point end }
    end
    if name:find("^valley_decor_v1_fx_") then return { old = true } end
end }
local props, particles, precached = {}, {}, {}
local stops, destroyed, removed = 0, 0, 0
local fail_create
SpawnEntityFromTableSynchronous = function(class, kv)
    assert(class == "prop_dynamic" and kv.solid == 0, "portal must not block units")
    assert(kv.DefaultAnim == "au_portal_chanelling")
    assert(kv.model == "models/heroes/abyssal_underlord/abyssal_underlord_portal_model.vmdl")
    local prop = { kv = kv, world = world }
    function prop:IsNull() return self.removed == true end
    function prop:SetAbsOrigin(value) self.position = value end
    function prop:SetAngles(pitch, yaw, roll)
        assert(roll == 0)
        self.pitch, self.yaw = pitch, yaw
    end
    props[#props + 1] = prop
    return prop
end
UTIL_Remove = function(prop)
    assert(not prop.removed and prop.world == world, "never remove another world's handles")
    prop.removed = true; removed = removed + 1
end
DoEntFireByInstanceHandle = function(entity, command, value)
    if entity.old then assert(command == "Stop"); stops = stops + 1
    else assert(command == "SetAnimation" and value == "au_portal_chanelling") end
end
PrecacheResource = function(kind, path) precached[kind] = path end
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        if fail_create then error("injected create failure") end
        assert(path == "particles/units/heroes/heroes_underlord/abbysal_underlord_portal_ambient.vpcf")
        assert(attach == PATTACH_WORLDORIGIN and owner == nil,
            "static spawn effects must not inherit a dormant prop's visibility or attachment")
        local id = #particles + 1
        particles[id] = { owner = owner, cp = {}, bindings = {}, orientation = {}, world = world }
        return id
    end,
    SetParticleControl = function(_, id, cp, value) particles[id].cp[cp] = value end,
    SetParticleAlwaysSimulate = function(_, id) particles[id].always_simulate = true end,
    SetParticleShouldCheckFoW = function(_, id, check) particles[id].check_fow = check end,
    SetParticleControlEnt = function()
        error("spawn landmarks must not depend on a prop attachment being evaluated")
    end,
    SetParticleControlOrientation = function(_, id, cp, forward, right, up)
        near(forward.x * right.x + forward.y * right.y + forward.z * right.z, 0)
        near(forward.x * up.x + forward.y * up.y + forward.z * up.z, 0)
        near(right.x * up.x + right.y * up.y + right.z * up.z, 0)
        for _, axis in ipairs({forward, right, up}) do near(axis.x^2 + axis.y^2 + axis.z^2, 1) end
        particles[id].orientation[cp] = { forward = forward, right = right, up = up }
    end,
    DestroyParticle = function(_, id, immediate)
        local p = particles[id]
        assert(immediate and not p.destroyed and p.world == world, "never destroy another world's indices")
        p.destroyed = true; destroyed = destroyed + 1
    end,
    ReleaseParticleIndex = function(_, id)
        assert(particles[id].destroyed and not particles[id].released)
        particles[id].released = true
    end,
}
local bus, events = require("core/event_bus"), require("core/events")
local service = require("systems/valley_environment_service")
local function check_last_four(name)
    local flat = name ~= "standard"
    for lane, direction in ipairs(expected) do
        local prop, particle = props[#props - 4 + lane], particles[#particles - 4 + lane]
        local marker, axes = positions[name][lane], particle.orientation[0]
        assert(particle.always_simulate and particle.check_fow == false,
            "static spawn landmarks must remain visible after off-screen sleep or unit-vision culling")
        assert(prop.yaw == direction[3] and prop.pitch == (flat and -90 or 0))
        assert(prop.kv.angles == string.format("%d %d 0", prop.pitch, prop.yaw))
        local attachment = assert(particle.cp[1])
        -- Compute the real model attachment's transformed local Z, rather
        -- than accepting a centered fallback while the actual model is offset.
        local model_up = flat and vector(-direction[1], -direction[2], 0) or vector(0, 0, 1)
        local actual = vector(prop.position.x + model_up.x * 97.362,
            prop.position.y + model_up.y * 97.362, prop.position.z + model_up.z * 97.362)
        near(actual.x, marker.x); near(actual.y, marker.y)
        near(actual.z, GetGroundHeight(marker) + 12 + (flat and 0 or 97.362))
        near(attachment.x, actual.x); near(attachment.y, actual.y)
        near(attachment.z, actual.z)
        near(particle.orientation[1].forward.x, axes.forward.x)
        near(particle.orientation[1].forward.y, axes.forward.y)
        near(particle.orientation[1].forward.z, axes.forward.z)
        near(particle.orientation[1].up.x, model_up.x)
        near(particle.orientation[1].up.y, model_up.y)
        near(particle.orientation[1].up.z, model_up.z)
        near(axes.forward.z, flat and 1 or 0)
        if not flat then near(axes.forward.x, direction[1]); near(axes.forward.y, direction[2]) end
        for _, cp in ipairs({0, 2}) do
            near(particle.orientation[cp].forward.z, axes.forward.z)
            near(particle.orientation[cp].up.x, model_up.x)
            near(particle.orientation[cp].up.y, model_up.y)
            near(particle.orientation[cp].up.z, model_up.z)
            near(particle.orientation[cp].right.x, direction[2])
            near(particle.orientation[cp].right.y, -direction[1])
            near(particle.cp[cp].x, prop.position.x); near(particle.cp[cp].z, prop.position.z)
        end
        assert(particle.cp[4].x == 0 and particle.cp[61].x == 0)
        assert(marker.z == (flat and 999 or 777), "must not move the gameplay spawn marker")
    end
end
service.precache({})
assert(precached.model and precached.particle)
service.init(); pending[#pending]()
assert(#props == 4 and #particles == 4 and stops == 4)
check_last_four("standard")
local before = #props
mode = "rich"; bus.emit(events.WAVE_CHANGED, {reason="mode_selected"})
assert(#props == before + 4 and destroyed == 4 and removed == 4, "selection must replace normal portals")
check_last_four("rich")
before = #props
bus.emit(events.WAVE_CHANGED, {reason="countdown_tick"}); bus.emit(events.BUILDER_READY, {})
assert(#props == before, "normal wave and builder events must not recreate particle effects")
mode = "cold"; bus.emit(events.BUILDER_READY, {})
assert(#props == before + 4); check_last_four("cold")
mode = "scourge"; bus.emit(events.WAVE_CHANGED, {})
check_last_four("scourge")
service.clear(); service.clear()
assert(destroyed == 16 and removed == 16, "cleanup is idempotent")
missing, searches = 2, {}
assert(service.apply() == 3, "missing advanced marker must not borrow a normal lane")
for _, name in ipairs(searches) do assert(not name:match("^monsterborn_player")) end
service.clear(); missing = nil
fail_create = true
assert(service.apply() == 0 and props[#props].removed, "failed particle must clean up model")
fail_create = nil
service.init()
local previous = pending[#pending]
service.init()
before = #props
previous(); assert(#props == before, "stale init callback must not create portals")
pending[#pending](); assert(#props == before + 4)
-- An actual module reload must retire the effects and subscriptions owned by
-- the earlier module instance without allowing its queued callback to reapply.
service.init(); previous = pending[#pending]
package.loaded["systems/valley_environment_service"] = nil
service = require("systems/valley_environment_service")
service.init(); before = #props
previous(); assert(#props == before)
pending[#pending](); assert(#props == before + 4)
before = #props
mode = "rich"; bus.emit(events.WAVE_CHANGED, {})
assert(#props == before + 4, "hot reload must leave only one active refresh subscriber")
local old_removed, old_destroyed = removed, destroyed
world = {}; service.clear(); service.init(); pending[#pending]()
assert(removed == old_removed and destroyed == old_destroyed, "new world must discard old handles")
bus.reset(); service.init(); pending[#pending]()
mode = "cold"; before = #props; bus.emit(events.WAVE_CHANGED, {})
assert(#props == before + 4, "init must resubscribe after event bus reset")
service.clear()
map = "other_map"
assert(service.apply() == 0)
mode, map = nil, "valley_decor_review"
assert(service.apply() == 4); check_last_four("standard"); service.clear()
print("VALLEY_UNDERLORD_PORTALS_PASS world-anchored effects without prop attachments; upright standard; 12 upward centered advanced portals; selection; no collision; cleanup; hot reload; worlds")
