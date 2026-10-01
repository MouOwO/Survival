-- Cosmetic selection follows displayed tower rarity, never inherited skill level
-- or the legacy rarity column in the route CSV.
local effects = require("config/generated/tower_laser_effects")
local projection = require("systems/tower_rank_projection")
local M = {}

function M.width(unit, skill, effect, state)
    local rank = projection.project(state or {
        building_id = unit and unit.survival_building_id,
        level = unit and unit.survival_level,
    })
    if rank and rank.rarity == "UR" then return 2.9 end
    local id = type(skill) == "table" and skill.skill_id or skill
    local stage_level = rank and (rank.stars + rank.red_stars)
        or tonumber(tostring(id):match("lv(%d+)$")) or 1
    return math.min(2.9, (tonumber(effect.width_base) or 1)
        + (math.max(1, stage_level) - 1) * (tonumber(effect.width_step) or 0.1))
end

function M.get(unit, skill, state)
    local id = type(skill) == "table" and skill.skill_id or skill
    if type(id) ~= "string" or id == "" then return nil end
    local rank = projection.project(state or {
        building_id = unit and unit.survival_building_id,
        level = unit and unit.survival_level,
    })
    local rarity = rank and rank.rarity
    -- Ultimate fusion retains the highest existing laser presentation.
    if rarity == "UR" then rarity = "SSR" end
    local by_id = effects.by_id or {}
    local row = rarity and by_id[id .. ":" .. rarity] or nil
    local asset_id = unit and unit.survival_model_asset_id
    row = row or (asset_id and by_id[id .. ":" .. asset_id])
        or by_id[id .. ":default"] or by_id[id]
    return row and row.enabled ~= false and row or nil
end

return M
