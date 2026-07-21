local ability_config = require("config/ability_tooltip_config")
local skill_config = require("config/generated/hero_skill_definitions")
local shop_config = require("config/shop_config")
local item_config = require("config/item_config")
local content_catalog = require("config/generated/content_catalog")
local weapon_config = require("config/generated/weapon_definitions")
local tower_skill_config = require("config/generated/tower_skill_definitions")
local tooltip_config = require("config/generated/tooltip_definitions")
local logger = require("core/logger")

local M = {}

local function tooltip_id(tooltip_type, id)
    return tooltip_type .. ":" .. tostring(id or "")
end

local function publish_tooltips()
    for _, definition in ipairs(tooltip_config.rows or {}) do
        CustomNetTables:SetTableValue(
            "survival_tooltips",
            definition.tooltip_id,
            definition
        )
    end
end

local function publish_ability(ability_name, definition)
    CustomNetTables:SetTableValue(
        "survival_ability_data",
        ability_name,
        {
            abilityid = definition.abilityid or ability_name,
            tooltip_id = definition.tooltip_id
                or tooltip_id("ability", ability_name),
            abilityname = definition.abilityname or ability_name,
            abilitydesc = definition.abilitydesc or "",
            abilityicon = definition.abilityicon or ability_name,
            skill_type = definition.skill_type or definition.trigger_type or "",
            is_active = definition.is_active == true and 1 or 0,
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
                skill_type = definition.skill_type or "",
                is_active = definition.skill_type == "active" and 1 or 0,
                fields = {
                    { label = "最高等级", value = tonumber(definition.max_level) or 1 },
                    { label = "每级效果", value = tonumber(definition.effect_value_per_level) or 0 },
                },
            })
        end
    end
    for _, definition in ipairs(tower_skill_config.rows or {}) do
        if definition.enabled ~= false then
            publish_ability(definition.skill_id, {
                abilityid = definition.skill_id,
                abilityname = definition.skill_name,
                abilitydesc = definition.description,
                abilityicon = definition.ability_icon
                    or "drow_ranger_marksmanship",
                skill_type = definition.trigger_type or "passive",
                is_active = 0,
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

local function publish_content_tooltips()
    local published = {}
    for _, definition in ipairs(content_catalog.rows or {}) do
        if definition.content_id and (definition.name or definition.description) then
            published[definition.content_id] = {
                content_id = definition.content_id,
                name = definition.name or definition.content_id,
                description = definition.description or "",
            }
        end
    end
    for _, definition in ipairs(weapon_config.rows or {}) do
        if definition.engine_item_name then
            local content = published[definition.content_id] or {}
            CustomNetTables:SetTableValue(
                "survival_item_tooltips",
                definition.engine_item_name,
                {
                    content_id = definition.content_id,
                    tooltip_id = tooltip_id(
                        "inventory_item",
                        definition.content_id
                    ),
                    name = content.name or definition.content_id,
                    description = content.description
                        or definition.description or "",
                }
            )
        end
    end
    for content_id, definition in pairs(published) do
        CustomNetTables:SetTableValue(
            "survival_item_tooltips",
            content_id,
            {
                content_id = definition.content_id,
                tooltip_id = tooltip_id("inventory_item", content_id),
                name = definition.name,
                description = definition.description,
            }
        )
    end
end

local function publish_weapon_ui_schema()
    -- Static protocol metadata is published here; player state remains owned
    -- by weapon_synthesis_snapshot_service.
    CustomNetTables:SetTableValue("survival_weapon_ui_schema", "root", {
        version = 1,
        snapshot_table = "survival_weapon_snapshot",
        recipe_table = "survival_weapon_recipes",
        effects_table = "survival_weapon_effects",
        request_event = "ui_weapon_synthesis_request",
        snapshot_event = "ui_weapon_snapshot_request",
    })
end

function M.init()
    publish_tooltips()
    publish_abilities()
    publish_shop()
    publish_items()
    publish_content_tooltips()
    publish_weapon_ui_schema()
    logger.info(
        "ClientDataService",
        "tooltip, ability, hero skill, shop and item data published"
    )
end

return M
