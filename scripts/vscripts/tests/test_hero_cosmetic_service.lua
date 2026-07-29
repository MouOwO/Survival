package.path = "./scripts/vscripts/?.lua;./scripts/vscripts/?/init.lua;" .. package.path

local previous_spawn = SpawnEntityFromTableSynchronous
local previous_precache = PrecacheResource
local previous_remove = UTIL_Remove
local previous_particles = ParticleManager
local previous_no_draw = EF_NODRAW
local previous_attach = PATTACH_ABSORIGIN_FOLLOW

local spawned = {}
local removed = {}
local precached = {}
local created_particles = {}
local destroyed_particles = {}
local released_particles = {}

local function entity(class_name)
    local result = { class_name = class_name, null = false }
    function result:IsNull() return self.null end
    function result:GetClassname() return self.class_name end
    function result:AddEffects(effect) self.effect = effect end
    function result:SetOwner(owner) self.owner = owner end
    function result:FollowEntity(owner, bone_merge)
        self.follow_owner = owner
        self.bone_merge = bone_merge
    end
    return result
end

SpawnEntityFromTableSynchronous = function(class_name, data)
    local result = entity(class_name)
    result.model = data.model
    spawned[#spawned + 1] = result
    return result
end
PrecacheResource = function(resource_type, path)
    precached[#precached + 1] = resource_type .. ":" .. path
end
UTIL_Remove = function(target)
    target.null = true
    removed[#removed + 1] = target
end
ParticleManager = {
    CreateParticle = function(_, path, attach_type, owner)
        local id = 100 + #created_particles
        created_particles[#created_particles + 1] = {
            id = id,
            path = path,
            attach_type = attach_type,
            owner = owner,
        }
        return id
    end,
    DestroyParticle = function(_, id)
        destroyed_particles[#destroyed_particles + 1] = id
    end,
    ReleaseParticleIndex = function(_, id)
        released_particles[#released_particles + 1] = id
    end,
}
EF_NODRAW = 32
PATTACH_ABSORIGIN_FOLLOW = 17

package.loaded["systems/hero_cosmetic_service"] = nil
local service = require("systems/hero_cosmetic_service")

service.precache({})
local hallows_model = "model:models/items/undying/undying_fall20_immortal_head/undying_fall20_immortal_head.vmdl"
local hallows_particle = "particle:particles/econ/items/undying/fall20_undying_head/fall20_undying_head_ambient.vpcf"
local found_model = false
local found_particle = false
for _, value in ipairs(precached) do
    if value == hallows_model then found_model = true end
    if value == hallows_particle then found_particle = true end
end
assert(found_model, "The Hallows Within model was not precached")
assert(found_particle, "The Hallows Within ambient was not precached")

local default_wearable = entity("dota_item_wearable")
local hero = { children = { default_wearable } }
function hero:IsNull() return false end
function hero:entindex() return 77 end
function hero:FirstMoveChild() return self.children[1] end

assert(service.apply(hero, "builder_undying") == true,
    "builder cosmetic application failed")
assert(default_wearable.effect == EF_NODRAW,
    "default wearable was not hidden")
assert(#spawned == 1, "expected one oversized Head wearable")
assert(spawned[1].owner == hero and spawned[1].follow_owner == hero,
    "wearable did not follow the builder")
assert(spawned[1].bone_merge == true, "wearable bone merge was not enabled")
assert(#created_particles == 1, "expected one ambient particle")
assert(created_particles[1].owner == spawned[1],
    "ambient particle must attach to the named Head wearable")
assert(created_particles[1].attach_type == PATTACH_ABSORIGIN_FOLLOW,
    "ambient particle used the wrong attachment type")

assert(service.apply(hero, "builder_undying") == true,
    "repeat cosmetic application failed")
assert(#removed == 1, "repeat application did not remove the old wearable")
assert(#destroyed_particles == 1 and #released_particles == 1,
    "repeat application did not clean up the old particle")
assert(#spawned == 2 and #created_particles == 2,
    "repeat application did not create one clean replacement set")

service.clear(hero)
assert(#removed == 2, "explicit clear did not remove the replacement wearable")
assert(#destroyed_particles == 2 and #released_particles == 2,
    "explicit clear did not release the replacement particle")

SpawnEntityFromTableSynchronous = previous_spawn
PrecacheResource = previous_precache
UTIL_Remove = previous_remove
ParticleManager = previous_particles
EF_NODRAW = previous_no_draw
PATTACH_ABSORIGIN_FOLLOW = previous_attach

print("HERO_COSMETIC_SERVICE_PASS")