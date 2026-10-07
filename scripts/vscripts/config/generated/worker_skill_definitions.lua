-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: worker_skill_definitions.csv
local M = {}
M.rows = {
    { skill_id = "ability_repairer_suicide", name = "自我销毁", description = "立即销毁当前修理工并返还其占用的1人口。训练消耗的木材和金币不返还。", icon = "techies_suicide", enabled = true, source = "修理工系统" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["skill_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
