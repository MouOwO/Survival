-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_skill_choice_rules.csv
local M = {}
M.rows = {
    { rule_id = "rebirth_new_skill", trigger_type = "rebirth_complete", min_trigger_level = 2, max_trigger_level = 5, pool_id = "public_pool", choice_count = 3, allow_owned_skill = false, owned_skill_action = "reject", exclude_max_level = true, unique_within_offer = true, skill_capacity = 10, enabled = true, notes = "二转到五转随机展示三个未拥有技能；选择后获得一级技能并从本局技能池移除。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["rule_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
