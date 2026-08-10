local M = {}

function M.profile(row, definition)
    row = row or {}
    definition = definition or {}
    local movement_type = row.movement_type_override
        or definition.movement_type
        or "ground"
    local flying = movement_type == "flying"
    local base_hull_radius = 29

    if flying or row.member_role == "assault_boss"
        or definition.rank == "boss" or row.is_boss == true then
        base_hull_radius = 0
    elseif definition.rank == "elite" or row.member_role == "wave_leader" then
        base_hull_radius = 58
    end

    return {
        movement_type = movement_type,
        base_hull_radius = base_hull_radius,
        no_unit_collision = flying,
    }
end

return M