local content_catalog = require("config/generated/content_catalog")
local categories = require("config/generated/shop_categories")
local aggregation = require("config/generated/shop_aggregation_rules")
local shop_listings = require("config/generated/shop_entries")
local evaluator = require("systems/shop_condition_evaluator")
local research_config = require("config/research_technology_config")
local research_description = require("research/research_technology_description")
local challenge_runtime_rules = require("config/challenge_runtime_rules")

local M = {}

local source_cache = {}
local entries = {}
local entries_by_id = {}
local listings_by_content_id = {}

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
    if row.name and row.name ~= "" then value = row.name end
    if value ~= "" and value ~= content_id then
        return value
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

local function rebuild_listings()
    listings_by_content_id = {}
    for _, listing in ipairs(shop_listings.rows or {}) do
        if listing.enabled ~= false
            and tostring(listing.content_id or "") ~= "" then
            listings_by_content_id[tostring(listing.content_id)] = listing
        end
    end
end

local function apply_listing(entry)
    local listing = entry and listings_by_content_id[entry.contentid] or nil
    if not listing then return entry end
    if entry.definition and entry.definition.enabled == false then return entry end
    entry.listed_in_shop = true
    entry.entryid = tostring(listing.shop_entry_id)
    entry.shopid = tostring(listing.category_id or entry.shopid)
    entry.name = tostring(listing.display_name or entry.name)
    entry.woodcost = number(listing.wood_cost)
    entry.goldcost = number(listing.gold_cost)
    entry.purchase_limit = number(listing.purchase_limit)
    entry.enabled = true
    return entry
end

local function make_entry(rule, row)
    local content_id = tostring(field(row, rule.id_field, ""))
    local listing = listings_by_content_id[content_id]
    local wood = listing and number(listing.wood_cost)
        or number(field(row, rule.wood_cost_field, 0))
    local gold = listing and number(listing.gold_cost)
        or number(field(row, rule.gold_cost_field, 0))
    local research = research_config.by_legacy_group[row.technology_group]
    local research_cost = research and research_config.cost_for_level(
        research, tonumber(row.level) or 0
    ) or nil
    if research_cost and not listing then
        wood = research_cost.wood
        gold = research_cost.gold
    end
    if content_id == ""
        or (wood <= 0 and gold <= 0) then
        return nil
    end
    if row.progression_type == "repeat_purchase"
        and (tonumber(row.stage) or 0) > 1 then
        return nil
    end

    local category_id = field(
        row,
        "shop_category_id",
        rule.category_default
    )
    local icon_type = rule.icon_type_default or "item"
    return apply_listing({
        entryid = rule.source_id .. ":" .. content_id,
        tooltip_id = "shop_item:" .. rule.source_id .. ":" .. content_id,
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
        purchase_limit = content_id == "item_forging_hammer" and 4 or number(field(row, "purchase_limit", 0)),
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
        technology_track = row.technology_track or "",
        unlock_technology_group = row.unlock_technology_group or "",
        technology_phase = tonumber(row.technology_phase) or 0,
        definition = row,
    })
end

local function rebuild()
    rebuild_listings()
    source_cache = {}
    entries = {}
    entries_by_id = {}
    for _, rule in ipairs(aggregation.rows or {}) do
        if rule.enabled ~= false then
            local source = load_source(rule.module_name)
            if rule.source_id == "challenge" then
                challenge_runtime_rules.apply(source)
            end
            for _, row in ipairs(source.rows or {}) do
                local entry = make_entry(rule, row)
                if entry then
                    table.insert(entries, entry)
                    entries_by_id[entry.entryid] = entry
                end
            end
        end
    end
    local advanced_unlock_entry = make_entry({ source_id="technology_service", content_type="technology_service", id_field="technology_id", name_field="technology_name", description_field="notes", category_default="technology", wood_cost_field="wood_cost", gold_cost_field="gold_cost", grant_type_default="technology_unlock", icon_type_default="ability" }, { technology_id="advanced_researcher_unlock", technology_name="高级研究员服务", notes="主城达到Lv.4后，支付100木材解锁高级研究员科技。", wood_cost=100, gold_cost=0, shop_sort_order=490, required_city_level=4, enabled=true, purchase_limit=1, icon_name="ability_build_research_lab" })
    if advanced_unlock_entry then table.insert(entries, advanced_unlock_entry); entries_by_id[advanced_unlock_entry.entryid] = advanced_unlock_entry end
    table.sort(entries, function(a, b)
        return a.shopid == b.shopid
            and a.order < b.order
            or a.shopid < b.shopid
    end)
