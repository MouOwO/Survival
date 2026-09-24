-- Run from the game addon root: lua scripts/vscripts/tests/test_building_death_visual.lua
package.path = "scripts/vscripts/?.lua;" .. package.path
local tasks, queued, appearance_cleared, carrier_cleared = {}, {}, {}, {}
local pending, ready = {}, true
local asset = {asset_id = "tower_test", primary_model = "tower.vmdl",
    bodygroups = {{bodygroup_name = "tower_crown", value = 1}},
    activity_modifiers = {{modifier_name = "tower"}}, environment_particles = {}}
package.loaded["config/asset_catalog"] = {
    model = function() return asset.primary_model, asset end,
}
package.loaded["core/logger"] = {warn = function() end}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, id)
        assert(delay == 4, "death uses a bounded, one-shot lifetime")
        tasks[id] = callback; queued[#queued + 1] = callback
    end,
    cancel = function(id) tasks[id] = nil end,
}
package.loaded["systems/asset_preload_service"] = {
    is_ready = function() return ready end,
    queue = function(_, options) pending[#pending + 1] = options; return true, "queued" end,
    status = function() return {status = "queued"} end,
    STATE = {FAILED = "failed", RETIRED = "retired"},
}
package.loaded["visual/model_appearance_service"] = {
    Matches = function() return true end,
    Refresh = function() return true, "ready", {} end,
    Clear = function(unit) appearance_cleared[unit] = (appearance_cleared[unit] or 0) + 1 end,
}
package.loaded["visual/native_wearable_carrier_service"] = {
    Clear = function(unit) carrier_cleared[unit] = (carrier_cleared[unit] or 0) + 1 end,
}
package.loaded["systems/unit_health_bar_service"] = {
    exclude = function(unit) unit.bar_excluded = true end,
}
ACT_DOTA_DIE = 1500
SOLID_NONE = 0
UTIL_Remove = function(unit) unit.removed = true; unit.invalid = true end
IsValidEntity = function(unit) return not unit.invalid end
local model_sets = 0
local function unit(index)
    return {
        alive = true, bodygroups = {},
        entindex = function() return index end,
        IsNull = function(self) return self.invalid == true end,
        IsAlive = function(self) return self.alive end,
        GetPlayerOwnerID = function() return 0 end,
        SetControllableByPlayer = function(self, _, value) self.controllable = value end,
        SetForceAttackTarget = function(self, target) self.target = target end,
        SetIdleAcquire = function(self, value) self.acquire = value end,
        SetAcquisitionRange = function(self, value) self.range = value end,
        SetHullRadius = function(self, value) self.hull = value end,
        SetSolid = function(self, value) self.solid = value end,
        StartGesture = function(self, activity) self.gesture = activity end,
        SetPlaybackRate = function() end,
        SetModel = function() model_sets = model_sets + 1 end,
        SetOriginalModel = function() end,
        AddActivityModifier = function(self) self.activity = true end,
        ClearActivityModifiers = function(self) self.activity = false end,
        SetBodygroupByName = function(self, name, value) self.bodygroups[name] = value end,
        ResetSequence = function(self) self.idle_resets = (self.idle_resets or 0) + 1 end,
        ResetSequenceInfo = function() end,
    }
end
local visual = require("systems/building_visual_service")
local tower = unit(10)
assert(not visual.play_death(tower), "living gameplay units must not become corpses")
assert(#queued == 0 and not tower.bar_excluded)
assert(visual.apply(tower, {model_asset_id = asset.asset_id}))
local baseline_clear = carrier_cleared[tower]
tower.alive = false; tower.target = {}
local before = tower.idle_resets
assert(visual.play_death(tower))
assert(tower.hull == 0 and tower.solid == 0 and tower.target == nil)
assert(tower.acquire == false and tower.range == 0 and tower.controllable == false)
assert(tower.bar_excluded and tower.gesture == ACT_DOTA_DIE)
assert(not appearance_cleared[tower] and carrier_cleared[tower] == baseline_clear,
    "wearables must survive until the native death animation finishes")
assert(tower.idle_resets == before and tower.bodygroups.tower_crown == 1)
assert(visual.play_death(tower) and #queued == 1, "duplicate deaths must not reschedule")
assert(not visual.apply(tower, {model_asset_id = asset.asset_id}), "dead visual cannot refresh")
queued[1]()
assert(appearance_cleared[tower] == 1 and tower.removed)
assert(tower.bodygroups.tower_crown == 0)
queued[1]()
assert(appearance_cleared[tower] == 1, "callback cannot clear twice")

-- A preload requested while alive may finish after the tower was destroyed.
local loading = unit(11)
ready = false
assert(visual.apply(loading, {model_asset_id = asset.asset_id}))
loading.alive = false
assert(visual.play_death(loading))
ready = true
local before_models = model_sets
pending[1].on_ready(); pending[1].on_failed()
assert(model_sets == before_models and loading.survival_pending_model_asset_id == nil,
    "late asset callbacks must not restore/reset the corpse")
local loading_cleanup = queued[#queued]
visual.clear(loading)
local count = appearance_cleared[loading]
loading_cleanup()
assert(appearance_cleared[loading] == count and not loading.removed,
    "explicit teardown must cancel the deferred callback")

-- Old corpse disappears natively, then its index is reused by a new live tower.
local old, replacement = unit(12), unit(12)
assert(visual.apply(old, {model_asset_id = asset.asset_id}))
old.alive = false
assert(visual.play_death(old))
local stale_cleanup = queued[#queued]
old.invalid = true
assert(visual.apply(replacement, {model_asset_id = asset.asset_id}))
stale_cleanup()
assert(not replacement.removed and not appearance_cleared[replacement])
assert(replacement.activity and replacement.bodygroups.tower_crown == 1,
    "old corpse cleanup must not mutate the replacement's visual cache")
assert(appearance_cleared[old] == 1, "expired corpse still releases owned wearables")

-- Models without a script gesture method retain the engine-selected death.
local native = unit(13); native.alive = false; native.StartGesture = nil
assert(visual.play_death(native))
assert(native.idle_resets == nil, "fallback must not overwrite native death with idle")
queued[#queued]()
assert(native.removed)
local reset = unit(14); reset.alive = false
assert(visual.play_death(reset))
local pre_reset_cleanup = queued[#queued]
visual.init()
assert(reset.removed and appearance_cleared[reset] == 1)
pre_reset_cleanup()
assert(appearance_cleared[reset] == 1, "old map cleanup must not run after initialization")

-- The component service must also reject its independent deferred refreshes.
package.loaded["visual/model_appearance_service"] = nil
local component_service = require("visual/model_appearance_service")
local dead_attachment_owner = unit(15)
dead_attachment_owner.survival_building_death_visual = true
local applied, reason = component_service.Apply(dead_attachment_owner, asset)
assert(applied == false and reason == "building_dead")
print("BUILDING_DEATH_VISUAL_PASS: native corpse, no collision/acquisition/bar, async guard, reuse safety, teardown")
