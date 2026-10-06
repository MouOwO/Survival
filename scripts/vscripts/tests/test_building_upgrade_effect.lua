package.path = "scripts/vscripts/?.lua;" .. package.path

local scheduled, cancelled, created, released = {}, {}, {}, {}
package.loaded["core/scheduler"] = {
    after = function(_, callback, id) scheduled[id] = callback; return id end,
    cancel = function(id) cancelled[id] = true end,
}
package.loaded["core/logger"] = {info = function() end}
package.loaded["systems/asset_preload_service"] = {}
local warp_paths = {}
package.loaded["systems/building_warp_effects"] = {
    create = function(path) warp_paths[#warp_paths + 1] = path end,
    destroy = function() end,
    is_shell = function() return false end,
    is_white = function() return false end,
    reset_shells = function() end,
}
PATTACH_ABSORIGIN_FOLLOW = 1
ParticleManager = {
    CreateParticle = function(_, path, attach, unit)
        created[#created + 1] = {path = path, attach = attach, unit = unit}
        return #created
    end,
    SetParticleControl = function(_, id, cp, position)
        assert(cp == 0 and position == created[id].unit:GetAbsOrigin())
    end,
    ReleaseParticleIndex = function(_, id)
        assert(not released[id], "each one-shot handle must be released once")
        released[id] = true
    end,
}
local effect = require("systems/building_upgrade_effect")
local preloaded
PrecacheResource = function(kind, path, context)
    assert(kind == "particle" and context == "load")
    preloaded = path
end
effect.precache("load")
assert(preloaded == effect.particle)

local process = require("systems/building_upgrade_process")
local unit = {position = {x = 5000, y = -2000, z = 384}}
function unit:IsNull() return self.removed == true end
function unit:IsAlive() return not self.dead end
function unit:entindex() return 77 end
function unit:GetAbsOrigin() return self.position end
local function begin(callback, cancel)
    assert(process.begin(unit, {
        duration = 1, on_complete = callback, on_cancel = cancel,
        definition = {build_start_particle = "start", build_complete_particle = "old_flash"},
    }).ok)
    return scheduled[process._active_for_test(77).task_id]
end
local completions = 0
local finish = begin(function() completions = completions + 1 end)
assert(#created == 0, "do not play success effects during upgrading")
finish(); finish()
assert(completions == 1 and #created == 1 and released[1])
assert(created[1].unit == unit and created[1].path == effect.particle)
assert(created[1].attach == PATTACH_ABSORIGIN_FOLLOW)
assert(not process.is_active(unit) and not unit.survival_upgrade_in_progress)

begin(function() return false end)()
begin(function() error("expected completion failure") end)()
finish = begin(function() error("cancelled upgrade must not complete") end)
assert(process.cancel_by_entindex(77, "cancelled")); finish()
finish = begin(function() error("dead building must not complete") end)
unit.dead = true; finish(); unit.dead = false
finish = begin(function() unit.removed = true end); finish()
assert(#created == 1, "failed/cancelled/dead/removed upgrades must not flash")
for _, path in ipairs(warp_paths) do assert(path ~= "old_flash", "no duplicate completion effect") end

local definitions = require("config/generated/building_sound_definitions")
local upgrade_count = 0
for _, row in ipairs(definitions.rows) do
    if row.phase == "upgrade_complete" then
        assert(#row.sound_events == 1 and row.sound_events[1] == "General.LevelUp")
        assert(row.sound_resources[1] == "soundevents/game_sounds_ui_imported.vsndevts")
        upgrade_count = upgrade_count + 1
    end
end
assert(upgrade_count == 17, "all building and tower upgrade cues must use hero audio")
print("BUILDING_UPGRADE_EFFECT_PASS")
