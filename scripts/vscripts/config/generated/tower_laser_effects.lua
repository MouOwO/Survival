-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_laser_effects.csv
local M = {}
M.rows = {
    { effect_key = "laser_lv01:default", skill_id = "laser_lv01", particle_name = "particles/units/heroes/hero_tinker/tinker_laser.vpcf", beam_mode = "segmented", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "持续重播相互重叠的激光段；视觉刷新不影响每秒伤害计时。" },
    { effect_key = "laser_lv02:default", skill_id = "laser_lv02", particle_name = "particles/units/heroes/hero_tinker/tinker_laser.vpcf", beam_mode = "segmented", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "持续重播相互重叠的激光段；视觉刷新不影响每秒伤害计时。" },
    { effect_key = "laser_lv03:default", skill_id = "laser_lv03", particle_name = "particles/units/heroes/hero_tinker/tinker_laser.vpcf", beam_mode = "segmented", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "持续重播相互重叠的激光段；视觉刷新不影响每秒伤害计时。" },
    { effect_key = "laser_lv04:default", skill_id = "laser_lv04", particle_name = "particles/units/heroes/hero_tinker/tinker_laser.vpcf", beam_mode = "segmented", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "持续重播相互重叠的激光段；视觉刷新不影响每秒伤害计时。" },
    { effect_key = "laser_lv05:default", skill_id = "laser_lv05", particle_name = "particles/units/heroes/hero_tinker/tinker_laser.vpcf", beam_mode = "segmented", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "持续重播相互重叠的激光段；视觉刷新不影响每秒伤害计时。" },
    { effect_key = "laser_lv05:tower_laser_phoenix_solar", skill_id = "laser_lv05", model_asset_id = "tower_laser_phoenix_solar", particle_name = "particles/units/heroes/hero_tinker/tinker_laser.vpcf", beam_mode = "segmented", attack_point = 0, beam_update_interval = 0.03, visual_refresh_interval = 0.12, visual_segment_duration = 0.18, source_offset_z = 160, target_offset_z = 70, damage_increment_pct = 5, max_damage_multiplier = 5, enabled = true, notes = "Phoenix阶段停用Sun Ray，完整沿用已验证的普通激光塔Tinker Laser视觉与分段生命周期。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["effect_key"]
    if key ~= nil then M.by_id[key] = row end
end
return M
