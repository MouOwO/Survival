local M = {}

M.zombie_basic = {
    id = "zombie_basic",
    unit_name = "zombie_basic",
    health = 200,
    health_regen = 0,
    damage_min = 10,
    damage_max = 15,
    armor = 1,
    magic_resistance = 0,
    move_speed = 250,
    attack_range = 128,
    attack_rate = 1.0,
    attack_animation_point = 0.4,
    acquisition_range = 0,
    day_vision = 500,
    night_vision = 500,
    model_scale = 0.8,
    bounty_gold = 5,
    bounty_wood = 3,
    wave_growth = {
        health_per_wave = 30,
        damage_per_wave = 2,
        armor_per_wave = 0.5,
        move_speed_per_wave = 1,
    },
}

M.zombie_boss = {
    id = "zombie_boss",
    unit_name = "zombie_boss",
    health = 2000,
    health_regen = 5,
    damage_min = 50,
    damage_max = 70,
    armor = 10,
    magic_resistance = 25,
    move_speed = 200,
    attack_range = 200,
    attack_rate = 1.5,
    attack_animation_point = 0.5,
    acquisition_range = 0,
    day_vision = 800,
    night_vision = 800,
    model_scale = 1.5,
    bounty_gold = 50,
    bounty_wood = 30,
    wave_growth = {
        health_per_wave = 200,
        damage_per_wave = 8,
        armor_per_wave = 1,
        move_speed_per_wave = 0,
    },
}

return M
