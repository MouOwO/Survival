-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_visual_profiles.csv
local M = {}
M.rows = {
    { profile_id = "class_1", core = "bases/death", detail = "bases/detail_death_sr", detail_ssr = "bases/detail_death_ssr", crown = "bases/detail_motes", color = {"146", "80", "230"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.50, enabled = true },
    { profile_id = "class_2", core = "bases/mystery", detail = "bases/detail_mystery_sr", detail_ssr = "bases/detail_mystery_ssr", crown = "bases/detail_motes", color = {"180", "110", "255"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.44, enabled = true },
    { profile_id = "class_3", core = "bases/lightning", detail = "bases/detail_lightning_sr", detail_ssr = "bases/detail_lightning_ssr", crown = "bases/detail_motes", color = {"100", "185", "255"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.54, enabled = true },
    { profile_id = "class_4", core = "bases/machine", detail = "bases/detail_machine_sr", detail_ssr = "bases/detail_machine_ssr", crown = "bases/detail_motes", color = {"255", "174", "72"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.48, enabled = true },
    { profile_id = "class_5", core = "bases/multi", detail = "bases/detail_multi_sr", detail_ssr = "bases/detail_multi_ssr", crown = "bases/detail_motes", color = {"132", "222", "148"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.44, enabled = true },
    { profile_id = "class_6", core = "bases/frost", detail = "bases/detail_frost_sr", detail_ssr = "bases/detail_frost_ssr", crown = "bases/detail_motes", color = {"150", "225", "255"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.50, enabled = true },
    { profile_id = "class_7", core = "bases/anti_air", detail = "bases/detail_anti_air_sr", detail_ssr = "bases/detail_anti_air_ssr", crown = "bases/detail_motes", color = {"130", "222", "234"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.38, enabled = true },
    { profile_id = "ultimate", core = "bases/ultimate", detail = "bases/detail_ultimate", detail_ssr = "bases/detail_ultimate", crown = "bases/detail_motes", color = {"255", "214", "126"}, radius_r = 96, radius_sr = 100, radius_ssr = 112, radius_ur = 128, alpha = 0.56, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["profile_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
