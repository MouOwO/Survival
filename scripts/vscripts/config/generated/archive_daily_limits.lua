-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_daily_limits.csv
local M = {}
M.rows = {
    { limit_id = "clear", display_name = "每日通关", storage_key = "clear_total", daily_limit = 20, pass_daily_limit = 20, implemented = true, sort_order = 10, notes = "全模式共用通关获取额度" },
    { limit_id = "mode_rich", display_name = "每日丰饶模式", storage_key = "mode_rich", daily_limit = 20, pass_daily_limit = 20, implemented = true, sort_order = 20, notes = "丰饶模式独立额度" },
    { limit_id = "mode_cold", display_name = "每日极寒模式", storage_key = "mode_cold", daily_limit = 10, pass_daily_limit = 10, implemented = true, sort_order = 21, notes = "极寒模式独立额度" },
    { limit_id = "mode_scourge", display_name = "每日天灾模式", storage_key = "mode_scourge", daily_limit = 10, pass_daily_limit = 10, implemented = true, sort_order = 22, notes = "天灾模式独立额度" },
    { limit_id = "mode_guixu", display_name = "每日归墟模式", storage_key = "mode_guixu", daily_limit = 10, pass_daily_limit = 10, implemented = false, sort_order = 23, notes = "预留；尚无独立奖励来源" },
    { limit_id = "mode_tianyu", display_name = "每日天域模式", storage_key = "mode_tianyu", daily_limit = 10, pass_daily_limit = 10, implemented = false, sort_order = 24, notes = "预留；尚无独立奖励来源" },
    { limit_id = "pet", display_name = "每日宠物", storage_key = "pet_total", daily_limit = 20, pass_daily_limit = 20, implemented = false, sort_order = 30, notes = "预留；不映射秘法牢笼" },
    { limit_id = "shadow", display_name = "每日虚空之影", storage_key = "shadow_total", daily_limit = 80, pass_daily_limit = 80, implemented = true, sort_order = 40, notes = "按实际获得件数计入" },
    { limit_id = "coins", display_name = "每日软妹币", storage_key = "coins_total", daily_limit = 8000, pass_daily_limit = 8000, implemented = true, sort_order = 50, notes = "仅计算获取；消费不返还名额" },
    { limit_id = "boss", display_name = "每日BOSS击杀", storage_key = "boss_total", daily_limit = 300, pass_daily_limit = 300, implemented = true, sort_order = 60, notes = "按实际计入次数计数" },
    { limit_id = "cage", display_name = "每日秘法牢笼", storage_key = "cage_total", daily_limit = 30, pass_daily_limit = 90, implemented = true, sort_order = 70, notes = "账号最终每日上限；VIP与月卡不提高" },
    { limit_id = "eternal_arcane", display_name = "每日永恒秘法", storage_key = "eternal_arcane_total", daily_limit = 60, pass_daily_limit = 60, implemented = false, sort_order = 71, notes = "预留；尚无独立奖励来源" },
    { limit_id = "evernight_arcane", display_name = "每日永夜秘法", storage_key = "evernight_arcane_total", daily_limit = 60, pass_daily_limit = 60, implemented = false, sort_order = 72, notes = "预留；尚无独立奖励来源" },
    { limit_id = "fragment_01", display_name = "每日神兵破碎大剑碎片", storage_key = "fragment_01", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 80, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_02", display_name = "每日神兵始祖之祸碎片", storage_key = "fragment_02", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 81, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_03", display_name = "每日神兵焚焰碎片", storage_key = "fragment_03", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 82, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_04", display_name = "每日神兵净魂之刃碎片", storage_key = "fragment_04", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 83, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_05", display_name = "每日神兵狂战斧碎片", storage_key = "fragment_05", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 84, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_06", display_name = "每日神兵碎颅锤碎片", storage_key = "fragment_06", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 85, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_07", display_name = "每日神兵影刃碎片", storage_key = "fragment_07", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 86, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_08", display_name = "每日神兵龙爪弯钩碎片", storage_key = "fragment_08", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 87, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_09", display_name = "每日神兵纯金之触碎片", storage_key = "fragment_09", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 88, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_10", display_name = "每日神兵战鬼双刃碎片", storage_key = "fragment_10", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 89, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_11", display_name = "每日神兵魔头之命碎片", storage_key = "fragment_11", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 90, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_12", display_name = "每日神兵魔导师密钥碎片", storage_key = "fragment_12", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 91, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "endless", display_name = "每日无尽积分", storage_key = "endless_total", daily_limit = 50000, pass_daily_limit = 50000, implemented = true, sort_order = 100, notes = "按实际获得积分计入" },
    { limit_id = "football", display_name = "每日绿茵积分", storage_key = "football_total", daily_limit = 100, pass_daily_limit = 100, implemented = false, sort_order = 110, notes = "预留；尚无独立奖励来源" },
    { limit_id = "fishing", display_name = "每日钓鱼", storage_key = "fishing_total", daily_limit = 80, pass_daily_limit = 80, implemented = true, sort_order = 120, notes = "PostgreSQL原子限制永久钓鱼奖励件数" },
    { limit_id = "social_beast", display_name = "每日瑞兽赐福", storage_key = "social_beast", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 130, notes = "福签" },
    { limit_id = "paid_points", display_name = "每日带薪积分", storage_key = "paid_points_total", daily_limit = 1000, pass_daily_limit = 1000, implemented = false, sort_order = 140, notes = "预留；不映射上班福利消费" },
    { limit_id = "social_ex", display_name = "每日邀请函", storage_key = "social_ex", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 150, notes = "邀请函" },
    { limit_id = "social_friend", display_name = "每日义帖", storage_key = "social_friend", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 151, notes = "义帖" },
    { limit_id = "social_wife", display_name = "每日玫瑰", storage_key = "social_wife", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 152, notes = "玫瑰" },
    { limit_id = "salary", display_name = "每日工资", storage_key = "salary_total", daily_limit = 10, pass_daily_limit = 10, implemented = false, sort_order = 160, notes = "预留；尚无独立奖励来源" },
    { limit_id = "faith", display_name = "每日信仰值", storage_key = "faith_total", daily_limit = 3000, pass_daily_limit = 3000, implemented = true, sort_order = 170, notes = "兼容已有buildings.earned_by_day" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["limit_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
