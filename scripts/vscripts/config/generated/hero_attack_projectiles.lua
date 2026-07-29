-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_attack_projectiles.csv
local M = {}
M.rows = {
    { hero_id = "hero_axe", enabled = true, notes = "速度为空时按近战攻击处理；攻击距离仍读取英雄表。" },
    { hero_id = "hero_slark", enabled = true, notes = "使用近战攻击能力；攻击距离仍读取英雄表。" },
    { hero_id = "hero_juggernaut", enabled = true, notes = "速度为空时按近战攻击处理；攻击距离仍读取英雄表。" },
    { hero_id = "hero_monkey_king", enabled = true, notes = "无弹道；使用近战攻击能力，攻击距离仍读取英雄表。" },
    { hero_id = "hero_blademaster", enabled = true, notes = "使用近战攻击能力；攻击距离仍读取英雄表。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["hero_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
