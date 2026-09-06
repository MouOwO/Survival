-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_drop_rules.csv
local M = {}
M.rows = {
    { rule_id = "white", quality = "white", weight = 33, base_count = 2, pass_bonus_count = 1, pass_entitlement_id = "archive_pass", enabled = true, notes = "27.5%；剩余30%均分补到四品质；品质内等概率。" },
    { rule_id = "blue", quality = "blue", weight = 29, base_count = 2, pass_bonus_count = 1, pass_entitlement_id = "archive_pass", enabled = true, notes = "24.1666667%；品质内等概率。" },
    { rule_id = "purple", quality = "purple", weight = 29, base_count = 2, pass_bonus_count = 1, pass_entitlement_id = "archive_pass", enabled = true, notes = "24.1666667%；品质内等概率。" },
    { rule_id = "green", quality = "green", weight = 29, base_count = 2, pass_bonus_count = 1, pass_entitlement_id = "archive_pass", enabled = true, notes = "24.1666667%；品质内等概率。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
