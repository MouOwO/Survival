-- Native Blinding Light: CP1 is the burst center, CP2.x is its world radius.
local M = {}
M.PARTICLE = "particles/units/heroes/hero_keeper_of_the_light/keeper_of_the_light_blinding_light_aoe.vpcf"

function M.play(position, radius)
    if not position or not ParticleManager then return false end
    local ok, particle = pcall(ParticleManager.CreateParticle,
        ParticleManager, M.PARTICLE, PATTACH_WORLDORIGIN, nil)
    if not ok or particle == nil then return false end
    local configured = pcall(function()
        local center = Vector(position.x, position.y, position.z)
        ParticleManager:SetParticleControl(particle, 0, center)
        ParticleManager:SetParticleControl(particle, 1, center)
        ParticleManager:SetParticleControl(particle, 2, Vector(radius, 0, 0))
    end)
    if not configured then
        pcall(ParticleManager.DestroyParticle, ParticleManager, particle, true)
    end
    -- The native finite burst retains its impact even if damage kills the target.
    pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, particle)
    return configured
end

function M.precache(context)
    PrecacheResource("particle", M.PARTICLE, context)
end

return M
