local content_catalog = require("config/generated/content_catalog")
local categories = require("config/generated/shop_categories")
local aggregation = require("config/generated/shop_aggregation_rules")
local evaluator = require("systems/shop_condition_evaluator")

local M = {}

local source_cache = {}
local entries = {}
local entries_by_id = {}

local function number(value)
    return tonumber(value) or 0
end

local function load_source(module_name)
    if not source_cache[module_name] then
        source_cache[module_name] =
            require("config/generated/" .. module_name)
    end
    return source_cache[module_name]
end

local function field(row, name, fallback)
    local value = row and row[name]
    if value == nil or value == "" then
        return fallback
    end
    return value
end

local function content_name(content_id, row, rule)
    local catalog = content_catalog.by_id[content_id]
    if catalog and catalog.name and catalog.name ~= "" then
        return catalog.name
    end
    local value = field(row, rule.name_field, "")
    if value ~= "" and value ~= content_id then
        return value
    end
    if row.technology_group and row.level then
        local prefix = row.technology_group == "gold_mine_crit"
            and "金矿暴击率" or "金矿采集效率"
        return prefix .. " Lv." .. tostring(row.level)
    end
    return content_id
end

local function description(content_id, row, rule)
    local catalog = content_catalog.by_id[content_id]
    if catalog and catalog.description
        and catalog.description ~= "" then
        return catalog.description
    end
    return field(row, rule.description_field, row.notes or "")
end

local function condition_text(row)
    local parts = {}
    local function add(value)
        table.insert(parts, value)
    end

    if row.requires_hero_summoned == true then
        add("已召唤英雄")
    end
    if number(row.required_city_level) > 0 then
        add("主城Lv." .. tostring(number(row.required_city_level)))
    end
    if row.requires_vip == true then
        add("VIP权限")
    end
    if number(row.required_rebirth_level) > 0 then
        add("已完成"
            .. tostring(number(row.required_rebirth_level))
            .. "转")
    end
    if row.requires_building_id
        and row.requires_building_id ~= "" then
        add("建筑：" .. row.requires_building_id)
    end
    if row.requires_content_id
        and row.requires_content_id ~= "" then
        add("前置：" .. row.requires_content_id)
    end
    return #parts > 0 and table.concat(parts, " · ") or "无"
end

local function fields_for(row, source_id)
    local result = {}
    local function add(label, value)
        if value ~= nil and value ~= "" then
            table.insert(result, { label = label, value = value })
        end
    end

    if source_id == "weapon" then
        add("系列", row.series_id)
        add("阶段", row.stage)
        add("成长方式", row.progression_type)
        add("成长要求", row.progression_value)
        add("基础攻击", row.base_attack_max)
        add("基础力量", row.base_strength)
        add("基础敏捷", row.base_agility)
        add("基础智力", row.base_intellect)
        add("每次攻击成长", row.attack_gain_per_attack)
    elseif source_id == "item" then
        add("类型", row.item_subtype)
        add("效果", row.effect_type)
        add("效果值", row.effect_value)
    elseif source_id == "technology" then
        add("科技组", row.technology_group)
        add("等级", row.level)
        add("效果", row.effect_type)
        add("效果值", row.effect_value)
    elseif source_id == "rebirth" then
        add("转职等级", row.rebirth_level)
    end
    return result
end

