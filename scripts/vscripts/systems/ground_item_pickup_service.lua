local event_bus = require("core/event_bus")
local events = require("core/events")
local content_id_aliases = require("config/content_id_aliases")

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

function M.nearby(caster, player_id, target_origin)
    local origin = target_origin or caster:GetAbsOrigin()
    local result = {}
    if not Entities or not Entities.FindAllByClassname then return result end
    for _, container in ipairs(Entities:FindAllByClassname("dota_item_drop") or {}) do
        local item = valid(container) and container.GetContainedItem
            and container:GetContainedItem() or nil
        if valid(item) then
            local distance = (container:GetAbsOrigin() - origin):Length2D()
            if distance <= PICKUP_RADIUS and allowed(item, player_id)
                and item_slot(caster, item) < 0 then
                result[#result + 1] = {
                    container = container,
                    item = item,
                    distance = distance,
                    entindex = container:entindex(),
                    pickup_origin = origin,
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
    if not valid(caster) or not candidate or not valid(candidate.item)
        or not valid(candidate.container)
        or candidate.container:GetContainedItem() ~= candidate.item
        or item_slot(caster, candidate.item) >= 0 then
        return { ok = false, error = "ground_item_unavailable" }
    end
    local item, container = candidate.item, candidate.container
    local player_id = caster:GetPlayerOwnerID()
    if not allowed(item, player_id) then
        return { ok = false, error = "ground_item_not_owned" }
    end
    local reward = item.survival_ground_reward == true and type(item.Claim) == "function"
    local merge_reward = false
    if reward then
        local preview = event_bus.request(events.INVENTORY_ITEM_SHELL_ADOPT_REQUEST, {
            player_id = player_id,
            content_id = content_id_aliases.canonical(tostring(item.survival_content_id or "")),
            hero = caster, item = item, preview_only = true,
        })
        merge_reward = preview and preview.ok and preview.merged == true
    end
    local stacks = {}
    if not reward and item.IsStackable and item:IsStackable()
        and item.GetAbilityName and item.GetCurrentCharges then
        for slot = 0, 8 do
            local existing = caster:GetItemInSlot(slot)
            if valid(existing) and existing.IsStackable and existing:IsStackable()
                and existing:GetAbilityName() == item:GetAbilityName() then
                stacks[#stacks + 1] = { item = existing, charges = existing:GetCurrentCharges() }
            end
        end
    end
    if not merge_reward and #stacks == 0 and empty_inventory_slot(caster) == nil then
        return { ok = false, error = "inventory_full", full = true }
    end
    local original_position = container:GetAbsOrigin()
    if not merge_reward then caster:AddItem(item) end
    -- AddItem may bypass dota_item_picked_up; commit ground rewards here too.
    if reward and valid(item) and item.survival_claimed ~= true then
        if not merge_reward and item_slot(caster, item) < 0 then
            return { ok = false, error = "inventory_full", full = true }
        end
        if item:Claim(caster) ~= true then
            if valid(item) and item_slot(caster, item) >= 0
                and caster.DropItemAtPositionImmediate then
                caster:DropItemAtPositionImmediate(item, original_position)
                -- DropItem creates a new container; discard only the old one.
                if valid(container) and UTIL_Remove then UTIL_Remove(container) end
            end
            return { ok = false, error = "ground_reward_claim_failed" }
        end
        if valid(container) and UTIL_Remove then UTIL_Remove(container) end
        return { ok = true }
    end
    local picked = (valid(item) and item_slot(caster, item) >= 0)
        or (reward and item.survival_claimed == true)
    for _, stack in ipairs(stacks) do
        -- A partially merged item must retain its ground container. Successful
        -- native merging consumes the incoming entity instead of carrying it.
        if not valid(item) and valid(stack.item)
            and stack.item:GetCurrentCharges() > stack.charges then
            picked = true
        end
    end
    if picked and valid(container) and UTIL_Remove then UTIL_Remove(container) end
    local full = not picked and empty_inventory_slot(caster) == nil
    return {
        ok = picked,
        error = not picked and (full and "inventory_full" or "ground_item_pickup_failed") or nil,
        full = full,
    }
end

-- Scan the world once, then retry only this cast's blocked candidates after
-- deferred synthesis. Each retry requires progress, so work is bounded by the
-- number of drops and stops as soon as nothing more can be collected.
function M.pickup_batch(caster, player_id, candidates, pickup_candidate)
    player_id = tonumber(player_id)
    if not valid(caster) or player_id == nil or player_id < 0
        or caster:GetPlayerOwnerID() ~= player_id then
        return { ok = false, error = "ground_item_picker_invalid" }
    end
    local result = { ok = true, found = #candidates, picked = 0, full = false }
    local pending = candidates
    caster.survival_pickup_generation = (caster.survival_pickup_generation or 0) + 1
    local generation = caster.survival_pickup_generation
    local function run()
        if not valid(caster) or caster:GetPlayerOwnerID() ~= player_id
            or caster.survival_pickup_generation ~= generation
            or (caster.IsAlive and not caster:IsAlive()) then return nil end
        local remaining, progress, full = {}, false, false
        for _, candidate in ipairs(pending) do
            local entity = candidate.container or (candidate.drop and candidate.drop.unit)
            local in_range = not candidate.pickup_origin or (valid(entity)
                and (entity:GetAbsOrigin() - candidate.pickup_origin):Length2D() <= PICKUP_RADIUS)
            local picked = in_range and pickup_candidate(candidate) or {}
            if picked.ok then
                result.picked = result.picked + 1
                progress = true
            elseif picked.full or tostring(picked.error or ""):find("upgrade_material_stage_mismatch:", 1, true) == 1 then
                remaining[#remaining + 1] = candidate
                full = full or picked.full == true
            end
        end
        pending, result.full = remaining, full
        if progress and #pending > 0 then return 0.15 end
        if full then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = "装备栏空间不足，未能放入的物品已保留在地面",
                level = "error",
            })
        end
        return nil
    end
    local delay = run()
    local mode = GameRules and GameRules:GetGameModeEntity()
    if delay and mode and mode.SetContextThink then
        mode:SetContextThink("survival_area_pickup_" .. tostring(caster:entindex()), run, delay)
    elseif delay then
        -- Test/server contexts without deferred synthesis can finish directly.
        while run() do end
    end
    return result
end

function M.pickup(caster, player_id)
    player_id = tonumber(player_id)
    if not valid(caster) or player_id == nil or player_id < 0
        or caster:GetPlayerOwnerID() ~= player_id then
        return { ok = false, error = "ground_item_picker_invalid" }
    end

    local candidates = M.nearby(caster, player_id)
    local result = M.pickup_batch(caster, player_id, candidates, function(candidate)
        return M.pickup_candidate(caster, candidate)
    end)
    if #candidates == 0 then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "300范围内没有可拾取的物品",
        })
    end
    return result
end

return M
