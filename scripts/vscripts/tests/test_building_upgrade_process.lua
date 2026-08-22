package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local TELEPORT = "particles/items2_fx/teleport_start.vpcf"
local GENERIC = "particles/test/building_upgrade.vpcf"

PATTACH_WORLDORIGIN = 7
Vector = function(x, y, z) return { x = x, y = y, z = z } end

local tasks = {}
local cancelled_tasks = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, task_id)
        tasks[task_id] = { delay = delay, callback = callback }
        return task_id
    end,
    cancel = function(task_id)
        cancelled_tasks[#cancelled_tasks + 1] = task_id
        tasks[task_id] = nil
    end,
}

local queued_assets = {}
package.loaded["systems/asset_preload_service"] = {
    queue = function(asset_id, options)
        queued_assets[#queued_assets + 1] = {
            asset_id = asset_id,
            options = options,
        }
        return true, "queued"
    end,
}

local created = {}
local controls = {}
local destroyed = {}
local released = {}
local next_particle = 100
local fail_control = false
ParticleManager = {
    CreateParticle = function(_, path, attach, owner)
        next_particle = next_particle + 1
        created[#created + 1] = {
            id = next_particle,
            path = path,
            attach = attach,
            owner = owner,
        }
        return next_particle
    end,
    SetParticleControl = function(_, particle, cp, value)
        if fail_control then error("simulated control failure") end
        controls[#controls + 1] = {
            particle = particle,
            cp = cp,
            value = value,
        }
    end,
    DestroyParticle = function(_, particle, immediate)
        destroyed[#destroyed + 1] = {
            particle = particle,
            immediate = immediate,
        }
    end,
    ReleaseParticleIndex = function(_, particle)
        released[#released + 1] = particle
    end,
}

local function unit(entindex, x)
    local result = {
        alive = true,
        origin = Vector(x, x + 10, 32),
    }
    function result:IsNull() return false end
    function result:IsAlive() return self.alive end
    function result:entindex() return entindex end
    function result:GetAbsOrigin() return self.origin end
    return result
end

local function only_task()
    local found = nil
    for task_id, task in pairs(tasks) do
        assert(found == nil, "expected exactly one scheduled upgrade task")
        found = { id = task_id, task = task }
    end
    return assert(found, "upgrade completion task was not scheduled")
end

package.loaded["systems/building_upgrade_process"] = nil
local process = require("systems/building_upgrade_process")

local completed = 0
local visual_statuses = {}
local first = unit(701, 120)
local started = process.begin(first, {
    duration = 1,
    particle = TELEPORT,
    target_level = 2,
    target_model_asset_id = "tower_level_2",
    target_model_name = "models/test/tower_level_2.vmdl",
    on_complete = function() completed = completed + 1 end,
    on_visual_status = function(status)
        visual_statuses[#visual_statuses + 1] = status
    end,
})
assert(started.ok and started.pending and started.duration == 1,
    "valid building upgrade did not start")
assert(first.survival_upgrade_in_progress
        and first.survival_upgrade_target_level == 2,
    "upgrade state was not projected onto the building")
assert(#created == 1 and created[1].path == TELEPORT
        and created[1].attach == PATTACH_WORLDORIGIN
        and created[1].owner == first,
    "upgrade particle was not created at a world origin")
assert(#controls == 2 and controls[1].cp == 0
        and controls[1].value == first.origin,
    "upgrade particle CP0 did not use the building origin")
assert(controls[2].cp == 7 and controls[2].value.x == 1,
    "teleport upgrade particle duration did not match the upgrade transaction")
assert(#queued_assets == 1 and queued_assets[1].asset_id == "tower_level_2"
        and visual_statuses[1] == "queued",
    "target model preload status was not preserved")

local duplicate = process.begin(first, {})
assert(not duplicate.ok and duplicate.error == "upgrade_in_progress",
    "duplicate upgrade was not rejected")

local completion = only_task()
tasks[completion.id] = nil
completion.task.callback()
assert(completed == 1 and not process.is_active(first),
    "scheduled upgrade did not complete exactly once")
assert(#destroyed == 1 and destroyed[1].particle == created[1].id
        and destroyed[1].immediate == false
        and released[1] == created[1].id,
    "completed upgrade did not gracefully destroy and release its particle")
assert(first.survival_upgrade_in_progress == nil
        and first.survival_upgrade_target_level == nil
        and first.survival_upgrade_target_model_asset_id == nil
        and first.survival_upgrade_target_model_name == nil,
    "completed upgrade left runtime state on the building")

local cancel_reason = nil
local second = unit(702, 240)
local second_result = process.begin(second, {
    duration = 2,
    particle = GENERIC,
    on_cancel = function(reason) cancel_reason = reason end,
})
assert(second_result.ok and #created == 2,
    "generic upgrade particle was not created")
assert(#controls == 3 and controls[3].cp == 0
        and controls[3].value == second.origin,
    "generic upgrade particle did not receive only its required world origin")
assert(process.cancel_by_entindex(702, "building_destroyed")
        and cancel_reason == "building_destroyed",
    "building destruction did not cancel the active upgrade")
assert(not process.is_active(second) and #destroyed == 2
        and released[2] == created[2].id,
    "cancelled upgrade left particle or activity state behind")

local no_origin = unit(703, 360)
no_origin.GetAbsOrigin = nil
local no_origin_result = process.begin(no_origin, {
    duration = 1,
    particle = TELEPORT,
})
assert(no_origin_result.ok and #created == 2,
    "missing building origin created a particle at the default world origin")
assert(process.cancel_by_entindex(703, "test_cleanup"),
    "originless upgrade could not be cleaned up")

local failed_control_unit = unit(704, 480)
fail_control = true
local failed_control_result = process.begin(failed_control_unit, {
    duration = 1,
    particle = TELEPORT,
})
fail_control = false
assert(failed_control_result.ok and #created == 3
        and #destroyed == 3 and destroyed[3].immediate == true
        and released[3] == created[3].id,
    "particle control failure left a default-origin particle alive")
assert(process.cancel_by_entindex(704, "test_cleanup")
        and #destroyed == 3,
    "failed particle initialization was retained as active particle state")

local reset_first = unit(705, 600)
local reset_second = unit(706, 720)
assert(process.begin(reset_first, { duration = 3, particle = GENERIC }).ok)
assert(process.begin(reset_second, { duration = 3, particle = GENERIC }).ok)
process.reset()
assert(not process.is_active(reset_first) and not process.is_active(reset_second)
        and process._active_for_test(705) == nil
        and process._active_for_test(706) == nil,
    "reset left active building upgrades")
assert(#destroyed == 5 and #released == 5,
    "reset did not clean up all active upgrade particles")

print("BUILDING_UPGRADE_PROCESS_PASS")
