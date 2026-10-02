-- Native cosmetic bundles only; no orders, ability casts or damage here.
local config = require("config/generated/tower_lightning_effects")
local projection = require("systems/tower_rank_projection")
local M = {}

function M.chain_particle(unit, fallback)
    local rank = projection.project({building_id=unit.survival_building_id,
        level=unit.survival_level})
    local rarity = rank and rank.rarity
    if rarity == "UR" then rarity = "SSR" end
    local row = rarity and config.by_id[rarity]
    return row and row.enabled ~= false and row.particle_name or fallback
end

-- A released native one-shot keeps its complete ground tail after a kill.
-- Do not attach the root to the victim or schedule an early destruction.
local function one_shot(name, configure)
    local particle
    local ok = pcall(function()
        particle = ParticleManager:CreateParticle(name, PATTACH_WORLDORIGIN, nil)
        assert(type(particle) == "number" and particle >= 0, "invalid bolt particle")
        configure(particle)
    end)
    if type(particle) == "number" and particle >= 0 then
        if not ok then pcall(ParticleManager.DestroyParticle, ParticleManager, particle, true) end
        pcall(ParticleManager.ReleaseParticleIndex, ParticleManager, particle)
    end
    return ok
end

function M.bolt(caster, position, target)
    local row = config.by_id.hero_strike
    if not row or row.enabled == false or not position then return false end
    local ok = one_shot(row.particle_name, function(particle)
        local hit = Vector(position.x, position.y, position.z)
        -- CP1's entity is only used by the native model-electricity layers.
        -- ABSORIGIN samples once; FOLLOW would drag new ground sparks along.
        if target and not target:IsNull() and ParticleManager.SetParticleControlEnt then
            ParticleManager:SetParticleControlEnt(particle, 1, target,
                PATTACH_ABSORIGIN, "", hit, true)
        end
        ParticleManager:SetParticleControl(particle, 0, Vector(hit.x, hit.y, hit.z + 4000))
        ParticleManager:SetParticleControl(particle, 1, hit)
        ParticleManager:SetParticleControl(particle, 3, hit)
    end)
    if ok and row.cast_particle and row.cast_particle ~= "" then
        one_shot(row.cast_particle, function(particle)
            local origin = caster:GetAbsOrigin()
            ParticleManager:SetParticleControl(particle, 0, Vector(origin.x, origin.y, origin.z))
        end)
    end
    return ok
end

function M.precache(context)
    local seen = {}
    for _, row in ipairs(config.rows) do
        if row.enabled ~= false then
            for _, key in ipairs({"particle_name", "impact_particle", "cast_particle"}) do
                local name = row[key]
                if name and name ~= "" and not seen[name] then
                    seen[name] = true
                    PrecacheResource("particle", name, context)
                end
            end
        end
    end
end

return M
