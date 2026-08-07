local M = {}

local function valid_entity(entity)
    return entity ~= nil and (not entity.IsNull or not entity:IsNull())
end

function M.apply(state, player_id, multiplier)
    multiplier = tonumber(multiplier)
    if not state or not valid_entity(state.unit) or not state.unit:IsAlive() then
        return false, "wall_not_selected"
    end
    if state.building_id ~= "wall" then
        return false, "selected_unit_not_wall"
    end
    if tonumber(state.player_id) ~= tonumber(player_id) then
        return false, "wall_not_owned"
    end
    if not multiplier or multiplier < 0.25 or multiplier > 4 then
        return false, "scale_must_be_between_0.25_and_4"
    end
    local base_radius = tonumber(state.definition.hull_radius)
        or tonumber(state.unit.survival_base_hull_radius)
        or tonumber(state.unit.survival_hull_radius)
    if not base_radius or base_radius <= 0 then
        return false, "wall_base_hull_missing"
    end
    state.unit.survival_base_hull_radius = base_radius
    local radius = base_radius * multiplier
    local ok, error_message = pcall(state.unit.SetHullRadius, state.unit, radius)
    if not ok then
        return false, "wall_hull_apply_failed:" .. tostring(error_message)
    end
    state.unit.survival_hull_radius = radius
    state.unit.survival_hull_scale = multiplier
    return true, radius, base_radius
end

return M