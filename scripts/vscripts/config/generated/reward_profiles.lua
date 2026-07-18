-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: reward_profiles.csv
local M = {}
M.rows = {
    { reward_profile_id = "reward_wild_boss_default", reward_group = "wild_boss", trigger_type = "on_encounter_complete", display_name = "野外Boss默认奖励", reward_text = "待配置", repeatable = true, enabled = false, notes = "用户尚未提供普通野外Boss掉落，默认停用。" },
    { reward_profile_id = "reward_practice_wood_100", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "木材练功房奖励", reward_text = "击杀每个怪物获得100木材。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_practice_gold_100", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "金币练功房奖励", reward_text = "击杀每个怪物获得100金币。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_practice_attribute_10", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "属性练功房奖励", reward_text = "击杀每个怪物获得10点全属性。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_practice_attribute_100_gold_1000", reward_group = "practice_room", trigger_type = "on_each_kill", display_name = "大属性练功房奖励", reward_text = "击杀每个怪物获得100点全属性,1000金币。", repeatable = true, enabled = true, notes = "练功房怪物每次死亡均调用同一个通用奖励服务。" },
    { reward_profile_id = "reward_rebirth_01", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "一转奖励", reward_text = "获得英雄专属技能/提高英雄2000全属性/增加攻击全属性+1/解锁分裂多重攻击", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_02", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "二转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄3000全属性/增加攻击全属性+2/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_03", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "三转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄5000全属性/增加攻击全属性+3/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_04", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "四转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄10000全属性/增加攻击全属性+4/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_05", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "五转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄20000全属性/增加攻击全属性+6/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_06", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "六转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄30000全属性/增加攻击全属性+7/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_07", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "七转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄50000全属性/增加攻击全属性+8/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_08", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "八转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄70000全属性/增加攻击全属性+9/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_09", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "九转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄100000全属性/增加攻击全属性+10/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
    { reward_profile_id = "reward_rebirth_10", reward_group = "rebirth", trigger_type = "on_encounter_complete", display_name = "十转奖励", reward_text = "获得随机技能，获得相同的技能时升级技能/提高英雄200000全属性/增加攻击全属性+12/多重攻击+1", repeatable = false, enabled = true, notes = "完成对应转职Boss后只发放一次；服务端必须记录完成状态。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["reward_profile_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
