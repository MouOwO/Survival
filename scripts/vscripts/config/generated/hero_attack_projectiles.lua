-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_attack_projectiles.csv
local M = {}
M.rows = {
    { hero_id = "hero_doom", enabled = true, notes = "近战攻击；攻击距离读取英雄表。" },
    { hero_id = "hero_shadow_fiend", projectile_speed = 900, projectile_model = "particles/units/heroes/hero_nevermore/nevermore_base_attack.vpcf", enabled = true, notes = "远程攻击弹道。" },
    { hero_id = "hero_axe", enabled = true, notes = "近战攻击；攻击距离读取英雄表。" },
    { hero_id = "hero_drow_ranger", projectile_speed = 1250, projectile_model = "particles/units/heroes/hero_drow/drow_base_attack.vpcf", enabled = true, notes = "远程攻击弹道。" },
    { hero_id = "hero_monkey_king", enabled = true, notes = "无弹道；使用近战攻击能力，攻击距离仍读取英雄表。" },
    { hero_id = "hero_blademaster", enabled = true, notes = "使用近战攻击能力；攻击距离仍读取英雄表。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["hero_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
