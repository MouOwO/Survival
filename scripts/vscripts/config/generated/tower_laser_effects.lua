-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_laser_effects.csv
local M = {}
M.rows = {
    { effect_key = "laser_lv01:default", skill_id = "laser_lv01", particle_name = "particles/survival/towers/laser_beam.vpcf", beam_mode = "continuous", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "原生路径算子持续白蓝束芯；单目标仅创建一次；视觉不影响每秒伤害计时。" },
    { effect_key = "laser_lv02:default", skill_id = "laser_lv02", particle_name = "particles/survival/towers/laser_beam.vpcf", beam_mode = "continuous", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "原生路径算子持续白蓝束芯；单目标仅创建一次；视觉不影响每秒伤害计时。" },
    { effect_key = "laser_lv03:default", skill_id = "laser_lv03", particle_name = "particles/survival/towers/laser_beam.vpcf", beam_mode = "continuous", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "原生路径算子持续白蓝束芯；单目标仅创建一次；视觉不影响每秒伤害计时。" },
    { effect_key = "laser_lv04:default", skill_id = "laser_lv04", particle_name = "particles/survival/towers/laser_beam.vpcf", beam_mode = "continuous", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "原生路径算子持续白蓝束芯；单目标仅创建一次；视觉不影响每秒伤害计时。" },
    { effect_key = "laser_lv05:default", skill_id = "laser_lv05", particle_name = "particles/survival/towers/laser_beam.vpcf", beam_mode = "continuous", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "原生路径算子持续白蓝束芯；单目标仅创建一次；视觉不影响每秒伤害计时。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_key"]
    if key ~= nil then M.by_id[key] = row end
end
return M
