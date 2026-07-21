-- generated/content_catalog 描述逐句分类；status: mapped/narrative/pending_confirmation/unsupported。
local M = {}
M.rows = {}
local function add(id, sentence, status, mapping)
    M.rows[#M.rows + 1] = { content_id = id, sentence = sentence, status = status, mapping = mapping }
end

add("item_death_mask", "死亡面罩（需求别名：吸血面罩）", "mapped", "aliases.death_mask")
add("item_death_mask", "攻击伤害50%转为生命", "mapped", "lifesteal_pct=50")
for level = 1, 4 do
    add(string.format("weapon_growth_sword_%02d", level), "每次攻击增加对应等级攻击力", "mapped", "attack_gain_on_attack")
    add(string.format("weapon_growth_sword_%02d", level), "攻击200次进化", "mapped", "normal_attack_count=200")
end
add("weapon_growth_sword_max", "每次攻击增加5点攻击力", "mapped", "attack_gain_on_attack=5")
add("weapon_growth_sword_max", "与吸血面罩自动合成后继武器", "pending_confirmation", "幻影之剑/霜之剑刃命名冲突")

for level = 1, 4 do
    local id = string.format("weapon_frost_blade_%02d", level)
    add(id, "每次攻击增加6~9点攻击力", "mapped", "attack_gain_on_attack")
    add(id, "50%吸血", "mapped", "lifesteal_pct=50")
    add(id, "攻击次数进化", level == 2 and "mapped" or "pending_confirmation", "明确需求覆盖为200/300/400/500")
end
add("weapon_frost_blade_max", "每次攻击增加10点攻击力并有50%吸血", "mapped", "完整效果快照")
add("weapon_frost_blade_max", "与大极地晶石、合成宝石合成极寒之刃", "mapped", "recipe_frost_max_crystal_gem_to_ice_01")
add("item_small_polar_crystal", "全属性+1000", "mapped", "all_attributes_flat=1000")
add("item_small_polar_crystal", "击杀200个冰之幽魂升级", "mapped", "challenge_06虚拟合法死亡计数")
add("item_large_polar_crystal", "全属性+2000", "mapped", "all_attributes_flat=2000")

for level = 1, 5 do
    local id = level == 5 and "weapon_ice_blade_max" or string.format("weapon_ice_blade_%02d", level)
    add(id, "50%吸血", "mapped", "lifesteal_pct=50")
    add(id, level < 4 and "50%暴击2倍" or "50%暴击5倍", "mapped", "critical_chance_pct/critical_multiplier")
    add(id, "静态全属性", "mapped", "all_attributes_flat")
    add(id, "成长攻击力", "mapped", "合法敌人死亡且击杀归属玩家；不得按valid_hit触发")
    if level < 5 then add(id, "击杀敌人升级", "mapped", "valid_enemy_kill_count=200/300/400/500") end
end

for level = 1, 5 do
    local id = level == 5 and "equipment_infernal_armor_max" or string.format("equipment_infernal_armor_%02d", level)
    add(id, "攻击/攻速/生命/护甲静态属性", "mapped", "完整效果快照")
    add(id, "200范围每秒全属性倍率伤害", "mapped", "aura_attribute_damage")
end
add("equipment_infernal_armor_04", "熔火核心Lv4升级至MAX", "mapped", "明确需求启用")
add("material_molten_core_04", "原表误写Lv3升级Lv4", "pending_confirmation", "只作Excel笔误审核，不影响Lv4核心配方")

for stage = 0, 7 do
    local id = string.format("weapon_epic_icefire_%02d", stage)
    add(id, "静态攻击/攻速/吸血/生命/护甲/全属性", stage < 7 and "mapped" or "unsupported", stage < 7 and "完整阶段快照" or "+7数值缺失，快照关闭")
    add(id, "200范围每秒全属性*5", stage < 7 and "mapped" or "unsupported", "aura_attribute_damage")
    add(id, "攻击增加20攻击与5全属性", stage < 7 and "mapped" or "unsupported", "attack_gain_on_attack/attributes_gain_on_attack")
    add(id, "10%概率500范围焰爆，全属性*50", stage < 7 and "mapped" or "unsupported", "proc_attribute_damage")
end
for stage = 0, 10 do
    local id = string.format("weapon_legend_abyss_%02d", stage)
    add(id, "静态属性与冰火裁决同类被动", "mapped", "完整阶段快照，按名称阶段而非legacy ID排序")
end
add("challenge_10", "七宗罪概率掉落精华并强化史诗武器", "pending_confirmation", "7阶段结构与结果已配；Boss/精华数值未知关闭")
add("challenge_11", "十戒Boss强化传说武器", "pending_confirmation", "10阶段结构与结果已配；Boss数值未知关闭")

M.by_content_id = {}
for _, row in ipairs(M.rows) do
    M.by_content_id[row.content_id] = M.by_content_id[row.content_id] or {}
    table.insert(M.by_content_id[row.content_id], row)
end
return M
