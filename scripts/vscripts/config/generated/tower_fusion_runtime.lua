-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: tower_fusion_runtime.csv
local M = {}
M.rows = {
    { config_id = "ultimate_tower", route_ids = {"class_1", "class_2", "class_3", "class_4", "class_5", "class_6", "class_7"}, unit_name = "npc_dota_unit_ultimate_tower", display_name = "终极之塔", model_name = "models/creeps/roshan/roshan.vmdl", base_attack_multiplier = 3, passive_slot_ability_ids = {"ultimate_tower_passive_1", "ultimate_tower_passive_2", "ultimate_tower_passive_3", "ultimate_tower_passive_4", "ultimate_tower_passive_5", "ultimate_tower_passive_6", "ultimate_tower_passive_7"}, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["config_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
