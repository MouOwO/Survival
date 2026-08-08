local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local MAX_SELECTED_BUILDINGS = 64

local ordinary_upgrade_abilities = {
    ability_upgrade_wall = { wall = true },
    ability_upgrade_city = { main_city = true },
    ability_upgrade_farm = { building_farm = true, farm = true },
}

local tower_single_upgrade_abilities = {
    "ability_upgrade_tower",
    "ability_upgrade_tower_lv01",
}

local tower_upgrade_abilities = {
    one = tower_single_upgrade_abilities,
    max = { "ability_upgrade_tower_max" },
}

local function valid_entity(unit)
    return unit and not unit:IsNull() and unit:IsAlive()
end

local function owner_id(unit)
    return tonumber(unit.survival_player_id) or unit:GetPlayerOwnerID()
end

local function same_type(primary, candidate)
    local building_id = tostring(primary.survival_building_id or "")
    if building_id == "" or tostring(candidate.survival_building_id or "") ~= building_id then
        return false
    end
    return true
end

local function ability_name_matches(ability, requested_name, upgrade_mode)
    if not ability or type(ability.GetAbilityName) ~= "function" then return false end
    local actual_name = ability:GetAbilityName()
    if ordinary_upgrade_abilities[requested_name] then
        return actual_name == requested_name
    end
    for _, name in ipairs(tower_upgrade_abilities[upgrade_mode] or {}) do
        if actual_name == name then return true end
    end
    return false
end

local function upgrade_ability(unit, primary_ability, ability_name, upgrade_mode)
    if primary_ability and primary_ability:GetCaster() == unit
        and ability_name_matches(primary_ability, ability_name, upgrade_mode) then
        return primary_ability
    end
    if ordinary_upgrade_abilities[ability_name] then
        return unit:FindAbilityByName(ability_name)
    end
    for _, name in ipairs(tower_upgrade_abilities[upgrade_mode] or {}) do
        local ability = unit:FindAbilityByName(name)
        if ability then return ability end
    end
    return nil
end

local function ability_ready(ability, unit)
    return ability and not ability:IsNull() and ability:GetCaster() == unit
        and not ability:IsPassive() and not ability:IsHidden()
        and ability:IsActivated() and ability:IsFullyCastable()
end

