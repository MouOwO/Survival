local shop_config = require("config/shop_config")
local item_config = require("config/item_config")
local technology_config = require("config/technology_config")

local M = {}

function M.find_entry(entry_id)
    for _, entry in ipairs(shop_config.entries or {}) do
        if entry.entryid == entry_id then return entry end
    end
    return nil
end

function M.definition_for(entry)
    if entry.contenttype == "technology" then
        return technology_config.technologies
            and technology_config.technologies[entry.contentid] or nil
    end
    return item_config.items and item_config.items[entry.contentid] or nil
end

function M.content_name(entry, definition)
    if entry.contenttype == "technology" then
        return definition.technologyname or entry.contentid
    end
    return definition.itemname or entry.contentid
end

local function content_description(entry, definition)
    if entry.itemdesc and entry.itemdesc ~= "" then return entry.itemdesc end
    if entry.contenttype == "technology" then
        return definition.technologydesc or ""
    end
    return definition.itemdesc or ""
end

local function content_icon(entry, definition)
    if entry.contenttype == "technology" then
        return definition.iconability or "ability_upgrade_wall", "ability"
    end
    return definition.iconitem or "item_branches", "item"
end

function M.evaluate(player_id, entry, context)
    local definition = M.definition_for(entry)
    local count = context.purchased_count[player_id]
        and context.purchased_count[player_id][entry.entryid] or 0
    local limit = math.max(0, tonumber(entry.purchase_limit) or 0)
    local city_level = context.city_level or 0
    local resources = context.resources or {}

    if entry.enabled == false then return false, "商品已停用", definition, count end
    if not definition then return false, "商品配置缺失", nil, count end
    if limit > 0 and count >= limit then
        return false, "已达到购买上限", definition, count
    end
    if city_level < math.max(0, tonumber(entry.min_city_level) or 0) then
        return false, "主城等级不足", definition, count
    end
    if (resources.wood or 0) < math.max(0, tonumber(entry.woodcost) or 0) then
        return false, "木材不足", definition, count
    end
    if (resources.gold or 0) < math.max(0, tonumber(entry.goldcost) or 0) then
        return false, "金币不足", definition, count
    end
    return true, "", definition, count
end

local function project_entry(player_id, entry, context)
    if entry.visible == false then return nil end
    local purchasable, reason, definition, count = M.evaluate(
        player_id,
        entry,
        context
    )
    local icon, icon_type = content_icon(entry, definition or {})
    return {
        entry_id = entry.entryid,
        shop_id = entry.shopid,
        content_type = entry.contenttype or "item",
        content_id = entry.contentid,
        name = definition and M.content_name(entry, definition) or entry.contentid,
        description = definition and content_description(entry, definition)
            or (entry.itemdesc or ""),
        icon = icon,
        icon_type = icon_type,
        wood_cost = math.max(0, tonumber(entry.woodcost) or 0),
        gold_cost = math.max(0, tonumber(entry.goldcost) or 0),
        visible = 1,
        purchasable = purchasable and 1 or 0,
        disabled_reason = reason,
        purchase_condition_text = entry.condition_text or "",
        owned_count = count,
        purchase_limit = math.max(0, tonumber(entry.purchase_limit) or 0),
        sort_order = tonumber(entry.order) or 0,
        fields = entry.fields or (definition and definition.fields) or {},
    }
end

function M.build_snapshot(player_id, context)
    local entries = {}
    for _, entry in ipairs(shop_config.entries or {}) do
        local projection = project_entry(player_id, entry, context)
        if projection then table.insert(entries, projection) end
    end
    table.sort(entries, function(a, b)
        if a.shop_id == b.shop_id then return a.sort_order < b.sort_order end
        return a.shop_id < b.shop_id
    end)

    return {
        schema_version = 1,
        sequence = context.sequence,
        config_version = shop_config.version or 1,
        player_id = player_id,
        reason = context.reason or "open",
        resources = context.resources or {},
        categories = shop_config.categories or shop_config.shops or {},
        entries = entries,
    }
end

return M
