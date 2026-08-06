-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: monster_visual_assets.csv
local M = {}
M.rows = {
    { visual_asset_id = "vis_kobold_pack", display_name = "狗头人群", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_kobold/kobold_a/n_creep_kobold_a.vmdl", async_unit_name = "asset_proxy_wave_vis_kobold_pack", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第1波普通怪；本机VPK已确认完整模型" },
    { visual_asset_id = "vis_kobold_foreman", display_name = "狗头人工头", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_kobold/kobold_c/n_creep_kobold_c.vmdl", async_unit_name = "asset_proxy_wave_vis_kobold_foreman", fallback_visual_asset_id = "vis_kobold_pack", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第1波小Boss；本机VPK已确认完整模型" },
    { visual_asset_id = "vis_giant_wolf", display_name = "巨狼", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_worg_small/n_creep_worg_small.vmdl", async_unit_name = "asset_proxy_wave_vis_giant_wolf", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第2波普通怪；本机VPK已确认完整模型" },
    { visual_asset_id = "vis_alpha_wolf", display_name = "头狼", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_worg_large/n_creep_worg_large.vmdl", async_unit_name = "asset_proxy_wave_vis_alpha_wolf", fallback_visual_asset_id = "vis_giant_wolf", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第2波小Boss；本机VPK已确认完整模型" },
    { visual_asset_id = "vis_centaur_courser", display_name = "半人马战士", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_centaur_med/n_creep_centaur_med.vmdl", async_unit_name = "asset_proxy_wave_vis_centaur_courser", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第3波普通怪；本机VPK已确认完整模型" },
    { visual_asset_id = "vis_centaur_conqueror", display_name = "半人马征服者", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_centaur_lrg/n_creep_centaur_lrg.vmdl", async_unit_name = "asset_proxy_wave_vis_centaur_conqueror", fallback_visual_asset_id = "vis_centaur_courser", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第3波小Boss；本机VPK已确认完整模型" },
    { visual_asset_id = "vis_ogre_bruiser", display_name = "食人魔重兵", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_ogre_lrg/n_creep_ogre_lrg.vmdl", async_unit_name = "asset_proxy_wave_vis_ogre_bruiser", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第4波普通怪；本机VPK已确认完整模型" },
    { visual_asset_id = "vis_ogre_frostmage", display_name = "食人魔霜法师", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_ogre_med/n_creep_ogre_med.vmdl", async_unit_name = "asset_proxy_wave_vis_ogre_frostmage", fallback_visual_asset_id = "vis_ogre_bruiser", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第4波辅助候选；混编比例批准前不启用实例分配" },
    { visual_asset_id = "vis_hellbear", display_name = "地狱熊", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_furbolg/n_creep_furbolg_disrupter.vmdl", async_unit_name = "asset_proxy_wave_vis_hellbear", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第5波普通怪；本机VPK仅确认这一套自包含地狱熊主体" },
    { visual_asset_id = "vis_hellbear_smasher", display_name = "地狱熊粉碎者", assembly_mode = "direct_model", model_path = "models/creeps/neutral_creeps/n_creep_furbolg/n_creep_furbolg_disrupter.vmdl", async_unit_name = "asset_proxy_wave_vis_hellbear", fallback_visual_asset_id = "vis_hellbear", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第5波小Boss；与普通型共享主体并由波次缩放区分" },
    { visual_asset_id = "vis_spirit_bear_boss", display_name = "荒原巨灵熊", assembly_mode = "direct_model", model_path = "models/heroes/lone_druid/spirit_bear.vmdl", async_unit_name = "asset_proxy_wave_vis_spirit_bear_boss", fallback_visual_asset_id = "vis_hellbear_smasher", verified_source = "local_pak01_dir_vpk", enabled = true, notes = "第5波阶段Boss；本机VPK已确认独立召唤物模型" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["visual_asset_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
