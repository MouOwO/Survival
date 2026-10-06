local M = {}

-- Use the base hero effect, independent of equipped cosmetic level-up effects.
M.particle = "particles/generic_hero_status/hero_levelup.vpcf"

function M.precache(context)
    PrecacheResource("particle", M.particle, context)
end

function M.play(unit)
    if not unit or unit:IsNull() or not unit:IsAlive() or not ParticleManager then
        return false
    end
    local particle = ParticleManager:CreateParticle(
        M.particle, PATTACH_ABSORIGIN_FOLLOW, unit)
    ParticleManager:SetParticleControl(particle, 0, unit:GetAbsOrigin())
    -- One-shot children finish naturally; release our handle immediately.
    ParticleManager:ReleaseParticleIndex(particle)
    return true
end

return M
