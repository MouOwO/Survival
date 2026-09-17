local geometry = require("core/building_grid_geometry")
local grid_config = require("config/grid_placement_config")
local M = {}
local white_shell = require("systems/building_white_shell")

function M.is_white(path)
    return type(path)=="string" and path:find("particles/survival_buildings/white_build_",1,true)==1
end

function M.is_shell(handle) return white_shell.is_handle(handle) end
function M.reset_shells() white_shell.reset() end
function M.precache_shells(context) return white_shell.precache(context) end

function M.is_warp(path)
    return type(path) == "string" and (
        path:find("particles/survival_buildings/white_build_", 1, true) == 1
        or path:find("particles/survival_buildings/warp_", 1, true) == 1)
end

function M.parameters(definition, duration)
    local footprint = geometry.footprint(definition and definition.footprint)
    local radius = math.max(footprint.x, footprint.y) * (tonumber(grid_config.cell_size) or 64) * 0.5
    return Vector(radius, radius * 2, math.max(0.1, tonumber(duration) or 3))
end

-- CP3 supplies only the model to a native RenderModels particle. The
-- projection never creates an additional selectable/colliding game entity.
function M.configure(particle, unit, definition, duration)
    local parameters = M.parameters(definition, duration)
    local level = tonumber(unit.survival_level) or 1
    local visual = ((definition or {}).levels or {})[level] or {}
    local scale = tonumber(visual.model_scale)
    local yaw = tonumber(visual.model_yaw)
    -- Construction hides the entity before its final visual apply. Prefer
    -- the configured facing/scale so the projection already matches preview.
    if scale == nil and unit.GetModelScale then scale = tonumber(unit:GetModelScale()) end
    if yaw == nil and unit.GetAnglesAsVector then
        local angles = unit:GetAnglesAsVector()
        yaw = angles and tonumber(angles.y)
    end
    ParticleManager:SetParticleControl(particle, 1, parameters)
    -- C_INIT_InitFloat's yaw field takes degrees, like the entity's angles.
    ParticleManager:SetParticleControl(particle, 2, Vector(scale or 1, yaw or 0, 0))
    if ParticleManager.SetParticleControlEnt then
        ParticleManager:SetParticleControlEnt(particle, 3, unit,
            PATTACH_ABSORIGIN_FOLLOW, "", unit:GetAbsOrigin(), true)
    end
end

function M.destroy(particle)
    if white_shell.is_handle(particle) then white_shell.destroy(particle); return end
    if particle == nil or not ParticleManager then return end
    -- Avoid the native end-cap cleanup crash; completion has its own burst.
    pcall(function() ParticleManager:DestroyParticle(particle, true) end)
    pcall(function() ParticleManager:ReleaseParticleIndex(particle) end)
end

function M.create(path, unit, definition, duration, one_shot)
    if M.is_white(path) and white_shell.model_for(unit) then
        return white_shell.create(unit,definition,duration,one_shot==true)
    end
    if type(path) ~= "string" or path == "" or not ParticleManager
        or not unit or unit:IsNull() or not unit.GetAbsOrigin then return nil end
    local particle
    local ok, error_message = pcall(function()
        local origin = unit:GetAbsOrigin()
        if not origin then return end
        particle = ParticleManager:CreateParticle(path, PATTACH_WORLDORIGIN, unit)
        if particle == nil then return end
        ParticleManager:SetParticleControl(particle, 0, origin)
        if M.is_warp(path) then
            M.configure(particle, unit, definition, duration)
        elseif path == "particles/items2_fx/teleport_start.vpcf" then
            ParticleManager:SetParticleControl(particle, 7, Vector(math.max(0.1, tonumber(duration) or 3), 0, 0))
        end
    end)
    if not ok then
        M.destroy(particle)
        print("[BuildingWhiteEffect] particle initialization failed: "
            .. tostring(path) .. " error=" .. tostring(error_message))
        return nil
    end
    if particle ~= nil and one_shot then
        pcall(function() ParticleManager:ReleaseParticleIndex(particle) end)
    end
    return particle
end

return M
