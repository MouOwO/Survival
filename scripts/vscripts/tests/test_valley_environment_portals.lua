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
Vector = vector
PATTACH_ABSORIGIN_FOLLOW, PATTACH_POINT_FOLLOW = 1, 2
local world, map = {}, "template_map"
GameRules = { GetGameModeEntity = function() return world end }
GetMapName = function() return map end
GetGroundHeight = function() return 128 end
local positions = {
    vector(88, 4096, 128), vector(-1024, 2984, 128),
    vector(-2136, 4096, 128), vector(-1024, 5208, 128),
}
local expected = { {1, 0, 0}, {0, -1, 270}, {-1, 0, 180}, {0, 1, 90} }
local missing
Entities = { FindByName = function(_, _, name)
    local lane = tonumber(name:match("^monsterborn_player(%d)$"))
    if lane and lane ~= missing then return { GetAbsOrigin = function() return positions[lane] end } end
    if name:find("^valley_decor_v1_fx_") then return { old = true } end
end }
local props, particles, precached = {}, {}, {}
local stops, destroyed, removed = 0, 0, 0
local fail_create
SpawnEntityFromTableSynchronous = function(class, kv)
    assert(class == "prop_dynamic" and kv.solid == 0, "portal must be decorative and nonsolid")
    assert(kv.DefaultAnim == "au_portal_chanelling")
    assert(kv.model == "models/heroes/abyssal_underlord/abyssal_underlord_portal_model.vmdl")
    local prop = { kv = kv, world = world }
    function prop:IsNull() return self.removed == true end
    function prop:SetAbsOrigin(value) self.position = value end
    function prop:SetAngles(pitch, yaw, roll)
        assert(pitch == 0 and roll == 0, "door must stay upright")
        self.yaw = yaw
    end
    props[#props + 1] = prop
    return prop
end
UTIL_Remove = function(prop)
    assert(not prop.removed and prop.world == world)
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
        assert(attach == PATTACH_ABSORIGIN_FOLLOW and owner)
        local id = #particles + 1
        particles[id] = { owner = owner, cp = {}, bindings = {}, orientation = {}, world = world }
        return id
    end,
    SetParticleControl = function(_, id, cp, value) particles[id].cp[cp] = value end,
    SetParticleControlEnt = function(_, id, cp, owner, attach, name)
        assert(particles[id].owner == owner)
        particles[id].bindings[cp] = { attach = attach, name = name }
    end,
    SetParticleControlOrientation = function(_, id, cp, forward, right, up)
        assert(up.z == 1 and forward.z == 0 and right.z == 0)
        assert(math.abs(forward.x * right.x + forward.y * right.y) < 1e-9)
        particles[id].orientation[cp] = forward
    end,
    DestroyParticle = function(_, id, immediate)
        local p = particles[id]
        assert(immediate and not p.destroyed and p.world == world)
        p.destroyed = true; destroyed = destroyed + 1
    end,
    ReleaseParticleIndex = function(_, id)
        assert(particles[id].destroyed and not particles[id].released)
        particles[id].released = true
    end,
}
local service = require("systems/valley_environment_service")
service.precache({})
assert(precached.model and precached.particle)
service.init(); pending[#pending]()
assert(#props == 4 and #particles == 4 and stops == 4)
for lane, direction in ipairs(expected) do
    local prop, particle = props[lane], particles[lane]
    assert(prop.yaw == direction[3])
    assert(prop.position.x == positions[lane].x and prop.position.y == positions[lane].y)
    assert(prop.position.z == 140 and positions[lane].z == 128, "must not mutate spawn marker")
    local forward = particle.orientation[0]
    assert(math.abs(forward.x - direction[1]) < 1e-9 and math.abs(forward.y - direction[2]) < 1e-9)
    assert(particle.bindings[1].name == "attach_portal" and particle.bindings[1].attach == PATTACH_POINT_FOLLOW)
    assert(particle.cp[4].x == 0 and particle.cp[61].x == 0)
end
assert(service.apply() == 4 and destroyed == 4 and removed == 4, "reapply retires old portals")
service.clear(); service.clear()
assert(destroyed == 8 and removed == 8, "cleanup is idempotent")
missing = 2
assert(service.apply() == 3, "missing marker must not duplicate another lane")
service.clear(); missing = nil
fail_create = true
assert(service.apply() == 0 and props[#props].removed, "failed particle must clean up model")
fail_create = nil
service.init()
local previous = pending[#pending]
service.init()
local before = #props
previous(); assert(#props == before, "stale init callback must not create portals")
pending[#pending](); assert(#props == before + 4)
local old_removed, old_destroyed = removed, destroyed
world = {}; service.init(); pending[#pending]()
assert(removed == old_removed and destroyed == old_destroyed, "new world must not remove old handles")
service.clear()
map = "other_map"
assert(service.apply() == 0)
map = "valley_decor_review"
assert(service.apply() == 4); service.clear()
print("VALLEY_UNDERLORD_PORTALS_PASS four lane orientations, attachments, no collision, cleanup, failure, worlds")
