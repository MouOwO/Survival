local event_bus = require("core/event_bus")
local events = require("core/events")
local weapon_definitions = require("config/generated/weapon_definitions")

local M = {}

local function series_inventory(counts, series_id)
    local matches = {}
    for content_id, count in pairs(counts or {}) do
        local definition = weapon_definitions.by_id[content_id]
        if (tonumber(count) or 0) > 0
            and definition
            and tostring(definition.series_id or "") == series_id then
            matches[#matches + 1] = {
                content_id = content_id,
                count = tonumber(count) or 0,
                stage = tonumber(definition.stage) or 0,
                definition = definition,
            }
        end
    end
    table.sort(matches, function(left, right)
        if left.stage == right.stage then
            return left.content_id < right.content_id
        end
        return left.stage > right.stage
    end)
    return matches
end

local function series_snapshot(matches)
    local values = {}
    for _, match in ipairs(matches or {}) do
        values[#values + 1] = string.format("%s(stage=%s,count=%s)",
            tostring(match.content_id), tostring(match.stage), tostring(match.count))
    end
    return #values > 0 and table.concat(values, ",") or "empty"
end

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

local function grant_virtual_item(player_id, entry, state)
    local definition = entry.definition or {}
    if entry.contentid == "service_early_final_boss" then
        return event_bus.request(events.WAVE_EARLY_FINAL_REQUEST, {
            player_id = player_id,
            reason = "shop_service_early_final_boss",
        }) or { ok = false, error = "wave_handler_missing" }
    end
    if definition.item_subtype == "consumable" then
        local summoned = event_bus.request(
            events.HERO_SUMMON_GET_REQUEST,
            { player_id = player_id }
        )
        local hero = summoned and summoned.unit
        if not hero or hero:IsNull() then
            return { ok = false, error = "hero_not_ready" }
        end
        if definition.effect_type ~= "add_all_attributes" then
            return { ok = false, error = "consumable_effect_unsupported" }
        end
        local attribute_value = tonumber(definition.effect_value)
        local attack_value = tonumber(definition.effect_secondary_value)
        if not attribute_value or attribute_value <= 0
            or not attack_value or attack_value <= 0 then
            return { ok = false, error = "consumable_effect_invalid" }
        end
        return event_bus.request(
            events.HERO_PROGRESSION_APPLY_REQUEST,
            {
                player_id = player_id,
                reason = "shop_consumable:" .. entry.entryid,
                effects = {
                    {
                        effect_type = "add_all_attributes",
                        value = attribute_value,
                    },
                    {
                        effect_type = "add_attack_flat",
                        value = attack_value,
                    },
                },
            }
        ) or { ok = false, error = "progression_handler_missing" }
    end
    if definition.progression_type == "repeat_purchase"
        and tostring(definition.series_id or "") ~= "" then
        local series_id = tostring(definition.series_id)
        local inv = event_bus.request(events.CONTENT_INVENTORY_GET_REQUEST,
            { player_id = player_id })
        local counts = inv and inv.snapshot and inv.snapshot.counts or {}
        local matches = series_inventory(counts, series_id)
        print(string.format(
            "[SHOP_REPEAT_SCAN] player=%s entry=%s requested=%s series=%s inventory=%s",
            tostring(player_id), tostring(entry.entryid), tostring(entry.contentid),
            series_id, series_snapshot(matches)))
        if #matches > 1 then
            print(string.format(
                "[SHOP_REPEAT_AMBIGUOUS] player=%s series=%s matches=%s selected=%s",
                tostring(player_id), series_id, series_snapshot(matches),
                tostring(matches[1].content_id)))
        end
        local selected = matches[1]
        if selected then
            local old_content_id = selected.content_id
            local next_content_id = tostring(
                selected.definition.next_content_id or "")
            if next_content_id == "" then
                print(string.format(
                    "[SHOP_REPEAT_MAX] player=%s entry=%s content_id=%s stage=%s",
                    tostring(player_id), tostring(entry.entryid), old_content_id,
                    tostring(selected.stage)))
                return { ok = false, error = "shop_equipment_already_max",
                    content_id = old_content_id }
            end
            local next_definition = weapon_definitions.by_id[next_content_id]
            if not next_definition
                or tostring(next_definition.series_id or "") ~= series_id then
                print(string.format(
                    "[SHOP_REPEAT_CHAIN_INVALID] player=%s series=%s old=%s next=%s",
                    tostring(player_id), series_id, old_content_id, next_content_id))
                return { ok = false, error = "shop_equipment_upgrade_chain_invalid" }
            end
            local result = event_bus.request(
                events.CONTENT_INVENTORY_TRANSACTION_REQUEST,
                {
                    player_id = player_id,
                    consume = { [old_content_id] = 1 },
                    grant = { [next_content_id] = 1 },
                    reason = "shop_repeat_upgrade:" .. entry.entryid,
                }
            ) or { ok = false, error = "inventory_handler_missing" }
            result.old_content_id = old_content_id
            result.new_content_id = next_content_id
            local after_counts = result.snapshot and result.snapshot.counts or {}
            print(string.format(
                "[SHOP_REPEAT_RESULT] player=%s entry=%s ok=%s old=%s new=%s after=%s error=%s",
                tostring(player_id), tostring(entry.entryid), tostring(result.ok == true),
                old_content_id, next_content_id,
                series_snapshot(series_inventory(after_counts, series_id)),
                tostring(result.error or "")))
            return result
        end
        print(string.format(
            "[SHOP_REPEAT_FIRST] player=%s entry=%s grant=%s series=%s",
            tostring(player_id), tostring(entry.entryid), tostring(entry.contentid),
            series_id))
    end
    local result = event_bus.request(
        events.CONTENT_INVENTORY_GRANT_REQUEST,
        {
            player_id = player_id,
            content_id = entry.contentid,
            count = 1,
            reason = "shop_purchase:" .. entry.entryid,
        }
    )
    print(string.format(
        "[SHOP_VIRTUAL_GRANT] player=%s entry=%s content_id=%s ok=%s error=%s",
        tostring(player_id), tostring(entry.entryid), tostring(entry.contentid),
        tostring(result and result.ok == true), tostring(result and result.error or "")))
    return result or { ok = false, error = "inventory_handler_missing" }
end

local function grant_technology(player_id, entry, state)
    if entry.contenttype == "technology_service" then
        if entry.contentid == "advanced_researcher_unlock" then
            if state.advanced_researcher_unlocked[player_id] == true then
                return { ok = false, error = "advanced_researcher_already_unlocked" }
            end
            state.advanced_researcher_unlocked[player_id] = true
            return { ok = true, advanced_researcher_unlocked = true }
        end
        if state.research_unlocked[player_id] == true then
            return { ok = false, error = "research_already_unlocked" }
        end
        state.research_unlocked[player_id] = true
        return { ok = true, research_unlocked = true }
    end
    state.technology_by_player[player_id] =
        state.technology_by_player[player_id] or {}
    local technologies = state.technology_by_player[player_id]
    local group = entry.definition.technology_group or entry.contentid
    local level = tonumber(entry.definition.level) or 1
    local current = tonumber(technologies[group]) or 0
    if level ~= current + 1 then
        return { ok = false, error = "technology_level_invalid" }
    end
    technologies[group] = level
    event_bus.emit(events.TECHNOLOGY_CHANGED, {
        player_id = player_id,
        technology_group = group,
        level = level,
        levels = technologies,
    })
    return { ok = true, technology_group = group, level = level }
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
    if entry.grant_type == "technology_unlock" then
        return grant_technology(player_id, entry, state)
    end
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
        return grant_virtual_item(player_id, entry, state)
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
