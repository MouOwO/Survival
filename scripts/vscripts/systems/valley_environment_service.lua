-- Shared by the released map and its art review. No preview camera/game rules.
local scheduler = require("core/scheduler")
local M = {}
local particles = {}
local effect = "particles/imagine_assets/environments_fx/portal_fx/act2_portal.vpcf"

local function supported_map()
    local name = GetMapName()
    return name == "template_map" or name == "valley_decor_review"
end

function M.precache(context)
    if supported_map() then PrecacheResource("particle", effect, context) end
end

function M.clear()
    for _, id in ipairs(particles) do
        ParticleManager:DestroyParticle(id, true)
        ParticleManager:ReleaseParticleIndex(id)
    end
    particles = {}
end

function M.apply()
    if not supported_map() then return 0 end
    M.clear()
    for i = 1, 4 do
        local marker = Entities:FindByName(nil, "monsterborn_player" .. i)
        local old = Entities:FindByName(nil, "valley_decor_v1_fx_monsterborn_player" .. i)
        if old then DoEntFireByInstanceHandle(old, "Stop", "", 0, old, old) end
        if marker then
            local p = marker:GetAbsOrigin()
            p.z = GetGroundHeight(p, nil) + 12
            local id = ParticleManager:CreateParticle(effect, PATTACH_WORLDORIGIN, nil)
            for _, cp in ipairs({0, 1, 3}) do
                ParticleManager:SetParticleControl(id, cp,
                    p + Vector(0, 0, cp == 3 and 160 or 0))
                -- This imported sprite uses an unusual normal. Verified flat
                -- in Workshop; a normal yaw frame stands the ground rings up.
                ParticleManager:SetParticleControlOrientation(id, cp,
                    Vector(0, 1, 0), Vector(0, 0, 1), Vector(1, 0, 0))
            end
            particles[#particles + 1] = id
        end
    end
    print("VALLEY_REFERENCE_PORTALS", #particles)
    return #particles
end

function M.init()
    -- Indices from the preceding world must not destroy the new world's FX.
    particles = {}
    scheduler.after(0, function() M.apply() end, "valley_environment_initialise")
end

return M
