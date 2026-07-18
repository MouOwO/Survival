local ability_config = require("config/ability_tooltip_config")
local skill_config = require("config/generated/hero_skill_definitions")
local shop_config = require("config/shop_config")
local item_config = require("config/item_config")
local logger = require("core/logger")

local M = {}

local function publish_ability(ability_name, definition)
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

local function publish_abilities()
    for ability_name, definition in pairs(ability_config) do
        publish_ability(ability_name, definition)
    end

    for _, definition in ipairs(skill_config.rows or {}) do
        if definition.enabled ~= false then
            publish_ability(definition.ability_name, {
                abilityid = definition.ability_name,
                abilityname = definition.display_name,
                abilitydesc = definition.description,
                abilityicon = definition.icon_name,
                fields = {
                    {
                        label = "最高等级",
                        value = tonumber(definition.max_level) or 1,
                    },
                    {
                        label = "每级效果",
                        value = tonumber(
                            definition.effect_value_per_level
                        ) or 0,
                    },
                },
            })
        end
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
    logger.info(
        "ClientDataService",
        "ability, hero skill, shop and item data published"
    )
end

return M
