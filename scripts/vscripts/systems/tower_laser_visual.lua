-- Cosmetic only. CP1 is sampled at the head surface; CP2 carries tier RGB.
local M = {}
local prefix = "particles/survival/towers/"

function M.clear_pose(owner)
    local pose = owner.laser_pose
    owner.laser_pose = nil
    if pose then pcall(function() if not pose:IsNull() then pose:Destroy() end end) end
end

function M.sync_pose(owner, effect)
    if not effect or effect.source_orb ~= true then M.clear_pose(owner); return end
    local unit = owner:GetParent()
    if not unit or unit:IsNull() or not unit:IsAlive() then M.clear_pose(owner); return end
    if owner.laser_pose and not owner.laser_pose:IsNull() then return end
    local now = GameRules:GetGameTime()
    if now < (owner.laser_pose_retry or 0) then return end
    owner.laser_pose_retry = now + 0.5
    if unit.AddNewModifier then
        local ok, pose = pcall(unit.AddNewModifier, unit, unit, nil, "modifier_tower_laser_pose", {})
        if ok then owner.laser_pose = pose end
    end
end

function M.color(effect)
    return Vector(tonumber(effect.color_r) or 210, tonumber(effect.color_g) or 240,
        tonumber(effect.color_b) or 255)
end

function M.head_position(caster, target, effect)
    local origin = target:GetAbsOrigin()
    local point
    if target.ScriptLookupAttachment and target.GetAttachmentOrigin then
        for _, name in ipairs({ "attach_head", "head", "attach_eye", "attach_eyes" }) do
            local ok, id = pcall(target.ScriptLookupAttachment, target, name)
            if ok and tonumber(id) and id > 0 then
                local found, position = pcall(target.GetAttachmentOrigin, target, id)
                if found and position then point = position; break end
            end
        end
    end
    if not point then
        local height = tonumber(effect.target_offset_z) or 70
        if target.GetBoundingMaxs then
            local ok, bounds = pcall(target.GetBoundingMaxs, target)
            if ok and bounds then height = math.max(24, bounds.z * 0.88) end
        end
        point = origin + Vector(0, 0, height)
    end
    local delta = caster:GetAbsOrigin() - origin
    local distance = delta:Length2D()
    local radius = 12
    if target.GetHullRadius then
        local ok, hull = pcall(target.GetHullRadius, target)
        if ok then radius = math.max(6, math.min(28, (tonumber(hull) or 24) * 0.5)) end
    end
    if distance > 0.01 then
        point = point + Vector(delta.x / distance * radius, delta.y / distance * radius, 0)
    end
    return point
end

function M.blood_strength(damage)
    -- Logarithmic response remains legible across late-game damage magnitudes.
    return math.max(1, math.min(4, 1 + math.log(1 + math.max(0, damage) / 800) / math.log(10)))
end

function M.afterglow(segment)
    if not segment.afterglow or not segment.source_position or not segment.target_position then return end
    -- Consume before native calls, so repeated/reentrant death notifications
    -- cannot emit two tails. No dead entity, retained Lua handle or timer.
    segment.afterglow = false
    local id
    local ok, err = pcall(function()
        id = ParticleManager:CreateParticle(prefix .. "laser_afterglow.vpcf", PATTACH_WORLDORIGIN, nil)
        assert(type(id) == "number" and id >= 0, "invalid laser afterglow")
        ParticleManager:SetParticleControl(id, 0, segment.source_position)
        ParticleManager:SetParticleControl(id, 9, segment.source_position)
        ParticleManager:SetParticleControl(id, 1, segment.target_position)
        ParticleManager:SetParticleControl(id, 2, segment.color)
    end)
    if type(id) == "number" and id >= 0 then
        if not ok then pcall(ParticleManager.DestroyParticle, ParticleManager, id, true) end
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, id)
    end
    return ok, err
end

function M.hit(caster, position, result)
    if type(result) ~= "table" or result.success ~= true then return end
    local damage = tonumber(result.final_damage) or tonumber(result.engine_damage) or 0
    if damage <= 0 then return end
    local id
    local ok, err = pcall(function()
        id = ParticleManager:CreateParticle(prefix .. "laser_blood.vpcf", PATTACH_WORLDORIGIN, caster)
        assert(type(id) == "number" and id >= 0, "invalid blood particle")
        ParticleManager:SetParticleControl(id, 0, position)
        ParticleManager:SetParticleControl(id, 1, Vector(M.blood_strength(damage), 0, 0))
    end)
    if type(id) == "number" and id >= 0 then
        if not ok then pcall(ParticleManager.DestroyParticle, ParticleManager, id, true) end
        -- Finite burst: engine owns decay after the caller releases its handle.
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, id)
    end
    return ok, err
end

return M
