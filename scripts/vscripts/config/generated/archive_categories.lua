-- AUTO-GENERATED. DO NOT EDIT THIS LUA FILE DIRECTLY.
-- Source: archive_categories.csv
local M = {}
M.rows = {
    { category_id = "endless", display_name = "无尽存档", renderer = "achievements", sort_order = 60, enabled = true },
    { category_id = "clear", display_name = "通关存档", renderer = "achievements", sort_order = 10, enabled = true },
    { category_id = "shadow", display_name = "破碎之影", renderer = "inventory", sort_order = 20, enabled = true },
    { category_id = "points", display_name = "积分道具", renderer = "inventory", sort_order = 30, enabled = true },
    { category_id = "map_level", display_name = "地图等级", renderer = "achievements", sort_order = 41, enabled = true },
    { category_id = "work", display_name = "上班福利", renderer = "upgrades", sort_order = 51, enabled = true },
    { category_id = "gift", display_name = "福利礼包", renderer = "achievements", sort_order = 32, enabled = true },
    { category_id = "fragment", display_name = "神兵碎片", renderer = "inventory", sort_order = 40, enabled = true },
    { category_id = "pet", display_name = "秘法牢笼", renderer = "inventory", sort_order = 50, enabled = true },
    { category_id = "boss", display_name = "boss存档", renderer = "achievements", sort_order = 90, enabled = true },
    { category_id = "shop", display_name = "商城道具", renderer = "placeholder", sort_order = 100, enabled = false },
    { category_id = "friend", display_name = "动漫挑战", renderer = "collection", sort_order = 61, enabled = true },
    { category_id = "ex", display_name = "二次元挑战", renderer = "collection", sort_order = 62, enabled = true },
    { category_id = "beast", display_name = "祥瑞挑战", renderer = "collection", sort_order = 63, enabled = true },
    { category_id = "fishing", display_name = "钓鱼存档", renderer = "inventory", sort_order = 64, enabled = true },
    { category_id = "building", display_name = "存档神器", renderer = "upgrades", sort_order = 65, enabled = true },
    { category_id = "starjoy_points", display_name = "曙光积分", renderer = "achievements", sort_order = 31, enabled = true },
    { category_id = "titles", display_name = "称号", renderer = "titles", sort_order = 33, enabled = true },
    { category_id = "wife", display_name = "二次元挑战2", renderer = "collection", sort_order = 66, enabled = true },
    { category_id = "commerce_goods", display_name = "商城道具", renderer = "commerce_goods", sort_order = 99, enabled = true },
    { category_id = "concubine", display_name = "我的侍妾", renderer = "collection", sort_order = 67, enabled = true },
}
M.by_id = {}
for _, row in ipairs(M.rows) do
    local key = row["category_id"]
    if key ~= nil then M.by_id[key] = row end
end
return M
