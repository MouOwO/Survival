local M = {}
local rows = {}
local function add(def)
    for level = def.start_level or 1, def.max_level do
        rows[#rows + 1] = {
            technology_id = def.id .. "_" .. string.format("%02d", level),
            technology_group = def.group or def.id,
            technology_phase = def.phase or 0,
            technology_track = def.track,
            unlock_technology_group = def.unlock_group or "",
            level = level, max_level = def.max_level,
            wood_cost = def.wood(level), gold_cost = def.gold and def.gold(level) or 0,
            value_per_level = def.value(level), effect_type = def.effect_type,
            effect_value = def.value(level), enabled = true, review_status = "ok",
            notes = def.notes, shop_enabled = true, shop_category_id = "technology",
            shop_sort_order = def.order + level, required_city_level = 1,
            requires_hero_summoned = def.requires_hero_summoned == true,
            requires_building_id = "", purchase_limit = 0,
            grant_type = "technology_level", icon_name = def.icon,
            unlock_required_level = def.unlock_required_level or 0,
        }
    end
end

local function add_basic_layers(def)
    local phase_two = {}
    for key, value in pairs(def) do phase_two[key] = value end
    def.phase = 1
    def.max_level = 10
    add(def)
    phase_two.id = def.id .. "_phase2"
    phase_two.group = def.id
    phase_two.phase = 2
    phase_two.start_level = 11
    phase_two.max_level = 20
    phase_two.order = def.order + 10
    add(phase_two)
end

add_basic_layers({id="lumberjack_speed",track="basic",order=100,effect_type="lumberjack_attack_speed_pct",icon="ability_train_lumberjack",value=function(n)return n*5 end,wood=function(n)return 200+(n-1)*400 end,notes="所有伐木工攻速每级提高5%。"})
add_basic_layers({id="lumberjack_efficiency",track="basic",order=120,effect_type="lumberjack_wood_per_hit",icon="ability_train_lumberjack",value=function(n)return n end,wood=function(n)return 200+(n-1)*300 end,notes="所有伐木工每次采集木材增加1。"})
add_basic_layers({id="tower_attack",track="basic",order=140,effect_type="tower_attack_flat",icon="ability_upgrade_attack",value=function(n)return n*200 end,wood=function(n)return 300+(n-1)*200 end,notes="所有防御塔攻击力每级提高200。"})
add_basic_layers({id="wall_health",track="basic",order=160,effect_type="wall_health_pct",icon="ability_upgrade_wall",value=function(n)return n*15 end,wood=function(n)return 200+(n-1)*300 end,notes="所有城墙生命值每级提高15%。"})
add({id="advanced_lumberjack_speed",track="advanced",unlock_group="lumberjack_speed",unlock_required_level=5,max_level=30,order=300,effect_type="lumberjack_attack_interval_flat",icon="ability_train_lumberjack",value=function()return 0.01 end,wood=function(n)return 4000+n*1000 end,gold=function(n)return n*1000 end,notes="高级：伐木工攻速达到Lv.5后解锁；普通攻速仍可继续升级。"})
add({id="advanced_lumberjack_efficiency",track="advanced",unlock_group="lumberjack_efficiency",unlock_required_level=10,max_level=30,order=340,effect_type="lumberjack_wood_per_hit_advanced",icon="ability_train_lumberjack",value=function(n)return n*3 end,wood=function(n)return 500+n*500 end,gold=function(n)return 4000+n*1000 end,notes="高级：伐木工效率达到Lv.10后解锁；普通效率仍可继续升级。"})
add({id="advanced_tower_attack",track="advanced",unlock_group="tower_attack",unlock_required_level=20,max_level=20,order=380,effect_type="tower_attack_flat_advanced",icon="ability_upgrade_attack",value=function(n)return n*1000 end,wood=function()return 0 end,gold=function(n)return 500+n*500 end,notes="高级：普通防御塔强化满级后解锁。"})
add({id="advanced_wall_health",track="advanced",unlock_group="wall_health",unlock_required_level=20,max_level=20,order=420,effect_type="wall_health_pct_advanced",icon="ability_upgrade_wall",value=function(n)return n*50 end,wood=function(n)return 4000+n*1000 end,gold=function(n)return 500+n*500 end,notes="高级：普通墙强化满级后解锁。"})
add({id="advanced_wall_health",track="advanced",unlock_group="wall_health",max_level=20,order=420,effect_type="wall_health_pct_advanced",icon="ability_upgrade_wall",value=function(n)return n*30 end,wood=function()return 0 end,gold=function(n)return 500+n*500 end,notes="高级：所有城墙生命值每级提高30%。"})

