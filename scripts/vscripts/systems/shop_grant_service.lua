local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local function grant_native_item(player_id, entry)
    local summoned = event_bus.request(
        events.HERO_SUMMON_GET_REQUEST,
        { player_id = player_id }
    )
    local hero = summoned and summoned.unit
        or PlayerResource:GetSelectedHeroEntity(player_id)
    if not hero or hero:IsNull() then
        return { ok = false, error = "hero_not_ready" }
    end
    local native_name = entry.definition.native_item_name
    if not native_name or native_name == "" then
        return { ok = false, error = "native_item_missing" }
    end
    local item = CreateItem(native_name, hero, hero)
    if not item then
        return { ok = false, error = "item_create_failed" }
    end
    hero:AddItem(item)
    return { ok = true }
end

local function grant_virtual_item(player_id, entry)
    local result = event_bus.request(
        events.CONTENT_INVENTORY_GRANT_REQUEST,
        {
            player_id = player_id,
            content_id = entry.contentid,
            count = 1,
            reason = "shop_purchase:" .. entry.entryid,
        }
    )
    return result or { ok = false, error = "inventory_handler_missing" }
end

local function grant_technology(player_id, entry, state)
    state.technology_by_player[player_id] =
        state.technology_by_player[player_id] or {}
    local technologies = state.technology_by_player[player_id]
    if technologies[entry.contentid] then
        return { ok = false, error = "technology_already_owned" }
    end
    technologies[entry.contentid] = true
    return { ok = true }
end

local function start_encounter(player_id, team, entry)
    local result = event_bus.request(
        events.MONSTER_ENCOUNTER_START_REQUEST,
        {
            player_id = player_id,
            team = team,
            encounter_id = entry.encounter_id,
        }
    )
    return result or { ok = false, error = "encounter_handler_missing" }
end

function M.grant(player_id, team, entry, state)
    if entry.grant_type == "technology_level" then
        return grant_technology(player_id, entry, state)
    end
    if entry.grant_type == "start_encounter" then
        return start_encounter(player_id, team, entry)
    end
    if entry.grant_type == "native_item" then
        return grant_native_item(player_id, entry)
    end
    if entry.grant_type == "virtual_item" then
        return grant_virtual_item(player_id, entry)
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
