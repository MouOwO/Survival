local M = {}
local global_rules = require("config/global_rules")

function M.profile(row, definition, is_wave)
    row = row or {}
    definition = definition or {}
    local movement_type = row.movement_type_override
        or definition.movement_type
        or "ground"
    local flying = movement_type == "flying"
    -- Every caller that attaches wall AI must enter with the same solid body,
    -- including single challenge bosses and visually flying monsters. Reward
    -- and lifetime metadata must never make an attacker pass through a living
    -- front row. Practice rooms and independent encounter NPCs keep their own
    -- smaller, non-wall collision profiles.
    local wall_attacker = is_wave == true or definition.endless == true
        or row.is_challenge_monster == true
    local base_hull_radius = global_rules.wave_ground_monster_hull_radius
    local collision_profile = row.collision_profile

    if flying and not wall_attacker then
        base_hull_radius = 10
    end

    if collision_profile == "practice" and not wall_attacker then
        base_hull_radius = global_rules.practice_monster_hull_radius
    end

    return {
        movement_type = movement_type,
        base_hull_radius = base_hull_radius,
        no_unit_collision = false,
        apply_before_placement = collision_profile == "practice",
    }
end

return M
