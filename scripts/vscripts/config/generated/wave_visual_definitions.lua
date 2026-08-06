-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: wave_visual_definitions.csv
local M = {}
M.rows = {
    { wave_number = 1, main_visual_asset_id = "vis_kobold_pack", mini_boss_visual_asset_id = "vis_kobold_foreman", main_scale = 0.9, mini_boss_scale = 1.25, support_every_nth = 0, enabled = true, notes = "荒原兽潮第1波；无运行时领头怪时不会凭视觉计划新增单位" },
    { wave_number = 2, main_visual_asset_id = "vis_giant_wolf", mini_boss_visual_asset_id = "vis_alpha_wolf", main_scale = 0.95, mini_boss_scale = 1.28, support_every_nth = 0, enabled = true, notes = "荒原兽潮第2波；无运行时领头怪时不会凭视觉计划新增单位" },
    { wave_number = 3, main_visual_asset_id = "vis_centaur_courser", mini_boss_visual_asset_id = "vis_centaur_conqueror", main_scale = 0.95, mini_boss_scale = 1.3, support_every_nth = 0, enabled = true, notes = "荒原兽潮第3波；无运行时领头怪时不会凭视觉计划新增单位" },
    { wave_number = 4, main_visual_asset_id = "vis_ogre_bruiser", support_visual_asset_id = "vis_ogre_frostmage", mini_boss_visual_asset_id = "vis_ogre_bruiser", main_scale = 0.92, support_scale = 0.88, mini_boss_scale = 1.32, support_every_nth = 0, enabled = true, notes = "辅助候选已配置；混编比例批准前support_every_nth保持0" },
    { wave_number = 5, main_visual_asset_id = "vis_hellbear", support_visual_asset_id = "vis_hellbear_smasher", mini_boss_visual_asset_id = "vis_hellbear_smasher", stage_boss_visual_asset_id = "vis_spirit_bear_boss", main_scale = 0.95, support_scale = 0.9, mini_boss_scale = 1.35, stage_boss_scale = 1.75, support_every_nth = 0, enabled = true, notes = "阶段Boss仅映射实际assault_boss；辅助比例批准前保持0" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["wave_number"]
    if key ~= nil then M.by_id[key] = row end
end
return M
