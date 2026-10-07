-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_titles.csv
local M = {}
M.rows = {
    { title_id = "peak_perfection", display_name = "登峰造极", icon = "file://{images}/custom_game/titles/peak_perfection_dragons_red.png", description = "登临群峰之巅。穿戴后在出战英雄头顶显示。", unlock_condition = "首发体验称号·免费开放", default_unlocked = true, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["title_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
