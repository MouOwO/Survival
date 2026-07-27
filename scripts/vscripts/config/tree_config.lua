local armor_balance = require("config/armor_balance")

local M = {
    unit_name = "enemy_tree",
    spawn_offset = { x = 520, y = 0, z = 0 },
    -- The tree is a permanent progression target. Each death advances one level.
    health = 1000,
    health_per_level = 10000,
    health_percent_per_level = 0,
    war3_armor = 100,
    armor = armor_balance.from_war3(100),
    minimum_war3_armor = 100,
    minimum_armor = armor_balance.from_war3(100),
    respawn_time = 0.1,
    -- No tree wood output: attacker efficiency is base + tree buff.
    lumber_efficiency_buff_per_level = 1,
    hero_base_lumber_efficiency = 13,
}

return M
