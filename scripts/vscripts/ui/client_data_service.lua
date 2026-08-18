local ability_config = require("config/ability_tooltip_config")
local skill_config = require("config/generated/hero_skill_definitions")
local shop_config = require("config/shop_config")
local item_config = require("config/item_config")
local content_catalog = require("config/generated/content_catalog")
local weapon_config = require("config/generated/weapon_definitions")
local tower_skill_config = require("config/generated/tower_skill_definitions")
local tooltip_config = require("config/generated/tooltip_definitions")
local seven_sins_essences = require("config/seven_sins_essences")
local equipment_levels = require("config/equipment_level_definitions")
local equipment_metadata = require("config/equipment_definitions")
local recipes = require("config/recipe_definitions")
local challenge_materials = require("config/challenge_upgrade_materials")
local logger = require("core/logger")

local M = {}

local ENGINE_ITEM_BY_CONTENT_ID = {
    equipment_attack_gloves_01 = "item_survival_attack_gloves_shell",
    equipment_burning_blade_01 = "item_survival_burning_blade_shell",
    equipment_iron_armor_01 = "item_survival_iron_armor_shell",
    equipment_infernal_armor_01 = "item_survival_infernal_armor_shell",
    material_synthesis_gem = "item_survival_synthesis_gem_shell",
    material_ice_soul_ember = "item_survival_ice_soul_ember_shell",
    item_death_mask = "item_survival_death_mask",
    item_small_polar_crystal = "item_survival_small_polar_crystal",
    item_large_polar_crystal = "item_survival_large_polar_crystal",
}

local ITEM_TYPE_NAMES = {
    main_hand = "主武器",
    accessory = "饰品",
    armor = "护甲",
    crystal = "晶石",
    synthesis_material = "合成材料",
    enhancement_item = "强化装备",
    consumable = "消耗品",
}

local EFFECT_LABELS = {
    all_attributes_flat = "全属性",
    armor_flat = "护甲",
    attack_flat = "攻击力",
    attack_gain_on_attack = "每次普通攻击成长",
    attack_gain_on_player_kill = "每次有效击杀成长",
    attack_speed_pct = "攻击速度",
    attributes_gain_on_attack = "每次普通攻击全属性成长",
    critical_chance_pct = "暴击概率",
    critical_multiplier = "暴击倍率",
    health_flat = "最大生命值",
    lifesteal_pct = "伤害吸血",
}

local PERCENT_EFFECTS = {
    attack_speed_pct = true,
    critical_chance_pct = true,
    lifesteal_pct = true,
}

local SLOT_BY_SUBTYPE = {
    main_weapon = "main_hand",
    accessory = "accessory",
    armor = "armor",
}

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
    for _, definition in ipairs(tooltip_config.rows or {}) do
        if definition.tooltip_type == "ability" and definition.id
            and definition.id ~= "" then
            publish_ability(definition.id, {
                abilityid = definition.id,
                tooltip_id = definition.tooltip_id,
                abilityname = definition.name,
                abilitydesc = definition.desc,
                abilityicon = definition.icon ~= ""
                    and definition.icon or definition.id,
                fields = {
                    { label = "所需木材", value = tonumber(definition.needwood) or 0 },
                    { label = "所需金币", value = tonumber(definition.needgold) or 0 },
                },
            })
        end
    end

    for ability_name, definition in pairs(ability_config) do
        publish_ability(ability_name, definition)
    end

    for _, definition in ipairs(skill_config.rows or {}) do
        if definition.enabled ~= false
            and definition.ability_name
            and definition.ability_name ~= "" then
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

local function content_name(content_id)
    if content_id == "item_death_mask" then return "吸血面罩" end
    local catalog = content_catalog.by_id[content_id] or {}
    local weapon = weapon_config.by_id[content_id] or {}
    return catalog.name or weapon.display_name or tostring(content_id or "")
end

local function item_type(content_id, content, weapon)
    local metadata = equipment_metadata.by_content_id[content_id] or {}
    local slot = weapon.equipment_slot or metadata.slot
        or SLOT_BY_SUBTYPE[tostring(content.content_subtype or "")]
    return ITEM_TYPE_NAMES[slot]
        or ITEM_TYPE_NAMES[tostring(content.content_subtype or "")]
        or "物品"
end