local function add_researcher(def)
    for level = 1, def.max_level do
        rows[#rows + 1] = {
            technology_id = def.id .. "_" .. string.format("%02d", level),
            technology_group = def.id,
            technology_phase = 0,
            technology_track = "advanced_researcher",
            unlock_technology_group = "advanced_researcher_service",
            level = level, max_level = def.max_level,
            wood_cost = def.wood(level), gold_cost = def.gold(level),
            value_per_level = def.value(level), effect_type = def.effect_type,
            effect_value = def.value(level), enabled = true, review_status = "ok",
            notes = def.notes, shop_enabled = true, shop_category_id = "technology",
            shop_sort_order = def.order + level, required_city_level = 4,
            requires_hero_summoned = string.match(def.id, "^researcher_hero_") ~= nil,
            requires_building_id = "",
            purchase_limit = 0, grant_type = "technology_level", icon_name = def.icon,
        }
    end
end

add_researcher({id="researcher_lumberjack_attack_growth",max_level=30,order=500,effect_type="lumberjack_attack_growth",icon="ability_train_lumberjack",value=function(n)return n*2 end,wood=function()return 0 end,gold=function(n)return 30000+(n-1)*10000 end,notes="高级研究员：伐木工攻击力每级成长2点。"})
add_researcher({id="researcher_lumberjack_armor_reduction",max_level=30,order=540,effect_type="lumberjack_attack_armor_reduction",icon="ability_train_lumberjack",value=function(n)return n*0.1 end,wood=function()return 0 end,gold=function(n)return 20000+(n-1)*5000 end,notes="高级研究员：伐木工攻击使目标护甲降低0.1。"})
add_researcher({id="researcher_super_wall_health",max_level=30,order=580,effect_type="super_wall_health_pct",icon="ability_upgrade_wall",value=function(n)return n*3 end,wood=function(n)return 100000+(n-1)*30000 end,gold=function(n)return 30000+(n-1)*20000 end,notes="高级研究员：超级墙生命值强化。"})
add_researcher({id="researcher_super_wall_armor",max_level=30,order=620,effect_type="super_wall_armor_flat",icon="ability_upgrade_wall",value=function(n)return n*3 end,wood=function(n)return 100000+(n-1)*30000 end,gold=function(n)return 30000+(n-1)*20000 end,notes="高级研究员：超级墙护甲强化。"})
add_researcher({id="researcher_super_tower_attack",max_level=30,order=660,effect_type="super_tower_attack_flat",icon="ability_upgrade_attack",value=function(n)return n*30000 end,wood=function(n)return 100000+(n-1)*30000 end,gold=function(n)return 30000+(n-1)*20000 end,notes="高级研究员：超级防御塔攻击力每级提高30000。"})
add_researcher({id="researcher_super_tower_range",max_level=30,order=700,effect_type="super_tower_attack_range",icon="ability_upgrade_attack",value=function(n)return n*30 end,wood=function(n)return 100000+(n-1)*30000 end,gold=function(n)return 30000+(n-1)*20000 end,notes="高级研究员：超级防御塔攻击范围每级增加30。"})
add_researcher({id="researcher_super_tower_crit",max_level=23,order=740,effect_type="super_tower_crit_pct",icon="ability_upgrade_attack",value=function(n)return n*1 end,wood=function(n)return 300000+(n-1)*30000 end,gold=function(n)return 1000+(n-1)*20000 end,notes="高级研究员：超级防御塔暴击率每级提高1%。"})
add_researcher({id="researcher_hero_final_damage",max_level=19,order=780,effect_type="hero_final_damage_pct",icon="ability_upgrade_attack",value=function(n)return n*1 end,wood=function(n)return n*50000 end,gold=function(n)return n*10000 end,notes="高级研究员：英雄最终伤害每级提高1%。"})
add_researcher({id="researcher_hero_armor_reduction",max_level=19,order=820,effect_type="hero_attack_armor_reduction",icon="ability_upgrade_attack",value=function(n)return n*0.5 end,wood=function(n)return n*50000 end,gold=function(n)return n*10000 end,notes="高级研究员：英雄攻击减甲每级增加0.5。"})
add_researcher({id="researcher_hero_attack",max_level=19,order=860,effect_type="hero_attack_flat",icon="ability_upgrade_attack",value=function(n)return n*2 end,wood=function(n)return n*50000 end,gold=function(n)return n*10000 end,notes="高级研究员：英雄攻击力每级提高2。"})
M.rows=rows; M.by_id={}; for _,row in ipairs(rows) do M.by_id[row.technology_id]=row end; return M
