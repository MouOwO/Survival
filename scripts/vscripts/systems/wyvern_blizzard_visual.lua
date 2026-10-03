-- Freezing Field frost + swirling snow, without native ability gameplay.
local M = {}
local active = {}
local scheduler = require("core/scheduler")
M.GROUND = "particles/survival/skills/blizzard_ground.vpcf"
M.SNOW = "particles/survival/skills/wyvern_blizzard_snow.vpcf"
local function world()
    return GameRules.GetGameModeEntity and GameRules:GetGameModeEntity() or GameRules
end

function M.finish(entry, immediate)
    if not entry or not active[entry] then return end
    active[entry] = nil
    if entry.world ~= world() then return end
    for _, particle in ipairs(entry.particles) do
        pcall(ParticleManager.DestroyParticle, ParticleManager, particle, immediate == true)
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, particle)
    end
end

function M.play(position, radius, ground, snow, duration)
    local entry = {world = world(), particles = {}}
    active[entry] = true
    local ok, err = pcall(function()
        if GetGroundPosition then position = GetGroundPosition(position, nil) end
        for index, name in ipairs({ground or M.GROUND, snow or M.SNOW}) do
            -- Snapshot the area, independent of the trigger target or tower model.
            local particle = ParticleManager:CreateParticle(name, PATTACH_WORLDORIGIN, nil)
            assert(type(particle) == "number" and particle >= 0, "invalid blizzard particle")
            entry.particles[#entry.particles + 1] = particle
            ParticleManager:SetParticleControl(particle, 0, position)
            if index == 1 then
                ParticleManager:SetParticleControl(particle, 2, Vector(radius, radius, 0))
            else
                ParticleManager:SetParticleControl(particle, 1, Vector(radius, radius, 0))
            end
        end
    end)
    if not ok then
        M.finish(entry, true)
        print("[WyvernBlizzardVisual] optional visual failed: " .. tostring(err))
        return nil
    end
    scheduler.after(math.max(0.1, tonumber(duration) or 5), function() M.finish(entry, false) end)
    return entry
end

function M.clear()
    local entries = {}
    for entry in pairs(active) do entries[#entries + 1] = entry end
    for _, entry in ipairs(entries) do M.finish(entry, true) end
end
return M