local function make_entry(rule, row)
    local content_id = tostring(field(row, rule.id_field, ""))
    local wood = number(field(row, rule.wood_cost_field, 0))
    local gold = number(field(row, rule.gold_cost_field, 0))
    if content_id == "" or (wood <= 0 and gold <= 0) then
        return nil
    end

    local category_id = field(
        row,
        "shop_category_id",
        rule.category_default
    )
    local icon_type = rule.icon_type_default or "item"
    return {
        entryid = rule.source_id .. ":" .. content_id,
        shopid = category_id,
        contenttype = rule.content_type,
        contentid = content_id,
        name = content_name(content_id, row, rule),
        description = description(content_id, row, rule),
        icon = field(
            row,
            "icon_name",
            icon_type == "ability"
                and "ability_upgrade_wall" or "item_branches"
        ),
        icon_type = icon_type,
        woodcost = wood,
        goldcost = gold,
        visible = true,
        enabled = row.shop_enabled ~= false,
        disabled_reason_text =
            field(row, "disabled_reason_text", ""),
        purchase_limit = number(field(row, "purchase_limit", 0)),
        order = number(field(row, "shop_sort_order", 0)),
        min_city_level =
            number(field(row, "required_city_level", 0)),
        requires_vip = field(row, "requires_vip", false) == true,
        requires_hero_summoned =
            field(row, "requires_hero_summoned", false) == true,
        required_rebirth_level =
            number(field(row, "required_rebirth_level", 0)),
        requires_building_id =
            tostring(field(row, "requires_building_id", "")),
        requires_content_id =
            tostring(field(row, "requires_content_id", "")),
        grant_type = tostring(field(
            row,
            "grant_type",
            rule.grant_type_default or "virtual_item"
        )),
        encounter_id = tostring(field(row, "encounter_id", "")),
        condition_text = condition_text(row),
        fields = fields_for(row, rule.source_id),
        definition = row,
    }
end

local function rebuild()
    source_cache = {}
    entries = {}
    entries_by_id = {}
    for _, rule in ipairs(aggregation.rows or {}) do
        if rule.enabled ~= false then
            for _, row in ipairs(
                load_source(rule.module_name).rows or {}
            ) do
                local entry = make_entry(rule, row)
                if entry then
                    table.insert(entries, entry)
                    entries_by_id[entry.entryid] = entry
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        return a.shopid == b.shopid
            and a.order < b.order
            or a.shopid < b.shopid
    end)
end

function M.find_entry(entry_id)
    return entries_by_id[entry_id]
end

function M.definition_for(entry)
    return entry and entry.definition or nil
end

function M.content_name(entry)
    return entry and entry.name or ""
end

function M.evaluate(player_id, entry, context)
    local ok, reason, count =
        evaluator.evaluate(player_id, entry, context)
    return ok, reason, entry.definition, count
end

local function project_entry(player_id, entry, context)
    local ok, reason, _, count =
        M.evaluate(player_id, entry, context)
    return {
        entry_id = entry.entryid,
        shop_id = entry.shopid,
        content_type = entry.contenttype,
        content_id = entry.contentid,
        grant_type = entry.grant_type,
        name = entry.name,
        description = entry.description,
        icon = entry.icon,
        icon_type = entry.icon_type,
        wood_cost = entry.woodcost,
        gold_cost = entry.goldcost,
        visible = 1,
        purchasable = ok and 1 or 0,
        disabled_reason = reason,
        purchase_condition_text = entry.condition_text,
        owned_count = count,
        purchase_limit = entry.purchase_limit,
        sort_order = entry.order,
        fields = entry.fields,
    }
end

local function projected_categories()
    local result = {}
    for _, category in ipairs(categories.rows or {}) do
        if category.enabled ~= false then
            table.insert(result, {
                shopid = category.category_id,
                shopname = category.name,
                order = tonumber(category.sort_order) or 0,
                description = category.description or "",
            })
        end
    end
    table.sort(result, function(a, b)
        return a.order < b.order
    end)
    return result
end

function M.build_snapshot(player_id, context)
    local projected = {}
    for _, entry in ipairs(entries) do
        table.insert(
            projected,
            project_entry(player_id, entry, context)
        )
    end
    return {
        schema_version = 2,
        sequence = context.sequence,
        config_version = 2,
        player_id = player_id,
        reason = context.reason or "open",
        resources = context.resources or {},
        categories = projected_categories(),
        entries = projected,
    }
end

rebuild()

return M
