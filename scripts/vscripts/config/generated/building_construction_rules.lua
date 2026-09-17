-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: building_construction_rules.csv
local M = {}
M.rows = {
    { building_id = "wall", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "main_city", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "arrow_tower", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "building_farm", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "building_research_lab", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "building_challenge", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "building_advanced_research_lab", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "gold_mine", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
    { building_id = "hero_altar", build_cast_range = 200, build_time = 3, build_particle = "particles/survival_buildings/white_build_channel.vpcf", build_loop_particle = "particles/survival_buildings/white_build_channel.vpcf", build_visual_scale = 1.0, enabled = true, notes = "稳定白光建筑轮廓；完成后白光平滑褪去；无循环光环与闪光。", build_complete_particle = "particles/survival_buildings/white_build_reveal.vpcf" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["building_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
