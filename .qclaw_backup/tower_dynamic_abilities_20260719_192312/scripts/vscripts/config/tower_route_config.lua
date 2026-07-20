local modules = {
    class_1 = require("config/generated/tower_class_death"),
    class_2 = require("config/generated/tower_class_mystery"),
    class_3 = require("config/generated/tower_class_lightning"),
    class_4 = require("config/generated/tower_class_machine_gun"),
    class_5 = require("config/generated/tower_class_multi"),
    class_6 = require("config/generated/tower_class_frost"),
    class_7 = require("config/generated/tower_class_anti_air"),
}

local M = {}

function M.get_route(class_id)
    local module = modules[class_id]
    return module and module.rows or nil
end

function M.get(class_id, route_index)
    local route = M.get_route(class_id)
    return route and route[route_index] or nil
end

function M.display_name(row)
    if not row then return "" end
    if not row.rarity or row.rarity == "" then return row.name end
    return "【" .. row.rarity .. "】" .. row.name
end

return M
