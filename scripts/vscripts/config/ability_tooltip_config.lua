local M = {
    ability_build_wall = {
        abilityid = "ability_build_wall",
        abilityname = "建造城墙",
        abilitydesc = "在指定位置建造城墙。城墙整局只能建造一次，且可以被选中并继续升级。",
        abilityicon = "tusk_ice_shards",
    },
    ability_build_main_city = {
        abilityid = "ability_build_main_city",
        abilityname = "建造主城",
        abilitydesc = "建造主城。主城拥有升级和训练伐木工两个技能。",
        abilityicon = "keeper_of_the_light_will_o_wisp",
    },
    ability_build_arrow_tower = {
        abilityid = "ability_build_arrow_tower",
        abilityname = "建造防御塔",
        abilitydesc = "建造可自动攻击敌人的防御塔。防御塔5级后可以选择一个转职方向。",
        abilityicon = "drow_ranger_marksmanship",
    },
    ability_upgrade_wall = {
        abilityid = "ability_upgrade_wall",
        abilityname = "升级城墙",
        abilitydesc = "消耗资源提升城墙等级、生命值和护甲。升级条件和费用由服务端实时校验。",
        abilityicon = "ogre_magi_bloodlust",
    },
    ability_upgrade_city = {
        abilityid = "ability_upgrade_city",
        abilityname = "升级主城",
        abilitydesc = "消耗木材和金币提升主城等级、生命、护甲和人口上限。",
        abilityicon = "alchemist_goblins_greed",
    },
    ability_train_lumberjack = {
        abilityid = "ability_train_lumberjack",
        abilityname = "训练伐木工",
        abilitydesc = "训练一名伐木工。伐木工会在主城外侧出生，并自动攻击资源树。当前每次有效攻击获得1点木材。",
        abilityicon = "furion_force_of_nature",
    },
    ability_upgrade_tower = {
        abilityid = "ability_upgrade_tower",
        abilityname = "升级防御塔",
        abilitydesc = "防御塔前5级按固定等级表成长；达到5级后必须选择一个转职方向，之后可以持续升级。",
        abilityicon = "drow_ranger_multishot",
    },
    ability_tower_class_1 = {
        abilityid = "ability_tower_class_1",
        abilityname = "转职一",
        abilitydesc = "选择防御塔转职方向一。五个方向当前消耗相同。",
        abilityicon = "axe_battle_hunger",
    },
    ability_tower_class_2 = {
        abilityid = "ability_tower_class_2",
        abilityname = "转职二",
        abilitydesc = "选择防御塔转职方向二。五个方向当前消耗相同。",
        abilityicon = "drow_ranger_frost_arrows",
    },
    ability_tower_class_3 = {
        abilityid = "ability_tower_class_3",
        abilityname = "转职三",
        abilitydesc = "选择防御塔转职方向三。五个方向当前消耗相同。",
        abilityicon = "windrunner_focusfire",
    },
    ability_tower_class_4 = {
        abilityid = "ability_tower_class_4",
        abilityname = "转职四",
        abilitydesc = "选择防御塔转职方向四。五个方向当前消耗相同。",
        abilityicon = "sniper_take_aim",
    },
    ability_tower_class_5 = {
        abilityid = "ability_tower_class_5",
        abilityname = "转职五",
        abilitydesc = "选择防御塔转职方向五。五个方向当前消耗相同。",
        abilityicon = "zuus_arc_lightning",
    },
}

return M
