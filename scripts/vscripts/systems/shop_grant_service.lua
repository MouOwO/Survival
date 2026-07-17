local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function grant_resource(team, definition)
    local grant = definition.grant or {}
    return event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = team,
        wood = grant.wood or 0,
        gold = grant.gold or 0,
        max_population = grant.max_population or 0,
        reason = "shop_grant:" .. definition.itemid,
    })
end

local function grant_native_item(player_id, definition)
    local hero = PlayerResource:GetSelectedHeroEntity(player_id)
    if not hero or hero:IsNull() then return { ok = false, error = "hero_not_ready" } end
    if not definition.native_item_name or definition.native_item_name == "" then
        return { ok = false, error = "native_item_missing" }
    end
    local item = CreateItem(definition.native_item_name, hero, hero)
    if not item then return { ok = false, error = "item_create_failed" } end
    hero:AddItem(item)
    return { ok = true }
end

local function grant_virtual_item(player_id, definition, inventory_by_player)
    inventory_by_player[player_id] = inventory_by_player[player_id] or {}
    local amount = math.max(1, tonumber(definition.stack_count) or 1)
    inventory_by_player[player_id][definition.itemid] =
        (inventory_by_player[player_id][definition.itemid] or 0) + amount
    return { ok = true }
end

local function grant_technology(player_id, definition, technology_by_player)
    technology_by_player[player_id] = technology_by_player[player_id] or {}
    local current = technology_by_player[player_id][definition.technologyid] or 0
    local maximum = math.max(1, tonumber(definition.max_level) or 1)
    if current >= maximum then return { ok = false, error = "technology_max_level" } end
    technology_by_player[player_id][definition.technologyid] = current + 1
    return { ok = true }
end

function M.grant(player_id, team, entry, definition, state)
    if entry.contenttype == "technology" then
        return grant_technology(player_id, definition, state.technology_by_player)
    end
    if definition.grant_type == "resource" then return grant_resource(team, definition) end
    if definition.grant_type == "native_item" then
        return grant_native_item(player_id, definition)
    end
    if definition.grant_type == "virtual_item" then
        return grant_virtual_item(player_id, definition, state.inventory_by_player)
    end
    return { ok = false, error = "unsupported_grant_type" }
end

function M.refund(team, entry)
    event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = team,
        wood = entry.woodcost or 0,
        gold = entry.goldcost or 0,
        reason = "shop_refund:" .. entry.entryid,
    })
end

return M
