package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

package.loaded["config/monster_visual_config"] = {
    resources_for_wave = function(wave_number)
        if wave_number == 6 then
            return {
                {
                    resource_type = "model",
                    path = "models/test/next_wave.vmdl",
                    async_unit_name = "asset_proxy_test_next_wave",
                },
            }
        end
        return {
            { resource_type = "model", path = "models/test/main.vmdl" },
            { resource_type = "particle", path = "particles/test/ambient.vpcf" },
        }
    end,
}
package.loaded["systems/monster_visual_service"] = nil

PATTACH_ABSORIGIN_FOLLOW = 1
EF_BONEMERGE = 2

local next_particle = 0
local destroyed = {}
local released = {}
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        assert(path:match("particles/test/") and attach == PATTACH_ABSORIGIN_FOLLOW)
        assert(owner ~= nil)
        next_particle = next_particle + 1
        return next_particle
    end,
    DestroyParticle = function(_, particle, immediate)
        destroyed[particle] = immediate
    end,
    ReleaseParticleIndex = function(_, particle)
        released[particle] = true
    end,
}

local removed = {}
UTIL_Remove = function(entity) removed[entity] = true end
local attachments = {}
SpawnEntityFromTableSynchronous = function(entity_class, data)
    assert(entity_class == "prop_dynamic" and data.solid == "0")
    local entity = { null = false }
    function entity:IsNull() return self.null end
    function entity:SetOwner(owner) self.owner = owner end
    function entity:SetParent(owner) self.parent = owner end
    function entity:FollowEntity(owner, merge) self.follow = owner; self.merge = merge end
    function entity:AddEffects(effect) self.effect = effect end
    attachments[#attachments + 1] = entity
    return entity
end

local unit = { index = 77 }
function unit:IsNull() return false end
function unit:entindex() return self.index end
function unit:SetModel(path) self.model = path end
function unit:SetOriginalModel(path) self.original_model = path end
function unit:SetModelScale(scale) self.scale = scale end

local resolved = {
    visual_asset_id = "test_visual",
    visual_role = "stage_boss",
    model_path = "models/test/main.vmdl",
    model_scale = 1.75,
    components = {
        { model_path = "models/test/head.vmdl", enabled = true },
    },
    effects = {
        { particle_path = "particles/test/a.vpcf", max_per_unit = 2 },
        { particle_path = "particles/test/b.vpcf", max_per_unit = 2 },
    },
}

local service = require("systems/monster_visual_service")
local ok, asset_id = service.apply(unit, resolved)
assert(ok and asset_id == "test_visual")
assert(unit.model == resolved.model_path and unit.original_model == resolved.model_path)
assert(unit.scale == 1.75 and unit.survival_monster_visual_role == "stage_boss")
assert(#attachments == 1 and attachments[1].owner == unit
    and attachments[1].follow == unit and attachments[1].merge == true)
local state = assert(service._state_for_test(unit.index))
assert(#state.particles == 2, "per-unit particle limit was not enforced")

service.apply(unit, resolved)
assert(removed[attachments[1]] == true, "reapply did not remove old attachment")
assert(destroyed[1] == true and destroyed[2] == true,
    "reapply did not immediately destroy old particles")
assert(released[1] and released[2], "reapply did not release old particles")

service.cleanup(unit)
assert(service._state_for_test(unit.index) == nil, "cleanup retained visual state")
assert(removed[attachments[2]] == true, "cleanup did not remove attachment")
assert(destroyed[3] == true and destroyed[4] == true,
    "cleanup did not immediately destroy particles")

local precached = {}
PrecacheResource = function(resource_type, path, context)
    assert(context == "test_context")
    precached[resource_type .. ":" .. path] = true
end
assert(service.precache_wave("test_context", 5) == 2)
assert(service.queue_wave(5) == true)

local async_requests = {}
PrecacheUnitByNameAsync = function(unit_name, callback, player_id)
    assert(unit_name == "asset_proxy_test_next_wave" and player_id == -1)
    async_requests[#async_requests + 1] = callback
end
local queued, queue_status = service.queue_wave(6)
assert(queued and queue_status == "loading" and #async_requests == 1,
    "next-wave model was not queued asynchronously")
local duplicate_ok, duplicate_status = service.queue_wave(6)
assert(duplicate_ok and duplicate_status == "loading" and #async_requests == 1,
    "duplicate next-wave queue was not idempotent")
async_requests[1]()
local ready, ready_status = service.queue_wave(6)
assert(ready and ready_status == "ready" and #async_requests == 1,
    "async next-wave model did not become ready")

print("MONSTER_VISUAL_SERVICE_PASS")