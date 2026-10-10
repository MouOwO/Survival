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
    local particle = ParticleManager:CreateParticle(path, PATTACH_ABSORIGIN_FOLLOW, unit)
    ParticleManager:SetParticleControl(particle, 0, unit:GetAbsOrigin())
    if group == "gold_mine_efficiency" then
        ParticleManager:SetParticleControl(particle, 1, Vector(150, 150, 150))
    end
    -- These native impact effects are one-shots; leave their natural fade-out.
    ParticleManager:ReleaseParticleIndex(particle)
    return true
end

return M
