-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_skill_pool_members.csv
local M = {}
M.rows = {
    { pool_member_id = "public_01", pool_id = "public_pool", skill_id = "proto_flame_burst", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_02", pool_id = "public_pool", skill_id = "proto_frost_nova", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_03", pool_id = "public_pool", skill_id = "proto_chain_lightning", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_04", pool_id = "public_pool", skill_id = "proto_poison_cloud", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_05", pool_id = "public_pool", skill_id = "proto_blade_nova", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_06", pool_id = "public_pool", skill_id = "proto_earth_line", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_07", pool_id = "public_pool", skill_id = "proto_meteor", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_08", pool_id = "public_pool", skill_id = "proto_arcane_barrage", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_09", pool_id = "public_pool", skill_id = "proto_magic_slingshot", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_10", pool_id = "public_pool", skill_id = "proto_holy_pulse", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_11", pool_id = "public_pool", skill_id = "proto_ice_cone", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_12", pool_id = "public_pool", skill_id = "proto_void_pulse", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
    { pool_member_id = "public_13", pool_id = "public_pool", skill_id = "proto_echo_slash", weight = 100, min_rebirth_level = 2, max_rebirth_level = 10, enabled = true, notes = "二转及以后公共随机池。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["pool_member_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
