local M = {
    unit_name = "enemy_tree",
    spawn_point = { x = 500, y = 500, z = 128 },
    -- The tree is a permanent progression target. Each death advances one level.
    health = 1000,
    health_per_level = 10000,
    health_percent_per_level = 0,
    armor = 2,
    respawn_time = 0.1,
    -- No tree wood output: worker efficiency is base + tree buff.
    lumber_efficiency_buff_per_level = 1,
}

return M
