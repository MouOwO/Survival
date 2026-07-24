local event_bus = require("core/event_bus")
local events = require("core/events")
local weapons = require("config/generated/weapon_definitions")
local content = require("config/generated/content_catalog")
local equipment = require("config/equipment_definitions")
local logger = require("core/logger")

local M = {}
local state_by_player = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function state(player_id)
    state_by_player[player_id] = state_by_player[player_id] or {
        hero = nil,
        equipped_by_slot = {},
        item_by_slot = {},
        content_shells = {},
        inventory_counts = {},
    }
    return state_by_player[player_id]
end

local function shell_item_name(definition)
    local series_id = tostring(definition and definition.series_id or "")
    local names = {
        attack_gloves = "item_survival_attack_gloves_shell",
        burning_blade = "item_survival_burning_blade_shell",
        iron_armor = "item_survival_iron_armor_shell",
        infernal_armor = "item_survival_infernal_armor_shell",
    }
    return names[series_id]
end

local function remove_content_shell(current, content_id)
    local item = current.content_shells[content_id]
    if not valid_entity(item) then
        current.content_shells[content_id] = nil
        return
    end
    if valid_entity(current.hero) and current.hero.RemoveItem then
        pcall(current.hero.RemoveItem, current.hero, item)
    end
    if UTIL_Remove then pcall(UTIL_Remove, item) end
    current.content_shells[content_id] = nil
end

local function add_content_shell(current, content_id, definition, quantity)
    if not valid_entity(current.hero) then return nil end
    local item = CreateItem(shell_item_name(definition), current.hero, current.hero)
    if not valid_entity(item) then
        logger.warn("WeaponEquipment", "content shell create failed: " .. content_id)
        return nil
    end
    item.survival_content_id = content_id
    if item.SetAbilityTextureName and tostring(definition.icon_name or "") ~= "" then
        pcall(item.SetAbilityTextureName, item, tostring(definition.icon_name))
    end
    if item.SetCurrentCharges then
        if content_id == "item_small_polar_crystal" then
            local progress = event_bus.request(
                events.POLAR_CRYSTAL_PROGRESS_GET_REQUEST,
                { player_id = current.hero:GetPlayerOwnerID() }
            )
            item:SetCurrentCharges(math.max(
                0,
                math.floor(tonumber(progress and progress.remaining) or 200)
            ))
        else
            item:SetCurrentCharges(math.max(1, math.floor(tonumber(quantity) or 1)))
        end
    end
    current.hero:AddItem(item)
    current.content_shells[content_id] = item
    return item
end

local function should_use_content_shell(content_id, definition)
    if not definition then return false end
    if not weapons.by_id[content_id] then return false end
    if not shell_item_name(definition) then return false end
    if tostring(definition.engine_item_name or "") ~= "" then return false end
    if content_id == "item_death_mask" then return false end
    return tostring(definition.grant_type or "") == "virtual_item"
end

local function sync_content_shells(player_id, counts)
    local current = state(player_id)
    current.inventory_counts = counts or {}
    for content_id in pairs(current.content_shells) do
        local definition = weapons.by_id[content_id]
        if (tonumber(current.inventory_counts[content_id]) or 0) <= 0
            or not should_use_content_shell(content_id, definition) then
            remove_content_shell(current, content_id)
        end
    end
    if not valid_entity(current.hero) then return end
    for content_id, quantity in pairs(current.inventory_counts) do
        local definition = weapons.by_id[content_id]
        if (tonumber(quantity) or 0) > 0
            and should_use_content_shell(content_id, definition) then
            local shell = current.content_shells[content_id]
            if not valid_entity(shell) then
                shell = add_content_shell(
                    current, content_id, definition, quantity
                )
            elseif shell.SetCurrentCharges then
                shell:SetCurrentCharges(math.max(
                    1, math.floor(tonumber(quantity) or 1)
                ))
            end
        end
    end
end

