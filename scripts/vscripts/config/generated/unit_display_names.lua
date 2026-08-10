-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: unit_display_names.csv
local M = {}
M.rows = {
    { unit_name = "npc_dota_hero_undying", display_name = "建造者", enabled = true, notes = "初始建造单位在选中面板显示的名称。" },
    { unit_name = "npc_survival_builder_proxy", display_name = "建造者", enabled = true, notes = "独立建造代理单位的本地化名称。" },
    { unit_name = "npc_survival_repairer", display_name = "修理工", enabled = true, notes = "修理工单位的本地化名称。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["unit_name"]
    if key ~= nil then M.by_id[key] = row end
end
return M
