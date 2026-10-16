-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_titles.csv
local M = {}
M.rows = {
    { title_id = "peak_perfection", display_name = "登峰造极", icon = "file://{images}/custom_game/titles/peak_perfection_dragons_red.png", description = "登临群峰之巅。穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到1层（第1档）", default_unlocked = false, enabled = true, title_level = 1, required_wave = 1 },
    { title_id = "jinghong", display_name = "惊鸿", icon = "file://{images}/custom_game/titles/series/jinghong_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到81层（第2档）", default_unlocked = false, enabled = true, title_level = 2, required_wave = 81 },
    { title_id = "youlong", display_name = "游龙", icon = "file://{images}/custom_game/titles/series/youlong_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到161层（第3档）", default_unlocked = false, enabled = true, title_level = 3, required_wave = 161 },
    { title_id = "jian_tianya", display_name = "仗剑天涯", icon = "file://{images}/custom_game/titles/series/jian_tianya_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到241层（第4档）", default_unlocked = false, enabled = true, title_level = 4, required_wave = 241 },
    { title_id = "tianxia_diyi", display_name = "天下第一", icon = "file://{images}/custom_game/titles/series/tianxia_diyi_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到321层（第5档）", default_unlocked = false, enabled = true, title_level = 5, required_wave = 321 },
    { title_id = "cangqiong", display_name = "苍穹之巅", icon = "file://{images}/custom_game/titles/series/cangqiong_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到401层（第6档）", default_unlocked = false, enabled = true, title_level = 6, required_wave = 401 },
    { title_id = "sihai", display_name = "纵横四海", icon = "file://{images}/custom_game/titles/series/sihai_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到481层（第7档）", default_unlocked = false, enabled = true, title_level = 7, required_wave = 481 },
    { title_id = "daoyuan", display_name = "大道本源", icon = "file://{images}/custom_game/titles/series/daoyuan_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到561层（第8档）", default_unlocked = false, enabled = true, title_level = 8, required_wave = 561 },
    { title_id = "chushen", display_name = "出神入化", icon = "file://{images}/custom_game/titles/series/chushen_v3.png", description = "穿戴后在出战英雄头顶显示。", unlock_condition = "无尽历史最高通关达到641层（第9档）", default_unlocked = false, enabled = true, title_level = 9, required_wave = 641 },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["title_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
