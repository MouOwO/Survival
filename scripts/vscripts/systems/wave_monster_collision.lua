local M = {}

function M.profile(row, definition)
    row = row or {}
    definition = definition or {}
    local movement_type = row.movement_type_override
        or definition.movement_type
        or "ground"
    local flying = movement_type == "flying"
    local role = tostring(row.member_role or "")
    local normal_flying = flying and (role == "" or role == "normal")
    local base_hull_radius = 29

    if normal_flying then
        base_hull_radius = 10
    elseif flying then
        base_hull_radius = 0
    end

    return {
        movement_type = movement_type,
        base_hull_radius = base_hull_radius,
        no_unit_collision = flying and not normal_flying,
    }
end

return M