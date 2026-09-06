-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_fishing_items.csv
local M = {}
M.rows = {
    { reward_id = "star_blessing_001", display_name = "青萍", max_owned = 90, description = "初始木材+10", workbook_description = "初始木材+10", quality = "N", enabled = true },
    { reward_id = "star_blessing_002", display_name = "浮玉", max_owned = 300, description = "墙生命+500", workbook_description = "墙生命+500", quality = "N", enabled = true },
    { reward_id = "star_blessing_003", display_name = "银朱", max_owned = 300, description = "墙每秒生命+1", workbook_description = "墙每秒生命+1", quality = "N", enabled = true },
    { reward_id = "star_blessing_004", display_name = "墨影", max_owned = 300, description = "箭塔攻击+30", workbook_description = "箭塔攻击+30", quality = "N", enabled = true },
    { reward_id = "star_blessing_005", display_name = "雪沫", max_owned = 300, description = "英雄初始属性+500", workbook_description = "英雄初始属性+500", quality = "N", enabled = true },
    { reward_id = "star_blessing_006", display_name = "素锦", max_owned = 300, description = "墙生命恢复+5", workbook_description = "墙生命恢复+5", quality = "N", enabled = true },
    { reward_id = "star_blessing_007", display_name = "星子", max_owned = 300, description = "墙伤害格挡+5", workbook_description = "墙伤害格挡+5", quality = "N", enabled = true },
    { reward_id = "star_blessing_008", display_name = "寸渊", max_owned = 300, description = "英雄每秒属性+2", workbook_description = "英雄每秒属性+2", quality = "N", enabled = true },
    { reward_id = "star_blessing_009", display_name = "秋毫", max_owned = 80, description = "箭塔每秒攻击+1", workbook_description = "箭塔每秒攻击+1", quality = "N", enabled = true },
    { reward_id = "star_blessing_010", display_name = "逍遥", max_owned = 200, description = "英雄生命加成+0.3%", workbook_description = "英雄生命加成+0.3%", quality = "N", enabled = true },
    { reward_id = "star_blessing_011", display_name = "从容", max_owned = 200, description = "英雄护甲加成+0.3%", workbook_description = "英雄护甲加成+0.3%", quality = "N", enabled = true },
    { reward_id = "star_blessing_012", display_name = "沧浪", max_owned = 90, description = "英雄最终伤害+0.3%", workbook_description = "英雄最终伤害+0.3%", quality = "N", enabled = true },
    { reward_id = "star_blessing_013", display_name = "碧虚", max_owned = 200, description = "英雄每秒属性+4", workbook_description = "英雄每秒属性+4", quality = "N", enabled = true },
    { reward_id = "star_blessing_014", display_name = "澹然", max_owned = 200, description = "英雄攻击速度+1%", workbook_description = "英雄攻击速度+1%", quality = "N", enabled = true },
    { reward_id = "star_blessing_015", display_name = "清晏", max_owned = 200, description = "墙护甲加成+2%", workbook_description = "墙护甲+2", quality = "N", enabled = true },
    { reward_id = "star_blessing_016", display_name = "云汀", max_owned = 30, description = "金矿效率+0.5%", workbook_description = "金矿效率+0.5%", quality = "N", enabled = true },
    { reward_id = "star_blessing_017", display_name = "鲲息", max_owned = 12, description = "每秒木材+1", workbook_description = "每秒木材+1", quality = "N", enabled = true },
    { reward_id = "star_blessing_018", display_name = "负天", max_owned = 13, description = "箭塔攻速+1%", workbook_description = "箭塔攻速+1%", quality = "N", enabled = true },
    { reward_id = "star_blessing_019", display_name = "蓬莱", max_owned = 11, description = "伐木工攻速+1%", workbook_description = "伐木工攻速+1%", quality = "N", enabled = true },
    { reward_id = "star_blessing_020", display_name = "龙骧", max_owned = 11, description = "箭塔每秒攻击+3", workbook_description = "箭塔每秒攻击+3", quality = "N", enabled = true },
    { reward_id = "star_blessing_021", display_name = "定海", max_owned = 120, description = "箭塔攻击加成+0.5%", workbook_description = "箭塔攻击加成+0.5%", quality = "N", enabled = true },
    { reward_id = "star_blessing_022", display_name = "太玄", max_owned = 11, description = "伐木效率+1", workbook_description = "伐木效率+1", quality = "N", enabled = true },
    { reward_id = "star_blessing_023", display_name = "归墟", max_owned = 60, description = "英雄三围加成+0.5%", workbook_description = "英雄三围加成+0.5%", quality = "N", enabled = true },
    { reward_id = "star_blessing_024", display_name = "坤舆", max_owned = 15, description = "英雄攻击减甲+0.5", workbook_description = "英雄攻击减甲+0.5", quality = "N", enabled = true },
    { reward_id = "star_blessing_025", display_name = "霍云", max_owned = 60, description = "箭塔造成伤害攻击+1", workbook_description = "英雄造成伤害攻击+1", quality = "N", enabled = true },
    { reward_id = "star_blessing_026", display_name = "北冥", max_owned = 11, description = "箭塔造成伤害攻击+1", workbook_description = "箭塔造成伤害攻击+1", quality = "N", enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["reward_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
