-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: reward_profiles.csv
local M = {}
M.rows = {
    { reward_profile_id = "reward_practice_wood_100", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "木材练功房奖励", reward_text = "击杀每个怪物获得100木材。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_practice_gold_100", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "金币练功房奖励", reward_text = "击杀每个怪物获得100金币。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_practice_attribute_10", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "属性练功房奖励", reward_text = "击杀每个怪物获得100点全属性。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_practice_attribute_100_gold_1000", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "大属性练功房奖励", reward_text = "击杀每个怪物获得1000点全属性。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_building_challenge_mountain_giant", reward_group = "building_challenge", trigger_type = "on_each_kill", display_name = "山岭巨人挑战奖励", reward_text = "城墙护甲+3，城墙生命+1%。", repeatable = true, enabled = true, notes = "按山岭巨人每次击杀重复叠加。" },
    { reward_profile_id = "reward_building_challenge_treant", reward_group = "building_challenge", trigger_type = "on_each_kill", display_name = "树人挑战奖励", reward_text = "箭塔攻击+100×挑战次数，箭塔攻击加成+1%。", repeatable = true, enabled = true, notes = "固定与按挑战次数缩放效果组合。" },
    { reward_profile_id = "reward_building_challenge_red_dragon", reward_group = "building_challenge", trigger_type = "on_each_kill", display_name = "红龙挑战奖励", reward_text = "伐木效率+1。", repeatable = true, enabled = true, notes = "按红龙每次击杀重复叠加。" },
    { reward_profile_id = "reward_building_challenge_blademaster", reward_group = "building_challenge", trigger_type = "on_each_kill", display_name = "剑圣挑战奖励", reward_text = "英雄全属性+1000×挑战次数，攻击+2000×挑战次数。", repeatable = true, enabled = true, notes = "按剑圣挑战次数缩放。" },
    { reward_profile_id = "reward_building_challenge_alchemist", reward_group = "building_challenge", trigger_type = "on_each_kill", display_name = "炼金挑战奖励", reward_text = "金矿收益+2%。", repeatable = true, enabled = true, notes = "按炼金每次击杀重复叠加。" },
    { reward_profile_id = "reward_rebirth_01", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "一转奖励", reward_text = "获得英雄专属技能/提高英雄2000全属性/增加攻击全属性+1/解锁分裂多重攻击", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_02", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "二转奖励", reward_text = "公共技能三选一/提高英雄3000全属性/增加攻击全属性+2/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；选择后技能从本局公共池移除。" },
    { reward_profile_id = "reward_rebirth_03", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "三转奖励", reward_text = "公共技能三选一/提高英雄5000全属性/增加攻击全属性+3/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；选择后技能从本局公共池移除。" },
    { reward_profile_id = "reward_rebirth_04", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "四转奖励", reward_text = "公共技能三选一/提高英雄10000全属性/增加攻击全属性+4/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；选择后技能从本局公共池移除。" },
    { reward_profile_id = "reward_rebirth_05", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "五转奖励", reward_text = "公共技能三选一/提高英雄20000全属性/增加攻击全属性+6/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；选择后技能从本局公共池移除。" },
    { reward_profile_id = "reward_rebirth_06", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "六转奖励", reward_text = "公共技能点+1/提高英雄30000全属性/增加攻击全属性+7/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；技能点不能升级专属技能。" },
    { reward_profile_id = "reward_rebirth_07", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "七转奖励", reward_text = "公共技能点+1/提高英雄50000全属性/增加攻击全属性+8/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；技能点不能升级专属技能。" },
    { reward_profile_id = "reward_rebirth_08", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "八转奖励", reward_text = "公共技能点+1/提高英雄70000全属性/增加攻击全属性+9/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；技能点不能升级专属技能。" },
    { reward_profile_id = "reward_rebirth_09", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "九转奖励", reward_text = "公共技能点+1/提高英雄100000全属性/增加攻击全属性+10/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；技能点不能升级专属技能。" },
    { reward_profile_id = "reward_rebirth_10", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "十转奖励", reward_text = "公共技能点+1/提高英雄200000全属性/增加攻击全属性+12/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；技能点不能升级专属技能。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["reward_profile_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
