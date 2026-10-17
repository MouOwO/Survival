-- Read-only collection view of the authenticated account's existing rewards.
-- Opening this page must never purchase, reconcile, claim or grant anything.
local catalog = require("config/generated/archive_commerce_goods")
local resources = require("config/generated/item_resources")
local json_null = require("core/json_decoder").null
local M = {}

local function table_or_nil(value)
    return type(value) == "table" and value ~= json_null and value or nil
end

local function quantity(value)
    local n = tonumber(value)
    if n and n == n and n >= 0 and n < math.huge and n == math.floor(n) then return n end
end

local function item_count(inventory, id)
    if not inventory then return nil end
    local value = inventory[id]
    -- A complete, loaded inventory represents absent entries as zero. An
    -- absent inventory (or malformed stored value) is unknown, never zero.
    if value == nil then return 0 end
    return quantity(value)
end

local function owned_count(item, save)
    local inventory = table_or_nil(save.content_inventory)
    if item.kind == "product" then return item_count(inventory, item.ownership_id) end
    if item.kind == "vip" then
        local archive = table_or_nil(save.archive)
        local raw_claims = archive and archive.vip_claimed
        local claims = table_or_nil(raw_claims)
        local claimed = claims and claims[item.ownership_id]
        local count = item_count(inventory, item.ownership_id)
        if claimed == true or count and count > 0 then return 1 end
        if claimed ~= nil and claimed ~= false then return nil end
        -- Legacy VIP settlements wrote the claim map rather than inventory.
        -- A loaded archive is therefore required before ruling out a claim.
        if archive and (raw_claims == nil or claims) and count ~= nil then return 0 end
        return nil
    end
    if item.kind == "starjoy" then
        local stats = table_or_nil(save.gameplay_stats)
        if not stats then return nil end
        local level = quantity(stats.starjoy_reward_level)
        if level == nil then return nil end
        return level >= item.level and 1 or 0
    end
    -- New ownership types require an explicit, authoritative adapter.
    return nil
end

function M.project(profile)
    local save = profile and table_or_nil(profile.save) or {}
    local rows = {}
    for _, item in ipairs(catalog.rows) do
        if item.enabled ~= false then
            local count = owned_count(item, save)
            local resource = resources.lookup(item)
            local row = {
                id = item.id, name = item.name, description = item.description,
                icon = resource and resource.uri or item.icon, icon_type = item.icon_type or "image",
                resource_id = resource and resource.id or nil,
                quality = item.quality or "", kind = item.kind,
                category_id = "commerce_goods", source_id = item.source_id,
                sku = item.sku, unlock_condition = item.unlock_condition,
                level = item.level, count = count,
                count_known = count ~= nil and 1 or 0,
                quantity_unknown = count == nil and 1 or 0,
            }
            if count ~= nil then
                local owned = count > 0 and 1 or 0
                row.owned, row.unlocked, row.completed = owned, owned, owned
            end
            local maximum = quantity(item.max_owned)
            if maximum and maximum > 0 then row.target = maximum end
            rows[#rows + 1] = row
        end
    end
    return rows
end

return M
