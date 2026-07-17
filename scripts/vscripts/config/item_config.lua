local M = {
    version = 1,
    items = {
        item_wood_supply_test = {
            itemid = "item_wood_supply_test",
            itemname = "木材补给（测试）",
            itemdesc = "使用后直接增加50木材。当前商品用于验证资源商品发放。",
            iconitem = "item_tango",
            grant_type = "resource",
            grant = {
                wood = 50,
                gold = 0,
                max_population = 0,
            },
        },
        item_survival_token_test = {
            itemid = "item_survival_token_test",
            itemname = "生存代币（测试）",
            itemdesc = "测试用虚拟物品。未来可扩展品质、属性、堆叠与装备字段。",
            iconitem = "item_branches",
            grant_type = "virtual_item",
            stack_count = 1,
        },
    },
}

return M
