local M = {}
local global_rules = require("config/global_rules")

function M.profile(row, definition, is_wave)
    row = row or {}
    definition = definition or {}
    local movement_type = row.movement_type_override
        or definition.movement_type
        or "ground"
    local flying = movement_type == "flying"
    -- Endless enemies keep challenge rewards/lifetime, but use the same
    -- physical queue and four wall contacts as formal wave enemies.
    local wave_collision = is_wave == true or definition.endless == true
    local base_hull_radius = global_rules.wave_ground_monster_hull_radius
    local collision_profile = row.collision_profile

    if flying and not wave_collision then
        base_hull_radius = 10
    end

    if collision_profile == "practice" then
        base_hull_radius = global_rules.practice_monster_hull_radius
    end

    local challenge_monster = row.is_challenge_monster == true and not wave_collision
    if challenge_monster then
        base_hull_radius = global_rules.building_challenge_hull_radius
    end

    return {
        movement_type = movement_type,
        base_hull_radius = base_hull_radius,
        -- Formal/endless waves need real unit collision so the wall approach
        -- cannot collapse into a stack. Other challenges keep their policy.
        no_unit_collision = challenge_monster,
        apply_before_placement = collision_profile == "practice",
    }
end

return M
