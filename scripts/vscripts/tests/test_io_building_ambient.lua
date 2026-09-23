-- Run from the addon root. Uses the real generated catalog and preload path;
-- mocks only engine APIs and the independent component attachment service.
package.path = "scripts/vscripts/?.lua;" .. package.path
local warnings = {}
package.loaded["core/logger"] = {
    info = function() end,
    warn = function(_, message) warnings[#warnings + 1] = message end,
}
package.loaded["core/scheduler"] = { after = function() error("unexpected asynchronous preload") end }
package.loaded["visual/native_wearable_carrier_service"] = { Clear = function() end }
package.loaded["visual/model_appearance_service"] = {
    Matches = function(unit, asset) return unit.appearance == asset.asset_id end,
    Refresh = function(unit, asset)
        unit.appearance = asset.asset_id
        return true, "ready", unit.components
    end,
    Clear = function(unit) unit.appearance = nil end,
}
GameRules = { GetGameTime = function() return 0 end }
Vector = function(x, y, z) return { x = x, y = y, z = z } end
PATTACH_ABSORIGIN_FOLLOW = 1
PATTACH_POINT_FOLLOW = 5
local static = {}
PrecacheResource = function(kind, path)
    local key = kind .. ":" .. path
    static[key] = (static[key] or 0) + 1
end
local created, destroyed, released = {}, {}, {}
local fail_control = nil
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        local id = #created + 1
        created[id] = { path = path, attach = attach, owner = owner, cp = {}, follow = {} }
        return id
    end,
    SetParticleControlEnt = function(_, id, cp, owner, attach, point, origin, lock)
        created[id].follow[cp] = {
            owner = owner, attach = attach, point = point, origin = origin, lock = lock,
        }
    end,
    SetParticleControl = function(_, id, cp, value)
        if fail_control == cp then error("injected control-point failure") end
        created[id].cp[cp] = value
    end,
    DestroyParticle = function(_, id)
        assert(not destroyed[id], "particle destroyed twice")
        destroyed[id] = true
    end,
    ReleaseParticleIndex = function(_, id)
        assert(not released[id], "particle handle released twice")
        released[id] = true
    end,
}
local function building(index)
    return {
        index = index, origin = Vector(100, 200, 30), components = {},
        IsNull = function() return false end,
        entindex = function(self) return self.index end,
        GetAbsOrigin = function(self) return self.origin end,
        SetModel = function(self, path) self.model = path end,
        SetOriginalModel = function(self, path) self.original_model = path end,
        SetModelScale = function(self, scale) self.scale = scale end,
        SetSkin = function(self, skin) self.skin = skin end,
    }
end

