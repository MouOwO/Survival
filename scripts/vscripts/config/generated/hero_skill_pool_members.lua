-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_skill_pool_members.csv
local M = {}
M.rows = {
    { pool_member_id = "public_01", pool_id = "public_pool", skill_id = "skill_power_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_02", pool_id = "public_pool", skill_id = "skill_vitality_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_03", pool_id = "public_pool", skill_id = "skill_agility_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_04", pool_id = "public_pool", skill_id = "skill_intellect_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_05", pool_id = "public_pool", skill_id = "skill_armor_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_06", pool_id = "public_pool", skill_id = "skill_attack_speed_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_07", pool_id = "public_pool", skill_id = "skill_move_speed_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_08", pool_id = "public_pool", skill_id = "skill_attack_range_training", weight = 80, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_09", pool_id = "public_pool", skill_id = "skill_health_regen_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_10", pool_id = "public_pool", skill_id = "skill_mana_regen_training", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_member_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