local function snapshot(player_id)
    local current = state(player_id)
    local main_id = current.equipped_by_slot.main_hand
    local definition = main_id and weapons.by_id[main_id] or nil
    return {
        player_id = player_id,
        main_hand_content_id = main_id or "",
        main_hand_name = main_id and content.by_id[main_id]
            and content.by_id[main_id].name or main_id or "",
        definition = definition,
    }
end

local function remove_shell(current, slot)
    local item = current.item_by_slot[slot]
    if not valid_entity(item) then
        current.item_by_slot[slot] = nil
        return
    end
    if valid_entity(current.hero) and current.hero.RemoveItem then
        pcall(current.hero.RemoveItem, current.hero, item)
    end
    if UTIL_Remove then
        pcall(UTIL_Remove, item)
    end
    current.item_by_slot[slot] = nil
end

local function set_item_counter(item, growth)
    if not valid_entity(item) or not item.SetCurrentCharges then
        return
    end
    local target = tonumber(growth and growth.stage_attack_target) or 0
    if target <= 0 then
        item:SetCurrentCharges(0)
        return
    end
    item:SetCurrentCharges(math.max(
        0,
        math.floor(tonumber(growth.stage_attack_remaining) or target)
    ))
end

local function add_shell(current, definition, slot, explicit_item_name)
    if not valid_entity(current.hero) then
        return nil
    end
    local item_name = tostring(explicit_item_name or definition.engine_item_name or "")
    if item_name == "" then
        return nil
    end
    local item = CreateItem(item_name, current.hero, current.hero)
    if not valid_entity(item) then
        logger.warn("WeaponEquipment", "item create failed: " .. item_name)
        return nil
    end
    current.hero:AddItem(item)
    current.item_by_slot[slot] = item
    if slot == "main_hand" and current.hero.GetPlayerOwnerID then
        local growth = event_bus.request(
            events.WEAPON_GROWTH_GET_REQUEST,
            { player_id = current.hero:GetPlayerOwnerID() }
        )
        if growth and growth.snapshot then
            set_item_counter(item, growth.snapshot)
        end
    elseif slot == "crystal" and current.hero.GetPlayerOwnerID
        and item_name == "item_survival_small_polar_crystal" then
        local progress = event_bus.request(
            events.POLAR_CRYSTAL_PROGRESS_GET_REQUEST,
            { player_id = current.hero:GetPlayerOwnerID() }
        )
        if item.SetCurrentCharges then
            item:SetCurrentCharges(math.max(
                0,
                math.floor(tonumber(progress and progress.remaining) or 200)
            ))
        end
    end
    return item
end

local function set_main_hand_counter(player_id, growth)
    local item = state(player_id).item_by_slot.main_hand
    if not valid_entity(item) or not item.SetCurrentCharges then
        return
    end
    set_item_counter(item, growth)
end

local function equip(player_id, content_id, reason)
    local definition = weapons.by_id[content_id]
    local equipment_meta = equipment.by_content_id[content_id]
    if not definition and not equipment_meta then
        return { ok = false, error = "equipment_definition_missing" }
    end
    if definition and definition.enabled == false then
        return { ok = false, error = "weapon_definition_missing" }
    end
    local slot = tostring((definition and definition.equipment_slot)
        or equipment_meta.slot or "")
    if slot == "" then
        return { ok = false, error = "equipment_slot_missing" }
    end
    local current = state(player_id)
    local previous = current.equipped_by_slot[slot]
    if previous == content_id then
        return { ok = true, snapshot = snapshot(player_id) }
    end
    remove_shell(current, slot)
    current.equipped_by_slot[slot] = content_id
    add_shell(current, definition or {}, slot,
        ({
            item_death_mask = "item_survival_death_mask",
            item_small_polar_crystal = "item_survival_small_polar_crystal",
            item_large_polar_crystal = "item_survival_large_polar_crystal",
        })[content_id])
    local data = snapshot(player_id)
    event_bus.emit(events.WEAPON_EQUIPPED_CHANGED, {
        player_id = player_id,
        slot = slot,
        previous_content_id = previous or "",
        content_id = content_id,
        reason = reason or "equip",
        snapshot = data,
    })
    return { ok = true, snapshot = data }
