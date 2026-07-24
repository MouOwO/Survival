-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: data_issues.csv
local M = {}
M.rows = {
    { issue_id = "ISSUE-001", severity = "high", content_id = "weapon_growth_sword_max", issue_type = "合成结果命名冲突", description = "成长之剑描述同时出现“幻影之剑”和“霜之剑刃”。", recommended_action = "确认最终产物名称与ID；当前配方暂指向weapon_frost_blade_01。" },
    { issue_id = "ISSUE-002", severity = "high", content_id = "item_death_mask", issue_type = "商店价格冲突", description = "建筑商店为木材10000+金币300；武器表为木材10000+金币500。", recommended_action = "建议以建筑商店为当前UI价格，策划确认后统一。" },
    { issue_id = "ISSUE-003", severity = "high", content_id = "multiple", issue_type = "可疑价格18", description = "武器表中大量后续等级购买金币为18，疑似占位或解析残留。", recommended_action = "已进入ShopEntries候选但默认enabled=0。" },
    { issue_id = "ISSUE-004", severity = "medium", content_id = "equipment_infernal_armor_04", issue_type = "核心等级疑似笔误", description = "Lv4描述写“熔火核心Lv3升级装备狱火熔铠Lv4”，与系列规律不一致。", recommended_action = "当前按核心Lv4升MAX建模，标记description_inferred。" },
    { issue_id = "ISSUE-005", severity = "medium", content_id = "weapon_epic_icefire", issue_type = "缺少+7行", description = "原表只包含基础到+6，但项目记录为+7后进入传说。", recommended_action = "补充+7正式数据后再生成最终链。" },
    { issue_id = "ISSUE-006", severity = "medium", content_id = "weapon_legend_abyss", issue_type = "原始ID顺序异常", description = "5003对应+10，5004对应+2，不能按数字ID排序。", recommended_action = "系统必须按名称解析后的stage排序。" },
    { issue_id = "ISSUE-007", severity = "low", content_id = "shop_proxy_*", issue_type = "重复购买代理行", description = "2101/2111/2121是购买代理，不应作为真实内容。", recommended_action = "已分类shop_proxy并默认停用，指向真实content_id。" },
    { issue_id = "ISSUE-009", severity = "high", affected_ids = {"challenge_10", "challenge_11"}, issue_type = "挑战Boss临时强度", description = "七宗罪与十宗罪缺少正式生命攻击护甲攻速数据；当前按N1后期曲线配置测试值。", proposed_resolution = "完成实机测试后由策划逐只确认并替换monster_archetypes中的临时数值。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["issue_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
