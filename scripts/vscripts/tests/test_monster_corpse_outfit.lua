package.path = "scripts/vscripts/?.lua;" .. package.path

local now, tick = 0, nil
GameRules = { GetGameTime = function() return now end }
Vector = function(x, y, z) return { x = x, y = y, z = z } end
UTIL_Remove = function(unit) unit.removed = true end
package.loaded["core/scheduler"] = {
    cancel = function() end,
    every = function(_, callback) tick = callback end,
}
package.loaded["config/generated/global_rules"] = { by_id = {} }
package.loaded["visual/model_appearance_service"] = {
    Clear = function(unit)
        unit.outfit = false
        unit.clears = (unit.clears or 0) + 1
    end,
}
local bus = require("core/event_bus")
local events = require("core/events")
local hero = require("systems/monster_hero_visual_service")
local corpse = require("systems/monster_corpse_lifecycle_service")

local function make_unit()
    return {
        outfit = true,
        survival_monster_default_wearable_asset_id = "monster_wave_humanoid_red_axe",
        IsNull = function(self) return self.removed == true end,
        GetAbsOrigin = function() return Vector(10, 20, 30) end,
        SetAbsOrigin = function(self, origin) self.origin = origin end,
        AddNoDraw = function(self) self.hidden = true end,
    }
end

-- Death handlers may run in either order. The outfit must survive both.
for _, visual_first in ipairs({ true, false }) do
    now, tick = 0, nil
    bus.reset()
    corpse.init()
    local unit = make_unit()
    corpse.track(unit, "wave")
    if visual_first then hero.on_death(unit) end
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = unit })
    if not visual_first then hero.on_death(unit) end
    assert(unit.outfit and not unit.clears, "death removed the outfit before animation")
    now = 0.7
    tick()
    assert(unit.outfit and unit.origin.z < 30, "outfit missing while corpse sinks")
    bus.emit(events.ENGINE_ENTITY_KILLED, { victim = unit })
    now = 1.5
    tick()
    assert(unit.hidden and not unit.outfit and unit.clears == 1,
        "outfit not cleared exactly once when corpse becomes hidden")
    now = 1.6
    tick()
    assert(unit.removed, "corpse was not removed after hiding")
end

local early = make_unit()
corpse.track(early, "wave")
bus.emit(events.ENGINE_ENTITY_KILLED, { victim = early })
early.removed = true
tick()
assert(not early.outfit, "engine-removed corpse leaked its outfit")

local forced = make_unit()
corpse.track(forced, "wave")
forced.survival_wave_cleanup = true
hero.on_death(forced)
assert(not forced.outfit, "forced wave cleanup retained an outfit")
local untracked = make_unit()
hero.on_death(untracked)
assert(not untracked.outfit, "untracked unit has no corpse owner to clean its outfit")

-- Exercise the real component store when the engine invalidates its owner.
package.loaded["visual/model_appearance_service"] = nil
local appearance = require("visual/model_appearance_service")
local component = {
    IsNull = function(self) return self.removed == true end,
    SetOwner = function() end,
    FollowEntity = function() end,
}
SpawnEntityFromTableSynchronous = function() return component end
local owner = make_unit()
function owner:entindex()
    assert(not self.removed, "called entindex on an invalid corpse")
    return 919
end
assert(appearance.Apply(owner, {
    asset_id = "corpse_test",
    components = { { component_id = "hat", model_path = "models/test/hat.vmdl" } },
}))
owner.removed = true
assert(appearance.Clear(owner) and component.removed,
    "real appearance store leaked an invalid owner's component")
print("MONSTER_CORPSE_OUTFIT_PASS")