local function format_effect_value(effect_type, value)
    if PERCENT_EFFECTS[effect_type] then
        return "+" .. tostring(value) .. "%"
    end
    if effect_type == "critical_multiplier" then
        return tostring(value) .. "倍伤害"
    end
    return "+" .. tostring(value)
end

local function effect_fields(content_id)
    local level = equipment_levels.by_id[content_id]
    local fields = {}
    for _, effect in ipairs(level and level.effects or {}) do
        local effect_type = tostring(effect.effect_type or "")
        local value = effect.value
        if EFFECT_LABELS[effect_type] and type(value) ~= "table" then
            fields[#fields + 1] = {
                label = EFFECT_LABELS[effect_type],
                value = format_effect_value(effect_type, value),
            }
        elseif effect_type == "aura_attribute_damage" and type(value) == "table" then
            local radius = value.radius or value.range or 0
            local interval = value.interval or value.internal_cooldown or 1
            fields[#fields + 1] = {
                label = "范围光环",
                value = tostring(interval) .. "秒/次，对" .. tostring(radius)
                    .. "范围敌人造成全属性×" .. tostring(value.multiplier or 0)
                    .. "伤害",
            }
        elseif effect_type == "proc_attribute_damage" and type(value) == "table" then
            fields[#fields + 1] = {
                label = "攻击触发",
                value = tostring(value.probability or 0) .. "%概率对"
                    .. tostring(value.range or value.radius or 0)
                    .. "范围敌人造成全属性×" .. tostring(value.multiplier or 0)
                    .. "伤害",
            }
        end
    end
    return fields, level
end

