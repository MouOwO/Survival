-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: monster_spawn_points.csv
local M = {}
M.rows = {
    { spawn_point_id = "spawn_rebirth_01", hammer_target_name = "rebirth_01_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 1, archetype_id = "rebirth_boss_01", enabled = true, notes = "一转Boss位置；英雄入口为rebirth_01_entry。" },
    { spawn_point_id = "spawn_rebirth_02", hammer_target_name = "rebirth_02_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 2, archetype_id = "rebirth_boss_02", enabled = true, notes = "二转Boss位置；英雄入口为rebirth_02_entry。" },
    { spawn_point_id = "spawn_rebirth_03", hammer_target_name = "rebirth_03_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 3, archetype_id = "rebirth_boss_03", enabled = true, notes = "三转Boss位置；英雄入口为rebirth_03_entry。" },
    { spawn_point_id = "spawn_rebirth_04", hammer_target_name = "rebirth_04_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 4, archetype_id = "rebirth_boss_04", enabled = true, notes = "四转Boss位置；英雄入口为rebirth_04_entry。" },
    { spawn_point_id = "spawn_rebirth_05", hammer_target_name = "rebirth_05_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 5, archetype_id = "rebirth_boss_05", enabled = true, notes = "五转Boss位置；英雄入口为rebirth_05_entry。" },
    { spawn_point_id = "spawn_rebirth_06", hammer_target_name = "rebirth_06_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 6, archetype_id = "rebirth_boss_06", enabled = true, notes = "六转Boss位置；英雄入口为rebirth_06_entry。" },
    { spawn_point_id = "spawn_rebirth_07", hammer_target_name = "rebirth_07_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 7, archetype_id = "rebirth_boss_07", enabled = true, notes = "七转Boss位置；英雄入口为rebirth_07_entry。" },
    { spawn_point_id = "spawn_rebirth_08", hammer_target_name = "rebirth_08_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 8, archetype_id = "rebirth_boss_08", enabled = true, notes = "八转Boss位置；英雄入口为rebirth_08_entry。" },
    { spawn_point_id = "spawn_rebirth_09", hammer_target_name = "rebirth_09_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 9, archetype_id = "rebirth_boss_09", enabled = true, notes = "九转Boss位置；英雄入口为rebirth_09_entry。" },
    { spawn_point_id = "spawn_rebirth_10", hammer_target_name = "rebirth_10_boss_spawn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 10, archetype_id = "rebirth_boss_10", enabled = true, notes = "十转Boss位置；英雄入口为rebirth_10_entry。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["spawn_point_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
