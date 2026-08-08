local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local MAX_SELECTED_BUILDINGS = 64

local ordinary_upgrade_abilities = {
    ability_upgrade_wall = true,
    ability_upgrade_city = true,
    ability_upgrade_farm = true,
}

local tower_single_upgrade_abilities = {
    "ability_upgrade_tower",
    "ability_upgrade_tower_lv01",
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
    if building_id ~= "arrow_tower" then return true end
    return tostring(candidate.survival_tower_class or "")
        == tostring(primary.survival_tower_class or "")
end

local function upgrade_ability(unit, primary_ability, ability_name)
    if primary_ability and primary_ability:GetCaster() == unit then
        return primary_ability
    end
    if ordinary_upgrade_abilities[ability_name] then
        return unit:FindAbilityByName(ability_name)
    end
    for _, name in ipairs(tower_single_upgrade_abilities) do
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
    local tower_single = ability_name == "ability_upgrade_tower"
        or ability_name == "ability_upgrade_tower_lv01"
    if player_id == nil or not valid_entity(primary) or owner_id(primary) ~= player_id
        or (not tower_single and not ordinary_upgrade_abilities[ability_name]) then
        return { ok = false, error = "批量升级请求无效" }
    end

    local success_count = 0
    local skipped_count = 0
    local first_error = nil
    for _, unit in ipairs(selected_candidates(primary, payload.selected_entindexes)) do
        local eligible = valid_entity(unit) and owner_id(unit) == player_id
            and same_type(primary, unit)
        local ability = eligible and upgrade_ability(
            unit,
            payload.primary_ability,
            ability_name
        ) or nil
        if not eligible or not ability_ready(ability, unit) then
            skipped_count = skipped_count + 1
            first_error = first_error or "部分建筑当前不能升级"
        else
            ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))
            local request = {
                building = unit,
                upgrade_mode = "one",
                source_ability = ability,
                silent_notification = true,
            }
            event_bus.emit(events.BUILDING_UPGRADE_REQUEST, request)
            if request.result and request.result.ok == true then
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
        "[BUILDING_BATCH_UPGRADE] player=%s primary=%s ability=%s success=%d skipped=%d",
        tostring(player_id), tostring(primary:entindex()), ability_name,
        success_count, skipped_count
    ))
    return result
end

return M