end

function M.find_entry(entry_id)
    return entries_by_id[entry_id]
end

function M.listed_in_shop(entry)
    return entry and entry.listed_in_shop == true
end

function M.find_technology_entry(group, level)
    for _, entry in ipairs(entries) do
        local definition = entry.definition or {}
        if entry.contenttype == "technology"
            and definition.technology_group == group
            and tonumber(definition.level) == tonumber(level) then
            return entry
        end
    end
    return nil
end

function M.max_technology_level(group)
    local max_level = 0
    for _, entry in ipairs(entries) do
        local definition = entry.definition or {}
        if entry.contenttype == "technology"
            and definition.technology_group == group then
            max_level = math.max(
                max_level,
                tonumber(definition.level) or 0
            )
        end
    end
    return max_level
end

function M.definition_for(entry)
    return entry and entry.definition or nil
end

function M.content_name(entry)
    return entry and entry.name or ""
end

function M.evaluate(player_id, entry, context)
    local group = entry and entry.definition
        and entry.definition.technology_group or ""
    local authoritative = research_config.by_legacy_group[group] ~= nil
    if authoritative then
        local adjusted = {}
        for key, value in pairs(context or {}) do adjusted[key] = value end
        adjusted.research_service_authoritative = true
        context = adjusted
    end
    local ok, reason, count =
        evaluator.evaluate(player_id, entry, context)
    return ok, reason, entry.definition, count
end

