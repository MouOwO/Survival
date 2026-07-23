-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: hero_attack_projectiles.csv
local M = {}
M.rows = {
    { hero_id = "hero_axe", enabled = true, notes = "速度为空时按近战攻击处理；攻击距离仍读取英雄表。" },
    { hero_id = "hero_slark", projectile_speed = 900, projectile_model = "particles/units/heroes/hero_drow/drow_base_attack.vpcf", enabled = true, notes = "远程箭矢弹道。" },
    { hero_id = "hero_juggernaut", enabled = true, notes = "速度为空时按近战攻击处理；攻击距离仍读取英雄表。" },
    { hero_id = "hero_monkey_king", projectile_speed = 900, projectile_model = "particles/units/heroes/hero_drow/drow_base_attack.vpcf", enabled = true, notes = "远程箭矢弹道。" },
    { hero_id = "hero_blademaster", projectile_speed = 900, projectile_model = "particles/units/heroes/hero_drow/drow_base_attack.vpcf", enabled = true, notes = "远程箭矢弹道。" },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["hero_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
