-- Short, self-terminating layers from Valve's town-portal arrival effect.
-- The full portal includes channel loops and a hero image; instant return only
-- needs these two bursts. No attachment lookup, follow trail or Lua timer.
local logger = require("core/logger")
local M = {}
local particles = {
    "particles/items2_fx/teleport_end_flash.vpcf",
    "particles/items2_fx/teleport_end_ground_drop.vpcf",
}

function M.precache(context)
    for _, path in ipairs(particles) do
        PrecacheResource("particle", path, context)
    end
end

local function burst(hero, position)
    for _, path in ipairs(particles) do
        local particle
        local ok, reason = pcall(function()
            particle = ParticleManager:CreateParticle(path, PATTACH_WORLDORIGIN, hero)
            if particle == nil or particle == -1 then error("invalid particle ID") end
            ParticleManager:SetParticleControl(particle, 0, position)
            ParticleManager:SetParticleControl(particle, 1, position)
            -- Ground-drop's native CP2 uses a normalized RGB color.
            ParticleManager:SetParticleControl(particle, 2, Vector(0.55, 0.78, 1))
        end)
        if particle ~= nil and particle ~= -1 then
            if not ok then pcall(ParticleManager.DestroyParticle, ParticleManager, particle, true) end
            -- Native emit-once particles decay after 0.15/0.25 seconds. Release
            -- script ownership immediately; the engine retires the simulation.
            pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, particle)
        end
        if not ok then logger.warn("HeroReturnHome", "particle setup failed: " .. tostring(reason)) end
    end
end

function M.play(hero, origin, destination)
    if not ParticleManager then return end
    burst(hero, origin)
    burst(hero, destination)
end

return M
