local M = {
    challenge_id = "challenge_07",
    encounter_id = "encounter_challenge_07",
    content_id = "material_molten_core_01",
    max_alive = 10,
    respawn_seconds = 0.5,
    drop_chance_pct = 20,
}

function M.roll(random_float)
    local roll = random_float(0, 100)
    return roll < M.drop_chance_pct, roll
end

return M