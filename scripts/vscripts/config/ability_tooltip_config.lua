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
    ability_build_gold_mine = {
        abilityid = "ability_build_gold_mine",
        abilityname = "建造金矿",
        abilitydesc = "主城达到3级后解锁。建造后每秒自动产出金币，并可升级采集效率和暴击率。",
        abilityicon = "alchemist_goblins_greed",
    },
    ability_upgrade_gold_mine = {
        abilityid = "ability_upgrade_gold_mine",
        abilityname = "提升采集效率",
        abilitydesc = "提高金矿采集效率等级。每级使每秒基础金币产量增加5点，最高10级。",
        abilityicon = "alchemist_goblins_greed",
    },
    ability_upgrade_gold_mine_crit = {
        abilityid = "ability_upgrade_gold_mine_crit",
        abilityname = "提升采集暴击率",
        abilitydesc = "暴击率共10级，每级增加2%。暴击时本次金币产量为正常产量的150%。",
        abilityicon = "phantom_assassin_coup_de_grace",
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

    ability_build_hero_altar = {
        abilityid = "ability_build_hero_altar",
        abilityname = "建造英雄祭坛",
        abilitydesc = "主城达到3级后可建造。祭坛可以召唤一个战斗英雄；召唤完成后祭坛停止工作，并解锁商店。",
        abilityicon = "omniknight_guardian_angel",
    },
    ability_open_hero_altar = {
        abilityid = "ability_open_hero_altar",
        abilityname = "召唤英雄",
        abilitydesc = "从斧王、斯拉克、主宰、齐天大圣和宙斯中选择一个英雄。每位玩家只能选择一次，齐天大圣和宙斯需要VIP。",
        abilityicon = "chen_holy_persuasion",
    },

ability_summon_axe = {
    abilityid = "ability_summon_axe",
    abilityname = "召唤斧王",
    abilitydesc = "召唤斧王作为战斗英雄。清除原版技能后，初始获得1个斧王专属项目技能。",
    abilityicon = "axe_berserkers_call",
},
ability_summon_slark = {
    abilityid = "ability_summon_slark",
    abilityname = "召唤斯拉克",
    abilitydesc = "召唤斯拉克作为战斗英雄。清除原版技能后，初始获得1个斯拉克专属项目技能。",
    abilityicon = "slark_dark_pact",
},
ability_summon_juggernaut = {
    abilityid = "ability_summon_juggernaut",
    abilityname = "召唤主宰",
    abilitydesc = "召唤主宰作为战斗英雄。清除原版技能后，初始获得1个主宰专属项目技能。",
    abilityicon = "juggernaut_blade_fury",
},
ability_summon_monkey_king = {
    abilityid = "ability_summon_monkey_king",
    abilityname = "召唤齐天大圣（VIP）",
    abilitydesc = "召唤齐天大圣。需要VIP权限，攻击距离1000，清除原版技能后初始获得4个项目技能。",
    abilityicon = "monkey_king_boundless_strike",
},
ability_summon_blademaster = {
    abilityid = "ability_summon_blademaster",
    abilityname = "召唤剑圣（VIP）",
    abilitydesc = "召唤剑圣。需要VIP权限；当前使用Sven作为测试载体，初始获得4个项目技能。",
    abilityicon = "sven_gods_strength",
},
}

return M