local function selected_candidates(primary, selected_entindexes)
    local result = { primary }
    local seen = { [primary:entindex()] = true }
    local count = 1
    local raw_values = {}
    if type(selected_entindexes) == "string" then
        for raw_entindex in string.gmatch(selected_entindexes, "[^,]+") do
            raw_values[#raw_values + 1] = raw_entindex
        end
    elseif type(selected_entindexes) == "table" then
        local numeric_keys = {}
        for key, _ in pairs(selected_entindexes) do
            local numeric_key = tonumber(key)
            if numeric_key then numeric_keys[#numeric_keys + 1] = numeric_key end
        end
        table.sort(numeric_keys)
        for _, key in ipairs(numeric_keys) do
            raw_values[#raw_values + 1] = selected_entindexes[key]
                or selected_entindexes[tostring(key)]
        end
    else
        return result
    end
    for _, raw_entindex in ipairs(raw_values) do
        if count >= MAX_SELECTED_BUILDINGS then break end
        local entindex = tonumber(raw_entindex)
        if entindex and entindex >= 0 and not seen[entindex] then
            seen[entindex] = true
            local ok, unit = pcall(EntIndexToHScript, entindex)
            if ok and unit then
                result[#result + 1] = unit
                count = count + 1
            end
        end
    end
    return result
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

function M.execute(payload)
    payload = payload or {}
    local player_id = tonumber(payload.player_id)
    local primary = payload.primary
    local ability_name = tostring(payload.ability_name or "")
    local upgrade_mode = ability_name == "ability_upgrade_tower_max"
        and "max" or "one"
    local tower_single = ability_name == "ability_upgrade_tower"
        or ability_name == "ability_upgrade_tower_lv01"
    local tower_max = ability_name == "ability_upgrade_tower_max"
    local primary_building_id = tostring(primary
        and primary.survival_building_id or "")
    local ordinary_types = ordinary_upgrade_abilities[ability_name]
    local type_matches = ((tower_single or tower_max)
            and primary_building_id == "arrow_tower")
        or (ordinary_types and ordinary_types[primary_building_id] == true)
    if player_id == nil or not valid_entity(primary) or owner_id(primary) ~= player_id
        or (not tower_single and not tower_max
            and not ordinary_types) or not type_matches then
        return { ok = false, error = "批量升级请求无效" }
    end

    local success_count = 0
    local skipped_count = 0
    local first_error = nil
    local queued = {}
    for _, unit in ipairs(selected_candidates(primary, payload.selected_entindexes)) do
        local eligible = valid_entity(unit) and owner_id(unit) == player_id
            and same_type(primary, unit)
        local ability = eligible and upgrade_ability(
            unit,
            payload.primary_ability,
            ability_name,
            upgrade_mode
        ) or nil
        if not eligible or not ability_ready(ability, unit) then
            skipped_count = skipped_count + 1
            first_error = first_error or "部分建筑当前不能升级"
        else
            local quote, quote_error = event_bus.request(
                events.BUILDING_UPGRADE_QUOTE_REQUEST,
                { building = unit, upgrade_mode = upgrade_mode }
            )
            if not quote or quote.ok ~= true then
                skipped_count = skipped_count + 1
                first_error = first_error or (quote and quote.error)
                    or quote_error or "升级费用不可用"
            else
                queued[#queued + 1] = {
                    unit = unit,
                    ability = ability,
                    quote = quote,
                    entindex = unit:entindex(),
                }
            end
        end
    end

    table.sort(queued, function(left, right)
        local left_wood = tonumber(left.quote.wood) or 0
        local right_wood = tonumber(right.quote.wood) or 0
        if left_wood ~= right_wood then return left_wood < right_wood end
        local left_gold = tonumber(left.quote.gold) or 0
        local right_gold = tonumber(right.quote.gold) or 0
        if left_gold ~= right_gold then return left_gold < right_gold end
        return left.entindex < right.entindex
    end)

    for _, candidate in ipairs(queued) do
        local unit = candidate.unit
        local ability = candidate.ability
        if not valid_entity(unit) or owner_id(unit) ~= player_id
            or not same_type(primary, unit) or not ability_ready(ability, unit) then
            skipped_count = skipped_count + 1
            first_error = first_error or "部分建筑当前不能升级"
        else
            local request = {
                building = unit,
                upgrade_mode = upgrade_mode,
                source_ability = ability,
                silent_notification = true,
            }
            event_bus.emit(events.BUILDING_UPGRADE_REQUEST, request)
            if request.result and request.result.ok == true then
                ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))
                success_count = success_count + 1
            else
                skipped_count = skipped_count + 1
                first_error = first_error
                    or (request.result and request.result.error)
                    or "升级失败"
            end
        end
    end

    local result = {
        ok = success_count > 0,
        success_count = success_count,
        skipped_count = skipped_count,
    }
    if result.ok then
        local message = success_count == 1 and skipped_count == 0
            and "开始升级"
            or string.format("批量升级：成功%d栋，跳过%d栋", success_count, skipped_count)
        notify(player_id, message, "info")
    else
        result.error = first_error or "没有可升级的同类型建筑"
        notify(player_id, result.error, "error")
    end
    print(string.format(
        "[BUILDING_BATCH_UPGRADE] player=%s primary=%s ability=%s mode=%s candidates=%d success=%d skipped=%d",
        tostring(player_id), tostring(primary:entindex()), ability_name,
        upgrade_mode, #queued, success_count, skipped_count
    ))
    return result
end

return M