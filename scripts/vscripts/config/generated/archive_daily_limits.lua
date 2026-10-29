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
    { limit_id = "fragment_01", display_name = "每日霜之哀伤碎片", storage_key = "fragment_01", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 80, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_02", display_name = "每日米奈希尔之力碎片", storage_key = "fragment_02", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 81, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_03", display_name = "每日埃辛诺斯战刃碎片", storage_key = "fragment_03", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 82, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_04", display_name = "每日灰烬使者碎片", storage_key = "fragment_04", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 83, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_05", display_name = "每日血吼碎片", storage_key = "fragment_05", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 84, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_06", display_name = "每日索利达尔群星之怒碎片", storage_key = "fragment_06", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 85, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_07", display_name = "每日雷霆之怒逐风者的祝福之剑碎片", storage_key = "fragment_07", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 86, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_08", display_name = "每日阿什坎迪兄弟会之剑碎片", storage_key = "fragment_08", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 87, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_09", display_name = "每日星月湮灭战弓碎片", storage_key = "fragment_09", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 88, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_10", display_name = "每日圣光裁决之锤碎片", storage_key = "fragment_10", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 89, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_11", display_name = "每日泰蕾苟萨法杖碎片", storage_key = "fragment_11", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 90, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_12", display_name = "每日萨格拉斯之杖碎片", storage_key = "fragment_12", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 91, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "endless", display_name = "每日无尽积分", storage_key = "endless_total", daily_limit = 50000, pass_daily_limit = 50000, implemented = true, sort_order = 100, notes = "按实际获得积分计入" },
    { limit_id = "football", display_name = "每日绿茵积分", storage_key = "football_total", daily_limit = 100, pass_daily_limit = 100, implemented = true, sort_order = 110, notes = "绿茵挑战实际获得积分；每日100；10点每次" },
    { limit_id = "fishing", display_name = "每日钓鱼", storage_key = "fishing_total", daily_limit = 80, pass_daily_limit = 80, implemented = true, sort_order = 120, notes = "PostgreSQL原子限制永久钓鱼奖励件数" },
    { limit_id = "social_beast", display_name = "每日瑞兽赐福", storage_key = "social_beast", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 130, notes = "福签" },
    { limit_id = "paid_points", display_name = "每日带薪积分", storage_key = "paid_points_total", daily_limit = 1000, pass_daily_limit = 1000, implemented = false, sort_order = 140, notes = "预留；不映射上班福利消费" },
    { limit_id = "social_ex", display_name = "每日邀请函", storage_key = "social_ex", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 150, notes = "邀请函" },
    { limit_id = "social_friend", display_name = "每日义帖", storage_key = "social_friend", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 151, notes = "义帖" },
    { limit_id = "social_wife", display_name = "每日玫瑰", storage_key = "social_wife", daily_limit = 10, pass_daily_limit = 20, implemented = true, sort_order = 152, notes = "玫瑰" },
    { limit_id = "salary", display_name = "每日工资", storage_key = "salary_total", daily_limit = 10, pass_daily_limit = 10, implemented = true, sort_order = 160, notes = "侍妾挑战工资；每日10；消费不返还名额" },
    { limit_id = "faith", display_name = "每日信仰值", storage_key = "faith_total", daily_limit = 3000, pass_daily_limit = 3000, implemented = true, sort_order = 170, notes = "兼容已有buildings.earned_by_day" },
    { limit_id = "fragment_13", display_name = "每日黑暗撕裂者碎片", storage_key = "fragment_13", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 92, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_14", display_name = "每日创世权柄碎片", storage_key = "fragment_14", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 93, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_15", display_name = "每日万军崩裂碎片", storage_key = "fragment_15", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 94, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "fragment_16", display_name = "每日守界圣辉碎片", storage_key = "fragment_16", daily_limit = 20, pass_daily_limit = 40, implemented = true, sort_order = 95, notes = "按实际获取片数；VIP与月卡不提高" },
    { limit_id = "watermelon", display_name = "每日西瓜积分", storage_key = "watermelon_total", daily_limit = 10, pass_daily_limit = 10, implemented = true, sort_order = 111, notes = "西瓜挑战每日10；每次1点" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["limit_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