local catalog = require("config/asset_catalog")
local io_asset_id = "tower_laser_od_blackgate"
local io_asset = catalog.resolve(io_asset_id)
local path = "particles/units/heroes/hero_wisp/wisp_ambient.vpcf"
assert(io_asset.primary_model == "models/heroes/wisp/wisp.vmdl")
assert(#io_asset.components == 0, "Io must not gain fabricated body wearables")
assert(#io_asset.ambient.effects == 1 and #io_asset.environment_particles == 1)
local descriptor = io_asset.environment_particles[1]
assert(descriptor.path == path and descriptor.control_profile == "io_base_ambient")
assert(descriptor.attach_type == "PATTACH_POINT_FOLLOW" and descriptor.attachment_point == "attach_hitloc")
assert((descriptor.owner or "") == "", "Io ambient must be attached to the original Building")
local io_owners = 0
for _, asset in ipairs(catalog.rows) do
    for _, effect in ipairs(asset.ambient.effects) do
        if effect.particle_path == path then
            io_owners = io_owners + 1
            assert(asset.asset_id == io_asset_id, "Io ambient leaked into another tower")
        end
    end
end
assert(io_owners == 1)

-- Old string environment declarations remain valid. These synthetic entries
-- travel through the real preload path as initial_required resources too.
local legacy = {
    asset_id = "legacy_ambient_test", primary_model = "models/test_legacy.vmdl",
    load_group = "initial_required", enabled = true, components = {},
    particle_resources = { "particles/test_legacy.vpcf" },
    environment_particles = { "particles/test_legacy.vpcf" },
    environment_particle_owners = { "crown" },
}
catalog.rows[#catalog.rows + 1] = legacy
catalog.by_id[legacy.asset_id] = legacy
local preload = require("systems/asset_preload_service")
local resources = preload.resources_for_assets({ io_asset_id })
local ambient_count = 0
for _, resource in ipairs(resources) do
    if resource.resource_type == "particle" and resource.path == path then
        ambient_count = ambient_count + 1
    end
end
assert(ambient_count == 1, "Io ambient missing or duplicated in expanded preload resources")
preload.precache_initial({})
assert(static["particle:" .. path] == 1, "initial preload did not submit Io ambient")
assert(preload.is_ready(io_asset_id))

local visual = require("systems/building_visual_service")
local tower = building(7)
local data = { model_asset_id = io_asset_id }
assert(visual.apply(tower, data))
assert(#created == 1 and created[1].path == path and created[1].owner == tower)
assert(created[1].attach == PATTACH_POINT_FOLLOW)
assert(created[1].follow[0].owner == tower and created[1].follow[0].point == "attach_hitloc")
assert(created[1].follow[0].attach == PATTACH_POINT_FOLLOW)
assert(created[1].follow[1].owner == tower and created[1].follow[1].attach == PATTACH_ABSORIGIN_FOLLOW)
local function vector_is(actual, x, y, z)
    return actual and actual.x == x and actual.y == y and actual.z == z
end
assert(vector_is(created[1].cp[10], 1, 1, 0), "native Io palette/heartbeat controls changed")
assert(vector_is(created[1].cp[11], 1, 0, 0), "Io incorrectly displays its red low-health layer")
assert(vector_is(created[1].cp[13], 0, 1, 1), "Io normal body layers were suppressed")
assert(tower.model == io_asset.primary_model and tower.original_model == tower.model)

-- Repeated attributes/level updates and relocation keep the current emitter.
-- The particle follows the Building via entity-bound CP0/CP1, not a stale vector.
tower.origin = Vector(800, 900, 20)
for level = 2, 5 do
    assert(visual.apply(tower, { model_asset_id = io_asset_id, level = level }))
end
assert(#created == 1 and not destroyed[1], "same-asset refresh restarted the persistent body")

-- A different stage cleans up the emitter without attaching Io's visuals to
-- that stage. Rebuilding and destroying the Io stage cleans up exactly once.
assert(visual.apply(tower, { model_asset_id = "tower_laser_death_prophet_brightshroud" }))
assert(#created == 1 and destroyed[1] and released[1])
assert(visual.apply(tower, data))
assert(#created == 2 and not destroyed[2])
visual.clear(tower)
assert(destroyed[2] and released[2])
visual.clear(tower)
assert(visual.apply(tower, data))
assert(#created == 3 and not destroyed[3])

-- Entity indices can be reused. A new entity must not inherit the old owner's
-- particle even when both asset ID and numeric index are unchanged.
local replacement = building(7)
assert(visual.apply(replacement, data))
assert(#created == 4 and created[4].owner == replacement and destroyed[3])
visual.clear(tower)
assert(not destroyed[4], "old owner's cleanup destroyed a replacement entity's particle")
visual.clear(replacement)

-- Legacy strings keep their owner component and receive no Io control points.
local old_tower = building(8)
local crown = building(9)
old_tower.components.crown = crown
assert(visual.apply(old_tower, { model_asset_id = legacy.asset_id }))
assert(#created == 5 and created[5].owner == crown)
assert(created[5].attach == PATTACH_ABSORIGIN_FOLLOW and next(created[5].cp) == nil)
assert(next(created[5].follow) == nil, "legacy string particle received unrelated bindings")
assert(visual.apply(old_tower, { model_asset_id = legacy.asset_id }))
assert(#created == 5 and not destroyed[5])
old_tower.components.crown = building(10)
assert(visual.apply(old_tower, { model_asset_id = legacy.asset_id }))
assert(#created == 6 and destroyed[5] and created[6].owner == old_tower.components.crown)
visual.clear(old_tower)
assert(destroyed[6])

-- A failed control point must not leave a red/unconfigured loop, or cache it
-- as successful and prevent a later property refresh from retrying.
local retry_tower = building(11)
fail_control = 11
assert(visual.apply(retry_tower, data))
assert(#created == 7 and destroyed[7] and released[7] and #warnings == 1)
fail_control = nil
assert(visual.apply(retry_tower, data))
assert(#created == 8 and not destroyed[8] and vector_is(created[8].cp[11], 1, 0, 0))
assert(visual.apply(retry_tower, data))
assert(#created == 8)
visual.clear(retry_tower)
assert(destroyed[8] and released[8])
print("IO_BUILDING_AMBIENT_PASS: native controls, initial preload, refresh reuse, stage/owner cleanup, legacy and retry")
