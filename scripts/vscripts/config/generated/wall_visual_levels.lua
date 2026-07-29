-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: wall_visual_levels.csv
local M = {}
M.rows = {
    { level_id = "wall_visual_lv01", level = 1, model_asset_id = "wall_tiny_large_form", enabled = true, notes = "1-1" },
    { level_id = "wall_visual_lv02", level = 2, model_asset_id = "wall_tiny_large_form", enabled = true, notes = "1-2" },
    { level_id = "wall_visual_lv03", level = 3, model_asset_id = "wall_tiny_large_form", enabled = true, notes = "1-3" },
    { level_id = "wall_visual_lv04", level = 4, model_asset_id = "wall_tiny_large_form", enabled = true, notes = "1-4" },
    { level_id = "wall_visual_lv05", level = 5, model_asset_id = "wall_tiny_large_form", enabled = true, notes = "1-5" },
    { level_id = "wall_visual_lv06", level = 6, model_asset_id = "wall_tiny_anthozoan_huge", enabled = true, notes = "2-1" },
    { level_id = "wall_visual_lv07", level = 7, model_asset_id = "wall_tiny_anthozoan_huge", enabled = true, notes = "2-2" },
    { level_id = "wall_visual_lv08", level = 8, model_asset_id = "wall_tiny_anthozoan_huge", enabled = true, notes = "2-3" },
    { level_id = "wall_visual_lv09", level = 9, model_asset_id = "wall_tiny_anthozoan_huge", enabled = true, notes = "2-4" },
    { level_id = "wall_visual_lv10", level = 10, model_asset_id = "wall_tiny_anthozoan_huge", enabled = true, notes = "2-5" },
    { level_id = "wall_visual_lv11", level = 11, model_asset_id = "wall_tiny_stronghold_fortress", enabled = true, notes = "3-1" },
    { level_id = "wall_visual_lv12", level = 12, model_asset_id = "wall_tiny_stronghold_fortress", enabled = true, notes = "3-2" },
    { level_id = "wall_visual_lv13", level = 13, model_asset_id = "wall_tiny_stronghold_fortress", enabled = true, notes = "3-3" },
    { level_id = "wall_visual_lv14", level = 14, model_asset_id = "wall_tiny_stronghold_fortress", enabled = true, notes = "3-4" },
    { level_id = "wall_visual_lv15", level = 15, model_asset_id = "wall_tiny_stronghold_fortress", enabled = true, notes = "3-5" },
    { level_id = "wall_visual_lv16", level = 16, model_asset_id = "wall_tiny_frostmoot_large", enabled = true, notes = "4-1" },
    { level_id = "wall_visual_lv17", level = 17, model_asset_id = "wall_tiny_frostmoot_large", enabled = true, notes = "4-2" },
    { level_id = "wall_visual_lv18", level = 18, model_asset_id = "wall_tiny_frostmoot_large", enabled = true, notes = "4-3" },
    { level_id = "wall_visual_lv19", level = 19, model_asset_id = "wall_tiny_frostmoot_large", enabled = true, notes = "4-4" },
    { level_id = "wall_visual_lv20", level = 20, model_asset_id = "wall_tiny_frostmoot_large", enabled = true, notes = "4-5" },
    { level_id = "wall_visual_lv21", level = 21, model_asset_id = "wall_tiny_astral_origins_back", enabled = true, notes = "5-1" },
    { level_id = "wall_visual_lv22", level = 22, model_asset_id = "wall_tiny_astral_origins_back", enabled = true, notes = "5-2" },
    { level_id = "wall_visual_lv23", level = 23, model_asset_id = "wall_tiny_astral_origins_back", enabled = true, notes = "5-3" },
    { level_id = "wall_visual_lv24", level = 24, model_asset_id = "wall_tiny_astral_origins_back", enabled = true, notes = "5-4" },
    { level_id = "wall_visual_lv25", level = 25, model_asset_id = "wall_tiny_astral_origins_back", enabled = true, notes = "5-5" },
    { level_id = "wall_visual_lv26", level = 26, model_asset_id = "wall_tiny_colossus_monolith", enabled = true, notes = "6-1" },
    { level_id = "wall_visual_lv27", level = 27, model_asset_id = "wall_tiny_colossus_monolith", enabled = true, notes = "6-2" },
    { level_id = "wall_visual_lv28", level = 28, model_asset_id = "wall_tiny_colossus_monolith", enabled = true, notes = "6-3" },
    { level_id = "wall_visual_lv29", level = 29, model_asset_id = "wall_tiny_colossus_monolith", enabled = true, notes = "6-4" },
    { level_id = "wall_visual_lv30", level = 30, model_asset_id = "wall_tiny_colossus_monolith", enabled = true, notes = "6-5" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["level_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
