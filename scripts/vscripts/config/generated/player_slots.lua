-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: player_slots.csv
local M = {}
M.rows = {
    { slot_id = "east", player_id = 0, display_name = "东区", builder_spawn_marker = "player_0_builder_spawn", wave_spawn_marker = "monsterborn", legacy_builder_x = 0, legacy_builder_y = 0, legacy_builder_z = 256, allow_legacy_builder_fallback = true, enabled = true, notes = "玩家0兼容当前单人地图；Hammer补齐marker后自动优先使用marker。" },
    { slot_id = "south", player_id = 1, display_name = "南区", builder_spawn_marker = "player_1_builder_spawn", wave_spawn_marker = "player_1_wave_spawn", legacy_builder_x = 0, legacy_builder_y = 0, legacy_builder_z = 256, allow_legacy_builder_fallback = false, enabled = true, notes = "缺少marker时失败关闭，禁止与玩家0重叠出生。" },
    { slot_id = "west", player_id = 2, display_name = "西区", builder_spawn_marker = "player_2_builder_spawn", wave_spawn_marker = "player_2_wave_spawn", legacy_builder_x = 0, legacy_builder_y = 0, legacy_builder_z = 256, allow_legacy_builder_fallback = false, enabled = true, notes = "缺少marker时失败关闭，禁止与其他玩家重叠出生。" },
    { slot_id = "north", player_id = 3, display_name = "北区", builder_spawn_marker = "player_3_builder_spawn", wave_spawn_marker = "player_3_wave_spawn", legacy_builder_x = 0, legacy_builder_y = 0, legacy_builder_z = 256, allow_legacy_builder_fallback = false, enabled = true, notes = "缺少marker时失败关闭，禁止与其他玩家重叠出生。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["slot_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
