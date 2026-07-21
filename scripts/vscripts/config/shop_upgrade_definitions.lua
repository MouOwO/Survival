-- 商店只声明可购买的起点与升级策略；未声明内容不可购买。
local M = {}
M.entries = {
    { entry_id = "shop_growth_sword_01", content_id = "weapon_growth_sword_01", category = "weapon", wood_cost = 0, gold_cost = 100, purchase_limit = 1, enabled = true, price_source = "generated.shop_entries" },
    { entry_id = "shop_attack_gloves_01", content_id = "equipment_attack_gloves_01", category = "weapon", wood_cost = 0, gold_cost = 200, purchase_limit = 5, upgrade = "repeat_purchase", enabled = true, price_source = "generated.shop_entries" },
    { entry_id = "shop_burning_blade_01", content_id = "equipment_burning_blade_01", category = "weapon", wood_cost = 0, gold_cost = 200, purchase_limit = 5, upgrade = "repeat_purchase", enabled = true, price_source = "generated.shop_entries" },
    { entry_id = "shop_iron_armor_01", content_id = "equipment_iron_armor_01", category = "weapon", wood_cost = 0, gold_cost = 200, purchase_limit = 5, upgrade = "repeat_purchase", enabled = true, price_source = "generated.shop_entries" },
    { entry_id = "shop_death_mask", content_id = "item_death_mask", category = "item", wood_cost = 10000, gold_cost = 300, purchase_limit = 1, enabled = true, alias_name = "吸血面罩", price_source = "generated.shop_entries" },
    { entry_id = "shop_small_polar_crystal", content_id = "item_small_polar_crystal", category = "item", wood_cost = 0, gold_cost = 1000, purchase_limit = 1, enabled = true, price_source = "generated.shop_entries" },
    { entry_id = "shop_large_polar_crystal", content_id = "item_large_polar_crystal", category = "item", wood_cost = 0, gold_cost = 1000, purchase_limit = 1, enabled = true, price_source = "generated.item_definitions", notes = "原商城提供；不采用候选表的未知零价。" },
}
M.by_content_id = {}
for _, row in ipairs(M.entries) do M.by_content_id[row.content_id] = row end
return M
