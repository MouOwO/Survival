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
