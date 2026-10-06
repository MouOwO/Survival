-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_visual_profiles.csv
local M = {}
M.rows = {
    { profile_id = "class_1", color = {"25", "219", "241"}, radius_r = 96, radius_sr = 108, radius_ssr = 120, radius_ur = 128, alpha = 0.95, enabled = true, native_base = "willow_shadow_realm", color_r = {"25", "219", "241"}, color_sr = {"180", "95", "255"}, color_ssr = {"255", "52", "83"} },
    { profile_id = "class_2", color = {"145", "115", "235"}, radius_r = 96, radius_sr = 108, radius_ssr = 120, radius_ur = 128, alpha = 0.95, enabled = true, native_base = "leshrac_edict" },
    { profile_id = "class_3", color = {"95", "155", "240"}, radius_r = 96, radius_sr = 108, radius_ssr = 120, radius_ur = 128, alpha = 0.95, enabled = true, native_base = "kinetic_markers" },
    { profile_id = "class_4", color = {"215", "145", "70"}, radius_r = 96, radius_sr = 108, radius_ssr = 120, radius_ur = 128, alpha = 0.95, enabled = false, native_base = "bulldoze" },
    { profile_id = "class_5", color = {"220", "85", "50"}, radius_r = 96, radius_sr = 108, radius_ssr = 120, radius_ur = 128, alpha = 0.95, enabled = true, native_base = "clinkz_embers" },
    { profile_id = "class_6", color = {"110", "175", "235"}, radius_r = 96, radius_sr = 108, radius_ssr = 120, radius_ur = 128, alpha = 0.95, enabled = true, native_base = "ice_vortex" },
    { profile_id = "class_7", color = {"135", "175", "235"}, radius_r = 96, radius_sr = 108, radius_ssr = 120, radius_ur = 128, alpha = 0.95, enabled = true, native_base = "psionic_trap" },
    { profile_id = "ultimate", core = "bases/ultimate", detail = "bases/detail_ultimate", detail_ssr = "bases/detail_ultimate", crown = "bases/detail_motes", color = {"255", "214", "126"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.38, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["profile_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
