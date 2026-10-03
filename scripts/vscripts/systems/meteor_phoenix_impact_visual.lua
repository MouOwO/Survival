local scheduler = require("core/scheduler")
local M = {}

local SPEC = {
    particle = "particles/survival/skills/meteor_phoenix_impact.vpcf",
    maximum_radius = 500,
    -- All seventeen derived native layers are authored for exactly 500 units.
    -- Native scorch layers last seven seconds; keep a one-second cleanup margin.
    natural_tail_seconds = 7,
    duration_seconds = 8,
}
local visuals, sequence, revision, clear_depth = {}, 0, 0, 0

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function particle_id(value)
    return finite(value) and value >= 0 and value == math.floor(value)
end

local function world_token()
    local rules = rawget(_G, "GameRules")
    if rules and type(rules.GetGameModeEntity) == "function" then
        local ok, world = pcall(rules.GetGameModeEntity, rules)
        if ok and world ~= nil then return rules, world end
    end
    return rules, rules or _G
end

local function same_world(visual)
    local rules, world = world_token()
    return visual.rules == rules and visual.world == world
end

local function cancel_task(visual)
    local task = visual.task
    visual.task = nil
    if task ~= nil and same_world(visual) then pcall(scheduler.cancel, task) end
end

local function destroy(visual, immediate)
    local particle = visual.particle
    visual.particle = nil
    if not particle_id(particle) or not same_world(visual) then return true end
    local manager = visual.manager
    local ok_destroy, destroy_result = pcall(manager.DestroyParticle, manager, particle, immediate == true)
    -- Destroy can synchronously enter a fresh Tools world and reuse the ID.
    -- Release is independent of Destroy failure, but only in its original world.
    local ok_release, release_result = true, nil
    if same_world(visual) then
        ok_release, release_result = pcall(manager.ReleaseParticleIndex, manager, particle)
    end
    return ok_destroy and destroy_result ~= false and ok_release and release_result ~= false
end

function M.release(visual_id, immediate)
    local visual = visuals[visual_id]
    if not visual then return true, "unchanged" end
    -- Reentrant native callbacks must observe that ownership was already revoked.
    visuals[visual_id] = nil
    cancel_task(visual)
    return destroy(visual, immediate), "released"
end

function M.clear()
    clear_depth = clear_depth + 1
    revision = revision + 1
    local pending = {}
    for id in pairs(visuals) do pending[#pending + 1] = id end
    for _, id in ipairs(pending) do M.release(id, true) end
    clear_depth = clear_depth - 1
    return true
end

function M.duration()
    return SPEC.duration_seconds
end

function M.active()
    return visuals
end

function M.spec()
    return {
        particle = SPEC.particle, maximum_radius = SPEC.maximum_radius,
        fixed_radius = SPEC.maximum_radius, control_point_1 = { 1, 1, 1 },
        control_point_3_offset = { 0, 0, 100 },
        natural_tail_seconds = SPEC.natural_tail_seconds,
        duration_seconds = SPEC.duration_seconds,
    }
end

function M.impact(position, owner, radius)
    if clear_depth > 0 then return nil, "visuals_clearing" end
    local wanted_radius = radius == nil and SPEC.maximum_radius or tonumber(radius)
    if not finite(wanted_radius) or wanted_radius ~= SPEC.maximum_radius then
        return nil, "impact_requires_authored_radius_500"
    end
    local vector, manager = rawget(_G, "Vector"), rawget(_G, "ParticleManager")
    if type(vector) ~= "function" or not manager then return nil, "particle_apis_unavailable" end
    for _, name in ipairs({ "CreateParticle", "SetParticleControl", "DestroyParticle", "ReleaseParticleIndex" }) do
        if type(manager[name]) ~= "function" then return nil, "missing_native_method_" .. name end
    end
    local attachment = rawget(_G, "PATTACH_WORLDORIGIN")
    if not particle_id(attachment) then return nil, "world_attachment_unavailable" end

    local rules, world = world_token()
    local visual = { rules = rules, world = world, revision = revision, manager = manager,
        radius = wanted_radius, particle = nil, task = nil }
    local function active()
        return clear_depth == 0 and visual.revision == revision and same_world(visual)
    end
    local function invoke(name, ...)
        assert(active(), "visual state changed before " .. name)
        local ok, result = pcall(manager[name], manager, ...)
        if not ok or result == false then error(name .. ": " .. tostring(result)) end
        assert(active(), "visual state changed during " .. name)
        return result
    end
    local allocated, failure = pcall(function()
        assert(position ~= nil and finite(position.x) and finite(position.y) and finite(position.z),
            "invalid impact position")
        visual.position = vector(position.x, position.y, position.z)
        assert(visual.position ~= nil, "impact position snapshot unavailable")
        assert(active(), "visual state changed before allocation")
        -- Capture the returned ID before checking the guard, so same-world
        -- reset during allocation can retire its temporary handle.
        local ok, id = pcall(manager.CreateParticle, manager, SPEC.particle, attachment, owner)
        visual.particle = id
        assert(ok and particle_id(id), "invalid particle allocation: " .. tostring(id))
        assert(active(), "visual state changed during allocation")
        invoke("SetParticleControl", id, 0, visual.position)
        -- CP1 is the native mixed-control convention, not a radius channel.
        -- The 500-unit footprint is authored in every derived native layer.
        invoke("SetParticleControl", id, 1, vector(1, 1, 1))
        -- Native shockwave normals read CP3. Its derived layers leave this
        -- world point to Lua, so impacts far from map origin remain upright.
        invoke("SetParticleControl", id, 3, vector(
            visual.position.x, visual.position.y, visual.position.z + 100
        ))
    end)
    if not allocated then
        destroy(visual, true)
        return nil, tostring(failure)
    end

    sequence = sequence + 1
    local visual_id = sequence
    visual.id = visual_id
    visuals[visual_id] = visual
    local scheduled, task = pcall(scheduler.after, SPEC.duration_seconds, function()
        if visuals[visual_id] == visual then M.release(visual_id, false) end
    end, "hero_meteor_phoenix_impact_" .. tostring(visual_id))
    visual.task = task
    if not scheduled or task == nil or task == false or not active() or visuals[visual_id] ~= visual then
        if visuals[visual_id] == visual then visuals[visual_id] = nil end
        cancel_task(visual)
        destroy(visual, true)
        return nil, "impact_cleanup_schedule_failed: " .. tostring(task)
    end
    return visual_id
end

return M
