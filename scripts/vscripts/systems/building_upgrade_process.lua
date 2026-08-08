local scheduler = require("core/scheduler")
local asset_preload = require("systems/asset_preload_service")

local M = {}
local active_by_entindex = {}
local next_generation = 0
local KEEN_TELEPORT_PARTICLE = "particles/items2_fx/teleport_start.vpcf"

local function valid_entity(unit)
    return unit and not unit:IsNull()
end

local function safe_callback(callback, ...)
    if type(callback) ~= "function" then return true end
    local ok, error_message = pcall(callback, ...)
    if not ok then
        print("[BuildingUpgradeProcess] callback failed: "
            .. tostring(error_message))
    end
    return ok
end

local function destroy_particle(state)
    if state.particle_id == nil then return end
    if ParticleManager then
        pcall(function()
            ParticleManager:DestroyParticle(state.particle_id, false)
            ParticleManager:ReleaseParticleIndex(state.particle_id)
        end)
    end
    state.particle_id = nil
end

local function clear_unit_state(state)
    local unit = state.unit
    if not valid_entity(unit) then return end
    unit.survival_upgrade_in_progress = nil
    unit.survival_upgrade_target_level = nil
    unit.survival_upgrade_target_model_asset_id = nil
    unit.survival_upgrade_target_model_name = nil
end

local function remove_state(state)
    if active_by_entindex[state.entindex] == state then
        active_by_entindex[state.entindex] = nil
    end
    if state.task_id then scheduler.cancel(state.task_id) end
    state.task_id = nil
    destroy_particle(state)
    clear_unit_state(state)
end

local function cancel_state(state, reason)
    if not state or state.finished then return false end
    state.finished = true
    remove_state(state)
    safe_callback(state.options.on_cancel, reason or "cancelled")
    return true
end

local function complete_state(state)
    if not state or state.finished
        or active_by_entindex[state.entindex] ~= state then return end
    if not valid_entity(state.unit) or not state.unit:IsAlive() then
        cancel_state(state, "building_invalid")
        return
    end
    state.finished = true
    remove_state(state)
    safe_callback(state.options.on_complete)
end

local function particle_origin(unit)
    if not valid_entity(unit) or type(unit.GetAbsOrigin) ~= "function" then
        return nil
    end
    local ok, origin = pcall(unit.GetAbsOrigin, unit)
    if ok then return origin end
    return nil
end

local function start_particle(state)
    local path = state.options.particle
    if type(path) ~= "string" or path == "" or not ParticleManager then return end
    local origin = particle_origin(state.unit)
    if not origin then return end

    local particle_id = nil
    local ok = pcall(function()
        particle_id = ParticleManager:CreateParticle(
            path,
            PATTACH_WORLDORIGIN,
            state.unit
        )
        ParticleManager:SetParticleControl(particle_id, 0, origin)
        if path == KEEN_TELEPORT_PARTICLE then
            ParticleManager:SetParticleControl(
                particle_id,
                7,
                Vector(math.max(0.1, state.duration), 0, 0)
            )
        end
    end)
    if ok and particle_id ~= nil then
        state.particle_id = particle_id
    elseif particle_id ~= nil then
        pcall(function()
            ParticleManager:DestroyParticle(particle_id, true)
            ParticleManager:ReleaseParticleIndex(particle_id)
        end)
    end
end

local function queue_target_visual(state)
    local asset_id = state.options.target_model_asset_id
    if type(asset_id) ~= "string" or asset_id == "" then
        safe_callback(state.options.on_visual_status, "not_required")
        return
    end
    local queued, status = asset_preload.queue(asset_id, {
        urgent = true,
        priority = 2000,
        on_ready = function()
            if not state.finished then
                safe_callback(state.options.on_visual_status, "ready")
            end
        end,
        on_failed = function()
            if not state.finished then
                safe_callback(state.options.on_visual_status, "failed")
            end
        end,
    })
    safe_callback(
        state.options.on_visual_status,
        queued and (status or "queued") or (status or "queue_failed")
    )
end

function M.begin(unit, options)
    options = options or {}
    if not valid_entity(unit) or not unit:IsAlive() then
        return { ok = false, error = "building_invalid" }
    end
    local entindex = unit:entindex()
    if active_by_entindex[entindex] then
        return { ok = false, error = "upgrade_in_progress" }
    end

    next_generation = next_generation + 1
    local state = {
        unit = unit,
        entindex = entindex,
        options = options,
        duration = math.max(0, tonumber(options.duration) or 0),
        finished = false,
    }
    active_by_entindex[entindex] = state
    unit.survival_upgrade_in_progress = true
    unit.survival_upgrade_target_level = tonumber(options.target_level)
    unit.survival_upgrade_target_model_asset_id = options.target_model_asset_id
    unit.survival_upgrade_target_model_name = options.target_model_name

    start_particle(state)
    safe_callback(options.on_start)
    queue_target_visual(state)

    state.task_id = scheduler.after(state.duration, function()
        complete_state(state)
    end, "building_upgrade_" .. tostring(entindex)
        .. "_" .. tostring(next_generation))
    return {
        ok = true,
        pending = true,
        entindex = entindex,
        target_level = unit.survival_upgrade_target_level,
        duration = state.duration,
    }
end

function M.is_active(unit)
    if not valid_entity(unit) then return false end
    return active_by_entindex[unit:entindex()] ~= nil
end

function M.cancel_by_entindex(entindex, reason)
    return cancel_state(active_by_entindex[tonumber(entindex)], reason)
end

function M.reset()
    local pending = {}
    for _, state in pairs(active_by_entindex) do
        pending[#pending + 1] = state
    end
    for _, state in ipairs(pending) do
        cancel_state(state, "reset")
    end
    active_by_entindex = {}
end

M._active_for_test = function(entindex)
    return active_by_entindex[tonumber(entindex)]
end

return M
