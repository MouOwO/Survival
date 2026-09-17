local shells = require("config/generated/building_white_shells")
local scheduler = require("core/scheduler")
local M = { reveal_seconds = 1.5, reveal_steps = 48 }
local active = {}
local next_id = 0

local function valid(entity)
    return entity and (not entity.IsNull or not entity:IsNull())
end

function M.model_for(unit)
    if not valid(unit) or not unit.GetModelName then return nil end
    return shells[unit:GetModelName()]
end

function M.is_handle(handle)
    return type(handle) == "table" and handle.white_shell_marker == M
end

function M.destroy(handle)
    if not M.is_handle(handle) or handle.destroyed then return end
    handle.destroyed = true
    active[handle.id] = nil
    if handle.task_id then scheduler.cancel(handle.task_id) end
    if valid(handle.entity) then
        if UTIL_Remove then pcall(UTIL_Remove, handle.entity)
        elseif handle.entity.RemoveSelf then pcall(handle.entity.RemoveSelf, handle.entity) end
    end
end

function M.create(unit, definition, duration, reveal)
    local model = M.model_for(unit)
    if not model or not SpawnEntityFromTableSynchronous then return nil end
    next_id = next_id + 1
    local handle = { white_shell_marker=M, id=next_id, unit=unit }
    local ok, err = pcall(function()
        local origin = unit:GetAbsOrigin()
        local level = tonumber(unit.survival_level) or 1
        local visual = ((definition or {}).levels or {})[level] or {}
        local scale = tonumber(visual.model_scale) or (unit.GetModelScale and unit:GetModelScale()) or 1
        local yaw = tonumber(visual.model_yaw)
        if yaw == nil then yaw = unit.GetAnglesAsVector and unit:GetAnglesAsVector().y or 0 end
        handle.entity = SpawnEntityFromTableSynchronous("prop_dynamic", {
            targetname="survival_build_white_"..handle.id,
            model=model, solid="0", disableshadows="1", rendermode="1", renderamt="255", rendercolor="255 255 255",
            origin=string.format("%f %f %f",origin.x,origin.y,origin.z),
            angles=string.format("0 %f 0",yaw),
        })
        assert(valid(handle.entity), "white shell spawn failed")
        -- Intentionally unparented: hiding the construction unit cannot hide
        -- this prop. Follow its world position explicitly, including Z.
        handle.entity:SetAbsOrigin(origin)
        handle.entity:SetAngles(0,yaw,0)
        handle.entity:SetModelScale(scale*1.006)
        handle.entity:SetRenderAlpha(255)
        local started = GameRules:GetGameTime()
        active[handle.id] = handle
        handle.task_id = scheduler.every(0.03, function()
            if handle.destroyed then return false end
            if not valid(unit) or not valid(handle.entity) or (unit.IsAlive and not unit:IsAlive()) then
                M.destroy(handle); return false
            end
            handle.entity:SetAbsOrigin(unit:GetAbsOrigin())
            local elapsed = GameRules:GetGameTime()-started
            if reveal then
                local t = math.min(1,math.max(0,elapsed/M.reveal_seconds))
                -- Height UVs and a feathered alpha mask reveal roof before
                -- walls. Color UV animation remains independent of the mask.
                -- Keep global alpha opaque: whole-model fading loses direction.
                local step = math.min(M.reveal_steps,math.floor(t*M.reveal_steps+0.5))
                if step > 0 and step ~= handle.reveal_step then
                    handle.entity:SetMaterialGroup(string.format("reveal_%02d",step))
                    handle.reveal_step=step
                end
                if t >= 1 then M.destroy(handle); return false end
            elseif elapsed > math.max(0.1,tonumber(duration) or 3)+5 then
                M.destroy(handle); return false
            end
            return true
        end,"building_white_shell_"..handle.id)
    end)
    if not ok then
        M.destroy(handle)
        print("[BuildingWhiteShell] create failed: "..tostring(err))
        return nil
    end
    return handle
end

function M.precache(context)
    local count=0
    for _,model in pairs(shells) do
        PrecacheResource("model",model,context); count=count+1
    end
    return count
end

function M.reset()
    local pending={}
    for _,handle in pairs(active) do pending[#pending+1]=handle end
    for _,handle in ipairs(pending) do M.destroy(handle) end
end

M._active_count_for_test=function()
    local count=0;for _ in pairs(active) do count=count+1 end;return count
end
return M
