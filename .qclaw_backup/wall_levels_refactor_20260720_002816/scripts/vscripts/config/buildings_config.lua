local M = {}

M.wall = {
    id = "wall", display_name = "城墙", unit_name = "building_wall",
    build_cost = { wood = 30, gold = 0 }, footprint = { x = 1, y = 1 },
    max_count = 1, build_once = true, show_health_bar = true, selectable = true,
    abilities = { "ability_upgrade_wall" }, levels = {},
}
for level = 1, 15 do
    local tier = math.floor((level - 1) / 5) + 1
    local tier_level = ((level - 1) % 5) + 1
    local tier_base_hp = 2000 + (tier - 1) * 5000
    local tier_base_armor = 5 + (tier - 1) * 5
    local tier_cost = ({ 20, 40, 80 })[tier]
    M.wall.levels[level] = {
        level = level, display_level = string.format("%d-%d", tier, tier_level),
        health = tier_base_hp + (tier_level - 1) * 1000,
        armor = tier_base_armor + (tier_level - 1),
        upgrade_cost = level > 1 and { wood = tier_cost, gold = 0 } or nil,
    }
end

M.main_city = {
    id = "main_city", display_name = "主城", unit_name = "building_main_city",
    build_cost = { wood = 100, gold = 50 }, footprint = { x = 2, y = 2 },
    max_count = 1, show_health_bar = false, selectable = true,
    abilities = { "ability_upgrade_city", "ability_train_lumberjack" },
    levels = {
        [1] = { health = 5000, armor = 10, add_population = 10 },
        [2] = { health = 7000, armor = 12, add_population = 5, upgrade_cost = { wood = 200, gold = 100 } },
        [3] = { health = 9000, armor = 14, add_population = 5, upgrade_cost = { wood = 400, gold = 200 } },
        [4] = { health = 11000, armor = 16, add_population = 10, upgrade_cost = { wood = 600, gold = 300 } },
        [5] = { health = 13000, armor = 18, add_population = 10, upgrade_cost = { wood = 800, gold = 400 } },
        [6] = { health = 15000, armor = 20, add_population = 10, upgrade_cost = { wood = 1200, gold = 600 } },
        [7] = { health = 17000, armor = 22, add_population = 15, upgrade_cost = { wood = 1600, gold = 800 } },
        [8] = { health = 19000, armor = 24, add_population = 15, upgrade_cost = { wood = 2000, gold = 1000 } },
    },
}

M.arrow_tower = {
    id = "arrow_tower", display_name = "防御塔", unit_name = "building_arrow_tower",
    build_cost = { wood = 80, gold = 20 }, footprint = { x = 1, y = 1 }, max_count = 0,
    show_health_bar = false, selectable = true, abilities = { "ability_upgrade_tower" },
    pre_class_levels = {
        [1] = { health = 1500, armor = 5, damage = 172, attack_range = 600, attack_rate = 1.0, upgrade_cost = { wood = 50, gold = 0 } },
        [2] = { health = 2000, armor = 6, damage = 251, attack_range = 600, attack_rate = 1.0, upgrade_cost = { wood = 100, gold = 0 } },
        [3] = { health = 2500, armor = 7, damage = 301, attack_range = 625, attack_rate = 1.0, upgrade_cost = { wood = 200, gold = 0 } },
        [4] = { health = 3000, armor = 8, damage = 401, attack_range = 650, attack_rate = 0.95, upgrade_cost = { wood = 250, gold = 0 } },
        [5] = { health = 3500, armor = 9, damage = 501, attack_range = 675, attack_rate = 0.9, upgrade_cost = { wood = 300, gold = 0 } },
    },
    class_change_cost = { wood = 100, gold = 50 },
    class_options = {
        [1] = { id = "class_1", display_name = "【N】死亡之塔", ability = "ability_tower_class_1" },
        [2] = { id = "class_2", display_name = "【N】神秘之塔", ability = "ability_tower_class_2" },
        [3] = { id = "class_3", display_name = "【N】闪电塔", ability = "ability_tower_class_3" },
        [4] = { id = "class_4", display_name = "【N】机枪塔", ability = "ability_tower_class_4" },
        [5] = { id = "class_5", display_name = "【N】多重塔", ability = "ability_tower_class_5" },
        [6] = { id = "class_6", display_name = "【N】冰霜之塔", ability = "ability_tower_class_6" },
        [7] = { id = "class_7", display_name = "【N】防空炮", ability = "ability_tower_class_7" },
    },
}

M.gold_mine = { id = "gold_mine", display_name = "金矿", unit_name = "building_gold_mine", build_cost = { wood = 300, gold = 100 }, footprint = { x = 2, y = 2 }, max_count = 1, unlock_city_level = 3, show_health_bar = true, selectable = true, abilities = { "ability_upgrade_gold_mine", "ability_upgrade_gold_mine_crit" }, levels = { [1] = { health = 3000, armor = 8 } } }
M.hero_altar = { id = "hero_altar", display_name = "英雄祭坛", unit_name = "building_hero_altar", build_cost = { wood = 300, gold = 100 }, footprint = { x = 2, y = 2 }, max_count = 1, unlock_city_level = 3, show_health_bar = false, selectable = true, abilities = { "ability_summon_axe", "ability_summon_slark", "ability_summon_juggernaut", "ability_summon_monkey_king", "ability_summon_blademaster" }, levels = { [1] = { health = 2500, armor = 8 } } }
return M
