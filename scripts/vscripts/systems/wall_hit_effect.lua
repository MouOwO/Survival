local M = {}
M.particle = "particles/units/heroes/hero_rattletrap/rattletrap_cog_attack_impact.vpcf"

function M.precache(context)
    PrecacheResource("particle", M.particle, context)
end

function M.play(wall, attacker)
    if not wall or wall:IsNull() or not attacker or attacker:IsNull() then return end
    local now=GameRules:GetGameTime()
    if now-(wall.survival_last_metal_hit or -100)<0.08 then return end
    wall.survival_last_metal_hit=now
    local origin,source=wall:GetAbsOrigin(),attacker:GetAbsOrigin()
    local dx,dy=source.x-origin.x,source.y-origin.y
    local length=math.max(math.abs(dx),math.abs(dy),1)
    -- Place the strike on the visible square face, not at the unit's center
    -- or the outside of its navigation shoulders.
    local point=Vector(origin.x+dx/length*124,origin.y+dy/length*124,origin.z+64)
    local manager=ParticleManager
    local index=manager:CreateParticle(M.particle,PATTACH_WORLDORIGIN,wall)
    local ok,err=pcall(function() manager:SetParticleControl(index,0,point) end)
    if not ok then
        if type(index)=="number" and index>=0
            and index<math.huge and index==math.floor(index) then
            pcall(function() manager:DestroyParticle(index,true) end)
            pcall(function() manager:ReleaseParticleIndex(index) end)
        end
        error(err,0)
    end
    manager:ReleaseParticleIndex(index)
end

return M
