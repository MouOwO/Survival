local ability_config = require("config/ability_tooltip_config")
local shop_config = require("config/shop_config")
local item_config = require("config/item_config")
local logger = require("core/logger")

local M = {}

local function publish_abilities()
    for ability_name, definition in pairs(ability_config) do
        CustomNetTables:SetTableValue(
            "survival_ability_data",
            ability_name,
            {
                abilityid = definition.abilityid or ability_name,
                abilityname = definition.abilityname or ability_name,
                abilitydesc = definition.abilitydesc or "",
                abilityicon = definition.abilityicon or ability_name,
                fields = definition.fields or {},
            }
        )
    end
end

local function publish_shop()
    CustomNetTables:SetTableValue(
        "survival_shop_config",
        "root",
        shop_config
    )
end

local function publish_items()
    local item_ids = {}
    for item_id, definition in pairs(item_config.items or {}) do
        table.insert(item_ids, item_id)
        CustomNetTables:SetTableValue(
            "survival_item_config",
            item_id,
            definition
        )
    end
    table.sort(item_ids)
    CustomNetTables:SetTableValue(
        "survival_item_config",
        "root",
        {
            version = item_config.version or 1,
            itemids = item_ids,
        }
    )
end

function M.init()
    publish_abilities()
    publish_shop()
    publish_items()
    logger.info("ClientDataService", "ability, shop and item data published")
end

return M
