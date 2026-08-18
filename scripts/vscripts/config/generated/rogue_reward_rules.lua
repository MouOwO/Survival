-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: rogue_reward_rules.csv
local M = {}
M.rows = {
    { rule_id = "default_rogue_reward", choice_count = 3, free_reroll_count = 1, exclude_claimed = true, unique_within_offer = true, enabled = true, tooltip_name = "肉鸽奖励", tooltip_desc = "打开肉鸽三选一奖励。建造者开局固定显示在G键槽位，成功打开后移除。", tooltip_icon = "item_tome_of_knowledge", notes = "正式Boss与开局技能共用；未选择和被重抽的卡不会永久排除。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
