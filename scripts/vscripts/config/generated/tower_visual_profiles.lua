-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_visual_profiles.csv
local M = {}
M.rows = {
    { profile_id = "class_1", core = "death", detail = "detail_runes", crown = "detail_motes", color = {"146", "80", "230"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.55, enabled = true },
    { profile_id = "class_2", core = "mystery", detail = "detail_runes", crown = "detail_motes", color = {"180", "110", "255"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.48, enabled = true },
    { profile_id = "class_3", core = "lightning", detail = "detail_runes", crown = "detail_motes", color = {"100", "185", "255"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.62, enabled = true },
    { profile_id = "class_4", core = "machine", detail = "detail_runes", crown = "detail_motes", color = {"255", "174", "72"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.55, enabled = true },
    { profile_id = "class_5", core = "multi", detail = "detail_runes", crown = "detail_motes", color = {"132", "222", "148"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.48, enabled = true },
    { profile_id = "class_6", core = "frost", detail = "detail_runes", crown = "detail_motes", color = {"150", "225", "255"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.58, enabled = true },
    { profile_id = "class_7", core = "anti_air", detail = "detail_runes", crown = "detail_motes", color = {"130", "222", "234"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.52, enabled = true },
    { profile_id = "ultimate", core = "ultimate", detail = "detail_runes", crown = "detail_motes", color = {"255", "214", "126"}, radius_r = 96, radius_sr = 112, radius_ssr = 128, radius_ur = 144, alpha = 0.65, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["profile_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
