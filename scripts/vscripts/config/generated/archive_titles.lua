-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_titles.csv
local M = {}
M.rows = {
    { title_id = "peak_perfection", display_name = "登峰造极", icon = "file://{images}/custom_game/titles/peak_perfection_dragons_red.png", description = "登临群峰之巅。穿戴后在出战英雄头顶显示。", unlock_condition = "首发体验称号·免费开放", default_unlocked = true, enabled = true },
    { title_id = "jinghong", display_name = "惊鸿", icon = "file://{images}/custom_game/titles/series/jinghong_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
    { title_id = "youlong", display_name = "游龙", icon = "file://{images}/custom_game/titles/series/youlong_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
    { title_id = "jian_tianya", display_name = "仗剑天涯", icon = "file://{images}/custom_game/titles/series/jian_tianya_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
    { title_id = "tianxia_diyi", display_name = "天下第一", icon = "file://{images}/custom_game/titles/series/tianxia_diyi_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
    { title_id = "cangqiong", display_name = "苍穹之巅", icon = "file://{images}/custom_game/titles/series/cangqiong_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
    { title_id = "sihai", display_name = "纵横四海", icon = "file://{images}/custom_game/titles/series/sihai_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
    { title_id = "daoyuan", display_name = "大道本源", icon = "file://{images}/custom_game/titles/series/daoyuan_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
    { title_id = "chushen", display_name = "出神入化", icon = "file://{images}/custom_game/titles/series/chushen_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "暂未开放", default_unlocked = false, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["title_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
