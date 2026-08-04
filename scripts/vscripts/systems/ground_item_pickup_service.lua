local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local PICKUP_RADIUS = 300

local function valid(entity)
    return entity and not entity:IsNull()
end

local function empty_inventory_slot(caster)
    for slot = 0, 8 do
        if not caster:GetItemInSlot(slot) then return slot end
    end
    return nil
end

local function item_slot(caster, item)
    for slot = 0, 8 do
        if caster:GetItemInSlot(slot) == item then return slot end
    end
    return -1
end

local function allowed(item, player_id)
    local owner_id = tonumber(item.survival_owner_player_id)
    if owner_id ~= nil and owner_id >= 0 then return owner_id == player_id end
    local owners = {}
    if item.GetPurchaser then owners[#owners + 1] = item:GetPurchaser() end
    if item.GetOwnerEntity then owners[#owners + 1] = item:GetOwnerEntity() end
    for _, owner in ipairs(owners) do
        if valid(owner) and owner.GetPlayerOwnerID then
            owner_id = tonumber(owner:GetPlayerOwnerID())
            if owner_id ~= nil and owner_id >= 0 then
                return owner_id == player_id
            end
        end
    end
    if item.GetPlayerOwnerID then
        owner_id = tonumber(item:GetPlayerOwnerID())
        if owner_id ~= nil and owner_id >= 0 then return owner_id == player_id end
    end
    return true
end

function M.nearby(caster, player_id)
    local origin = caster:GetAbsOrigin()
    local result = {}
    if not Entities or not Entities.FindAllByClassname then return result end
    for _, container in ipairs(Entities:FindAllByClassname("dota_item_drop") or {}) do
        local item = valid(container) and container.GetContainedItem
            and container:GetContainedItem() or nil
        if valid(item) and allowed(item, player_id) then
            local distance = (container:GetAbsOrigin() - origin):Length2D()
            if distance <= PICKUP_RADIUS then
                result[#result + 1] = {
                    container = container,
                    item = item,
                    distance = distance,
                    entindex = container:entindex(),
                }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.distance == b.distance then return a.entindex < b.entindex end
        return a.distance < b.distance
    end)
    return result
end

function M.pickup_candidate(caster, candidate)
    if not valid(caster) or not candidate or not valid(candidate.item) then
        return { ok = false, error = "ground_item_unavailable" }
    end
    if not empty_inventory_slot(caster) then
        return { ok = false, error = "inventory_full", full = true }
    end
    caster:AddItem(candidate.item)
    local picked = item_slot(caster, candidate.item) >= 0
        or candidate.item.survival_claimed == true
    return {
        ok = picked,
        error = picked and nil or "ground_item_pickup_failed",
    }
end

function M.pickup(caster, player_id)
    player_id = tonumber(player_id)
    if not valid(caster) or player_id == nil or player_id < 0
        or caster:GetPlayerOwnerID() ~= player_id then
        return { ok = false, error = "ground_item_picker_invalid" }
    end

    local candidates = M.nearby(caster, player_id)
    local picked = 0
    local full = false
    for _, candidate in ipairs(candidates) do
        local result = M.pickup_candidate(caster, candidate)
        if result.full then full = true break end
        if result.ok then picked = picked + 1 end
    end

    if full then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "装备栏已满，已停止拾取剩余物品",
            level = "error",
        })
    elseif #candidates == 0 then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "300范围内没有可拾取的物品",
        })
    end
    return { ok = true, found = #candidates, picked = picked, full = full }
end

return M