local function project_entry(player_id, entry, context)
    local ok, reason, _, count =
        M.evaluate(player_id, entry, context)
    local item = {
        entry_id = entry.entryid,
        tooltip_id = entry.tooltip_id
            or ("shop_item:" .. entry.entryid),
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
        technology_track = entry.technology_track,
        unlock_technology_group = entry.unlock_technology_group,
        technology_phase = entry.technology_phase,
        technology_level = context.technology_levels and context.technology_levels[player_id] and context.technology_levels[player_id][entry.definition.technology_group] or 0,
        technology_max_level = tonumber(entry.definition.max_level) or 0,
        next_technology_level = tonumber(entry.definition.level) or 0,
        progression_type = entry.definition.progression_type or "",
        series_id = entry.definition.series_id or "",
        stage = tonumber(entry.definition.stage) or 0,
        sort_order = entry.order,
        fields = entry.fields,
        challenge_active = context.active_challenge_encounters
            and context.active_challenge_encounters[entry.encounter_id]
            and 1 or 0,
    }
    if item.challenge_active == 1 then
        item.wood_cost = 0
        item.gold_cost = 0
    end
    local research = research_config.by_legacy_group[
        entry.definition.technology_group
    ]
    if research then
        local target_level = tonumber(item.next_technology_level) or 0
        local current_level = tonumber(item.technology_level) or 0
        local cost = research_config.cost_for_level(research, target_level)
        item.name = research.display_name .. " Lv."
            .. tostring(target_level)
        item.description = research_description.build(
            research,
            current_level,
            target_level
        )
        item.purchase_condition_text = research_description.condition_text(research)
        item.fields = research_description.fields(
            research,
            current_level,
            target_level
        )
        item.technology_max_level = research.max_level
        item.wood_cost = cost and cost.wood or 0
        item.gold_cost = cost and cost.gold or 0
        local required = research.prerequisite or {}
        local levels = context.technology_levels
            and context.technology_levels[player_id] or {}
        local prerequisite_met = not required.tech_id
            or (tonumber(levels[(research_config.by_id[required.tech_id]
                or {}).legacy_group]) or 0) >= (required.required_level or 0)
        local reincarnation_met = (tonumber(context.rebirth_level) or 0)
            >= (required.reincarnation_level or 0)
        local locked_reason = nil
        if target_level ~= current_level + 1
            or current_level >= research.max_level then
            locked_reason = "已达到最高等级"
        elseif not prerequisite_met and context.debug_all_unlocked ~= true then
            locked_reason = "前置科技等级不足"
        elseif not reincarnation_met and context.debug_all_unlocked ~= true then
            locked_reason = "转生等级不足"
        elseif number((context.resources or {}).gold) < item.gold_cost then
            locked_reason = "金币不足"
        elseif number((context.resources or {}).wood) < item.wood_cost then
            locked_reason = "木材不足"
        end
        if item.purchasable == 1 and locked_reason then
            item.purchasable = 0
            item.disabled_reason = locked_reason
        end
    end
    return item
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
        local listed_for_mode = context.ui_mode ~= "shop"
            or entry.listed_in_shop == true
        local item = project_entry(player_id, entry, context)
        -- Challenge entrances remain visible while locked. Players can see
        -- the abyss prerequisite/completion state instead of having its card
        -- disappear before the first run or after the tenth clear.
        -- Resource shortages and purchase limits change availability, not the
        -- shop's structure. Keep ordinary entries projected as disabled cards;
        -- otherwise spending the last resources makes the incremental patch
        -- remove every unaffordable item and leaves the category visually empty.
        local include = item ~= nil
        local group = entry.definition
            and entry.definition.technology_group or ""
        local hero_technology = string.match(
            group,
            "^researcher_hero_"
        ) ~= nil
        local scope_allowed = context.debug_all_unlocked == true
            or context.ui_mode == "research"
            and (entry.contenttype == "technology_service"
                or entry.contenttype == "technology" and not hero_technology)
            or context.ui_mode ~= "research"
                and (entry.contenttype ~= "technology" or hero_technology)
        if entry.contenttype == "technology_service" then
            if context.debug_all_unlocked == true then
                include = true
            elseif entry.contentid == "advanced_researcher_unlock" then
                include = not context.advanced_researcher_unlocked
                    and (tonumber(context.city_level) or 0) >= 4
            else
                include = not context.research_unlocked
                    and (tonumber(context.city_level) or 0) >= 1
            end
        elseif entry.contenttype == "rebirth" then
            -- Always project exactly the next rebirth challenge. Resource or
            -- building failures are shown as a disabled card instead of making
            -- 4-10 rebirth silently disappear from the shop.
            include = context.debug_all_unlocked == true
                or (tonumber(entry.definition.rebirth_level) or 0)
                    == (tonumber(context.rebirth_level) or 0) + 1
        elseif entry.contenttype == "technology" then
            local current = tonumber(item.technology_level) or 0
            local level = tonumber(item.next_technology_level) or 0
            local research = research_config.by_legacy_group[group]
            local phase = tonumber(entry.technology_phase) or 1
            local levels = context.technology_levels
                and context.technology_levels[player_id] or {}
            local prerequisite_level = tonumber(
                levels[entry.unlock_technology_group] or 0
            ) or 0
            local prerequisite_required = tonumber(
                entry.definition.unlock_required_level
            ) or 0
            local prerequisite_ready = research ~= nil
                or entry.technology_track ~= "advanced"
                or prerequisite_level >= prerequisite_required
            local gold_mine_technology =
                entry.definition.technology_group == "gold_mine_efficiency"
                or entry.definition.technology_group == "gold_mine_crit"
            local unlocked = entry.technology_track == "advanced_researcher"
                and context.advanced_researcher_unlocked == true
                or entry.technology_track ~= "advanced_researcher"
                and context.research_unlocked == true
            include = context.debug_all_unlocked == true
                or not gold_mine_technology
                and unlocked
                and prerequisite_ready
                and level == current + 1
                and (research ~= nil
                    or entry.technology_track == "advanced_researcher"
                    or phase == 0
                    or phase == 1 and current < 10
                    or phase == 2 and current >= 10)
        end
        if item and include and scope_allowed and listed_for_mode then
            table.insert(projected, item)
        end
    end
    return {
        schema_version = 2,
        sequence = context.sequence,
        config_version = 2,
        player_id = player_id,
        reason = context.reason or "open",
        resources = context.resources or {},
        categories = context.ui_mode == "research" and {
            {
                shopid = "technology",
                shopname = "建筑与工人科技",
                order = 10,
                description = "研究所科技",
            },
        } or projected_categories(),
        entries = projected,
        ui_mode = context.ui_mode or "shop",
    }
end

rebuild()

return M
