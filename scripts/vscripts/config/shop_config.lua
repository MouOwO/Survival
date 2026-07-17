local M = {
    version = 3,

    categories = {
        {
            shopid = "items",
            shopname = "物品",
            order = 1,
        },
        {
            shopid = "technologies",
            shopname = "科技",
            order = 2,
        },
    },

    entries = {
        {
            entryid = "shop_wood_supply_test",
            shopid = "items",
            contenttype = "item",
            contentid = "item_wood_supply_test",
            woodcost = 0,
            goldcost = 10,
            itemdesc = "支付10金币，获得50木材。当前用于验证服务端商店快照和购买闭环。",
            purchase_limit = 0,
            condition_text = "无额外条件",
            order = 1,
            visible = true,
            enabled = true,
            fields = {
                { label = "发放类型", value = "服务器资源" },
            },
        },
        {
            entryid = "shop_survival_token_test",
            shopid = "items",
            contenttype = "item",
            contentid = "item_survival_token_test",
            woodcost = 25,
            goldcost = 0,
            itemdesc = "支付25木材，获得1个测试代币。代币暂存于服务器虚拟物品状态。",
            purchase_limit = 0,
            condition_text = "无额外条件",
            order = 2,
            visible = true,
            enabled = true,
            fields = {
                { label = "发放类型", value = "虚拟物品" },
            },
        },
        {
            entryid = "shop_wall_armor_technology_test",
            shopid = "technologies",
            contenttype = "technology",
            contentid = "tech_wall_armor_test",
            woodcost = 100,
            goldcost = 50,
            itemdesc = "科技购买接口测试项。需要主城达到2级。",
            purchase_limit = 1,
            min_city_level = 2,
            condition_text = "需要主城等级2",
            order = 1,
            visible = true,
            enabled = true,
            fields = {
                { label = "最高等级", value = "1" },
                { label = "当前作用", value = "仅记录测试状态" },
            },
        },
    },
}

-- Backward-compatible alias for code that still reads `shops`.
M.shops = M.categories

return M