local function recipe_text(recipe)
    local ingredients = {}
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        local quantity = math.max(1, math.floor(tonumber(ingredient.quantity) or 1))
        ingredients[#ingredients + 1] = content_name(ingredient.content_id)
            .. (quantity > 1 and "×" .. tostring(quantity) or "")
    end
    local result_count = math.max(1, math.floor(tonumber(recipe.result_count) or 1))
    return table.concat(ingredients, " + ") .. " → "
        .. content_name(recipe.result_content_id)
        .. (result_count > 1 and "×" .. tostring(result_count) or "")
end

local function recipes_by_ingredient()
    local result = {}
    for _, recipe in ipairs(recipes.rows or {}) do
        if recipe.enabled ~= false then
            for _, ingredient in ipairs(recipe.ingredients or {}) do
                local content_id = tostring(ingredient.content_id or "")
                result[content_id] = result[content_id] or {}
                result[content_id][#result[content_id] + 1] = recipe
            end
        end
    end
    return result
end

local function progression_text(content_id, weapon, level, ingredient_recipes)
    local progression = level and level.progression or nil
    if progression and progression.type == "normal_attack_count" then
        return "进化需求", "完成" .. tostring(progression.required or 0)
            .. "次普通攻击 → " .. content_name(weapon.next_content_id)
    end
    if progression and progression.type == "valid_enemy_kill_count" then
        return "进化需求", "击杀" .. tostring(progression.required or 0)
            .. "个有效敌人 → " .. content_name(weapon.next_content_id)
    end
    if progression and progression.type == "ice_wraith_kill_count" then
        return "进化需求", "击杀" .. tostring(progression.required or 0)
            .. "个冰之幽魂 → " .. content_name("item_large_polar_crystal")
    end
    if tostring(weapon.progression_type or "") == "repeat_purchase"
        and tostring(weapon.next_content_id or "") ~= "" then
        return "升级需求", "再次购买同系列装备 → "
            .. content_name(weapon.next_content_id)
    end
    local recipe_list = ingredient_recipes[content_id] or {}
    if #recipe_list > 0 then
        return "下一段合成", recipe_text(recipe_list[1])
    end
    local series_id = tostring(weapon.series_id or "")
    local stage = tonumber(weapon.stage)
    local max_stage = tonumber(weapon.max_stage)
    if stage ~= nil and max_stage ~= nil and stage >= max_stage then
        return "当前阶段", "已达最高阶段"
    end
    if (series_id == "epic_icefire" or series_id == "legend_abyss")
        and stage ~= nil and tostring(weapon.next_content_id or "") ~= "" then
        local challenge_id = series_id == "epic_icefire" and "challenge_10"
            or "challenge_11"
        local material = challenge_materials.find(challenge_id, stage)
        if material then
            local pickup = material.auto_pickup and "击败对应Boss后自动合成"
                or "击败对应Boss后按F拾取"
            return "下一段合成", content_name(content_id) .. " + "
                .. material.display_name
                .. " → " .. content_name(weapon.next_content_id)
                .. "（" .. pickup .. "）"
        end
    end
    return "", ""
end

local function equipment_description(content_id, content, weapon, has_effects)
    if not has_effects then return content.description or weapon.description or "" end
    local series = tostring(weapon.series_id or "")
    local descriptions = {
        growth_sword = "随普通攻击不断成长的主武器。下列数值为当前阶段实际生效增益。",
        frost_blade = "由成长之剑与吸血面罩合成的进阶主武器，兼具成长与吸血。",
        ice_blade = "由霜之剑刃、极地晶石与合成宝石铸成，以击杀推动进化。",
        attack_gloves = "提升英雄攻击速度的基础装备，可通过重复购买逐级强化。",
        burning_blade = "直接提升英雄攻击力的基础装备，可通过重复购买逐级强化。",
        iron_armor = "提升英雄护甲与最大生命值的防御装备，可通过重复购买逐级强化。",
        infernal_armor = "融合三件满级基础装备而成的合成护甲，兼顾攻防并灼烧附近敌人。",
        epic_icefire = "融合极寒之刃与狱火熔铠而成的史诗主武器，可通过七宗罪阶段材料强化。",
        legend_abyss = "冰火裁决升华而成的传说主武器，可通过罪渊阶段材料继续强化。",
    }
    if descriptions[series] then return descriptions[series] end
    if content_id == "item_death_mask" then
        return "将英雄造成的攻击伤害按比例转化为自身生命值。"
    end
    if content_id == "item_small_polar_crystal"
        or content_id == "item_large_polar_crystal" then
        return "蕴含极寒力量的强化晶石，可提供全属性增益并参与武器合成。"
    end
    return content.description or weapon.description or "装备后持续提供下列增益。"
end

local function publish_content_tooltips()
    local published = {}
    local ingredient_recipes = recipes_by_ingredient()
    for _, definition in ipairs(content_catalog.rows or {}) do
        if definition.content_id and (definition.name or definition.description) then
            local content_id = definition.content_id
            local id = tooltip_id("inventory_item", content_id)
            local standard = (tooltip_config.by_id or {})[id] or {}
            local weapon = weapon_config.by_id[content_id] or {}
            local fields, level = effect_fields(content_id)
            local progression_label, progression = progression_text(
                content_id, weapon, level, ingredient_recipes
            )
            if progression ~= "" then
                fields[#fields + 1] = {
                    label = progression_label,
                    value = progression,
                }
            end
            published[content_id] = {
                content_id = content_id,
                tooltip_id = id,
                name = standard.name or weapon.display_name
                    or definition.name or content_id,
                description = equipment_description(
                    content_id, definition, weapon, #fields > 0
                ),
                item_type = item_type(content_id, definition, weapon),
                level_text = level and ("阶段 " .. tostring(level.level)) or "",
                fields = fields,
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
                    tooltip_id = content.tooltip_id,
                    name = content.name,
                    displayname = content.name,
                    description = content.description,
                    item_type = content.item_type,
                    level_text = content.level_text,
                    fields = content.fields or {},
                }
            )
        end
    end
    for content_id, definition in pairs(published) do
        local tooltip = {
            content_id = content_id,
            tooltip_id = definition.tooltip_id
                or tooltip_id("inventory_item", content_id),
            name = definition.name,
            displayname = definition.name,
            description = definition.description,
            item_type = definition.item_type or "物品",
            level_text = definition.level_text or "",
            fields = definition.fields or {},
        }
        CustomNetTables:SetTableValue(
            "survival_item_tooltips", content_id, tooltip
        )
        local engine_item_name = ENGINE_ITEM_BY_CONTENT_ID[content_id]
        if engine_item_name then
            CustomNetTables:SetTableValue(
                "survival_item_tooltips", engine_item_name, tooltip
            )
        end
    end
    for _, definition in ipairs(seven_sins_essences.rows) do
        local tooltip = {
            content_id = definition.content_id,
            tooltip_id = tooltip_id("inventory_item", definition.content_id),
            name = definition.display_name,
            displayname = definition.display_name,
            description = definition.description,
        }
        CustomNetTables:SetTableValue(
            "survival_item_tooltips", definition.content_id, tooltip
        )
        CustomNetTables:SetTableValue(
            "survival_item_tooltips", definition.engine_item_name, tooltip
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
