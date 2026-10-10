-- Cosmetic selection follows displayed tower rarity, never inherited skill level
-- or the legacy rarity column in the route CSV.
local effects = require("config/generated/tower_laser_effects")
local projection = require("systems/tower_rank_projection")
local M = {}

function M.width(unit, skill, effect, state)
    -- Native width at every star/rank; rarity is expressed by art and color.
    return 1
end

function M.get(unit, skill, state)
    local id = type(skill) == "table" and skill.skill_id or skill
    if type(id) ~= "string" or id == "" then return nil end
    local rarity = projection.rarity(state and state.building_id or unit and unit.survival_building_id,
        state and (state.absolute_level or state.level) or unit and unit.survival_level)
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
