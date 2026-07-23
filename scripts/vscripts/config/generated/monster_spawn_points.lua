-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: monster_spawn_points.csv
local M = {}
M.rows = {
    { spawn_point_id = "spawn_wild_boss", hammer_target_name = "monsterborn", current_entity_class = "info_target", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "wild_boss", rebirth_level = 0, archetype_id = "wild_boss_common", enabled = true, notes = "每波怪物从地图中的info_target monsterborn生成。" },
    { spawn_point_id = "spawn_rebirth_01", hammer_target_name = "firstcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 1, archetype_id = "wild_boss_common", enabled = true, notes = "一转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_02", hammer_target_name = "secondcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 2, archetype_id = "wild_boss_common", enabled = true, notes = "二转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_03", hammer_target_name = "thirdcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 3, archetype_id = "wild_boss_common", enabled = true, notes = "三转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_04", hammer_target_name = "fourthcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 4, archetype_id = "wild_boss_common", enabled = true, notes = "四转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_05", hammer_target_name = "fifthcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 5, archetype_id = "wild_boss_common", enabled = true, notes = "五转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_06", hammer_target_name = "sixthcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 6, archetype_id = "wild_boss_common", enabled = true, notes = "六转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_07", hammer_target_name = "seventhcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 7, archetype_id = "wild_boss_common", enabled = true, notes = "七转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_08", hammer_target_name = "eighthcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 8, archetype_id = "wild_boss_common", enabled = true, notes = "八转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_09", hammer_target_name = "ninethcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 9, archetype_id = "wild_boss_common", enabled = true, notes = "九转Boss位置；Hammer名称必须完全一致。" },
    { spawn_point_id = "spawn_rebirth_10", hammer_target_name = "tenthcircle", current_entity_class = "info_player_start_dota", recommended_entity_class = "info_target", team_name = "DOTA_TEAM_BADGUYS", encounter_group = "rebirth_boss", rebirth_level = 10, archetype_id = "wild_boss_common", enabled = true, notes = "十转Boss位置；Hammer名称必须完全一致。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["spawn_point_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
