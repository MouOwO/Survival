local M = {}

M.particles = {
    gold_mine_efficiency = "particles/units/heroes/hero_omniknight/omniknight_purification.vpcf",
    gold_mine_crit = "particles/units/heroes/hero_phantom_assassin/phantom_assassin_crit_impact.vpcf",
}

function M.precache(context)
    for _, particle in pairs(M.particles) do
        PrecacheResource("particle", particle, context)
    end
end

function M.play(unit, group)
    local path = M.particles[group]
    if not path or not unit or unit:IsNull() or not unit:IsAlive()
        or not ParticleManager then return false end
    local manager = ParticleManager
    local particle = manager:CreateParticle(path, PATTACH_ABSORIGIN_FOLLOW, unit)
    local ok, err = pcall(function()
        manager:SetParticleControl(particle, 0, unit:GetAbsOrigin())
        if group == "gold_mine_efficiency" then
            manager:SetParticleControl(particle, 1, Vector(150, 150, 150))
        end
    end)
    if not ok then
        if type(particle) == "number" and particle >= 0
            and particle < math.huge and particle == math.floor(particle) then
            pcall(function() manager:DestroyParticle(particle, true) end)
            pcall(function() manager:ReleaseParticleIndex(particle) end)
        end
        error(err, 0)
    end
    -- These native impact effects are one-shots; leave their natural fade-out.
    manager:ReleaseParticleIndex(particle)
    return true
end

return M
