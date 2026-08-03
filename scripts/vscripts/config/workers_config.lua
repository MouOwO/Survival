local armor_balance = require("config/armor_balance")

local M = {
    unit_name = "npc_survival_lumberjack",
    cost = { wood = 50, gold = 20, population = 1 },
    health = 300,
    armor = armor_balance.from_war3(1),
    damage_min = 15,
    damage_max = 15,
    attack_rate = 0.5,
    move_speed = 300,
    wood_per_hit = 1,
    max_count = 0,

    -- Spawn on a ring outside the main-city collision hull. The main city keeps
    -- its normal collision; no undocumented KV collision flag is required.
    spawn_radius_min = 420,
    spawn_radius_max = 640,
    spawn_attempts = 24,
    spawn_clearance = 160,
    nearby_unit_clearance = 128,
}

return M