end

local function clear_if_removed(player_id, content_id, counts)
    local current = state(player_id)
    for slot, equipped_id in pairs(current.equipped_by_slot) do
        if equipped_id == content_id and (counts[content_id] or 0) <= 0 then
            remove_shell(current, slot)
            current.equipped_by_slot[slot] = nil
            event_bus.emit(events.WEAPON_EQUIPPED_CHANGED, {
                player_id = player_id,
                slot = slot,
                previous_content_id = content_id,
                content_id = "",
                reason = "inventory_removed",
                snapshot = snapshot(player_id),
            })
        end
    end
end

local function on_inventory_changed(payload)
    local player_id = tonumber(payload.player_id)
    local counts = payload.snapshot and payload.snapshot.counts or {}
    sync_content_shells(player_id, counts)
    local replacements = {}
    for content_id, delta in pairs(payload.changes or {}) do
        local definition = weapons.by_id[content_id]
        local equipment_meta = equipment.by_content_id[content_id]
        local auto_equip = definition and definition.auto_equip == true
        local virtual_equipment = equipment_meta and equipment_meta.virtual == true
        if tonumber(delta) and tonumber(delta) > 0
            and (auto_equip or virtual_equipment) then
            replacements[tostring((definition and definition.equipment_slot)
                or equipment_meta.slot or "")] = content_id
        end
    end
    for slot, content_id in pairs(replacements) do
        if slot ~= "" then
            equip(player_id, content_id, payload.reason)
        end
    end
    for content_id, delta in pairs(payload.changes or {}) do
        if tonumber(delta) and tonumber(delta) < 0 then
            clear_if_removed(player_id, content_id, counts)
        end
    end
end

local function on_hero_summoned(payload)
    local current = state(payload.player_id)
    for content_id in pairs(current.content_shells) do
        remove_content_shell(current, content_id)
    end
    for slot, content_id in pairs(current.equipped_by_slot) do
        remove_shell(current, slot)
    end
    current.hero = payload.unit
    for slot, content_id in pairs(current.equipped_by_slot) do
        add_shell(current, weapons.by_id[content_id] or {}, slot, ({
            item_death_mask = "item_survival_death_mask",
            item_small_polar_crystal = "item_survival_small_polar_crystal",
            item_large_polar_crystal = "item_survival_large_polar_crystal",
        })[content_id])
    end
    sync_content_shells(payload.player_id, current.inventory_counts)
end

local function on_growth_changed(payload)
    if payload.snapshot then
        set_main_hand_counter(tonumber(payload.player_id), payload.snapshot)
    end
end

local function on_polar_crystal_progress(payload)
    local current = state(tonumber(payload.player_id))
    if current.equipped_by_slot.crystal ~= "item_small_polar_crystal" then
        return
    end
    local item = current.item_by_slot.crystal
    if valid_entity(item) and item.SetCurrentCharges then
        item:SetCurrentCharges(math.max(
            0,
            math.floor(tonumber(payload.remaining) or 200)
        ))
    end
end

local function get_equipment(payload)
    return { ok = true, snapshot = snapshot(tonumber(payload.player_id)) }
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(events.WEAPON_EQUIPMENT_GET_REQUEST, get_equipment)
    event_bus.subscribe(events.CONTENT_INVENTORY_CHANGED, on_inventory_changed)
    event_bus.subscribe(events.WEAPON_GROWTH_CHANGED, on_growth_changed)
    event_bus.subscribe(
        events.POLAR_CRYSTAL_PROGRESS_CHANGED,
        on_polar_crystal_progress
    )
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
end

return M
