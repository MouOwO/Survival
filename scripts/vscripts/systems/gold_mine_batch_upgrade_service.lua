local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}
local MAX_SELECTED_BUILDINGS = 64
local request_sequence = 0

local ACTIONS = {
    ability_upgrade_gold_mine = { kind = "level" },
    ability_upgrade_gold_mine_efficiency = {
        kind = "technology",
        group = "gold_mine_efficiency",
        label = "采金效率",
    },
    ability_upgrade_gold_mine_crit = {
        kind = "technology",
        group = "gold_mine_crit",
        label = "采金暴击",
    },
    ability_gold_mine_auto_upgrade = {
        kind = "auto",
        enabled = true,
        label = "自动升级",
    },
    ability_gold_mine_stop_auto_upgrade = {
        kind = "auto",
        enabled = false,
        label = "停止自动升级",
    },
}

local function valid_entity(unit)
    if not unit then return false end
    local ok, valid = pcall(function()
        return not unit:IsNull() and unit:IsAlive()
    end)
    return ok and valid == true
end

local function owner_id(unit)
    local player_id = tonumber(unit.survival_player_id)
    if player_id ~= nil then return player_id end
    local ok, result = pcall(function() return unit:GetPlayerOwnerID() end)
    return ok and tonumber(result) or nil
end

local function is_owned_gold_mine(unit, player_id)
    return valid_entity(unit) and owner_id(unit) == player_id
        and unit.survival_building_id == "gold_mine"
end

local function ability_ready(ability, unit)
    return ability and not ability:IsNull() and ability:GetCaster() == unit
        and not ability:IsPassive() and not ability:IsHidden()
        and ability:IsActivated() and ability:IsFullyCastable()
end

local function selected_candidates(primary, selected_entindexes)
    local result = { primary }
    local seen = { [primary:entindex()] = true }
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
    end
    for _, raw_entindex in ipairs(raw_values) do
        if #result >= MAX_SELECTED_BUILDINGS then break end
        local entindex = tonumber(raw_entindex)
        if entindex and entindex >= 0 and not seen[entindex] then
            seen[entindex] = true
            local ok, unit = pcall(EntIndexToHScript, entindex)
            if ok and unit then result[#result + 1] = unit end
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

local function candidate_ability(unit, primary, primary_ability, ability_name)
    if unit == primary and primary_ability
        and primary_ability:GetCaster() == unit
        and primary_ability:GetAbilityName() == ability_name then
        return primary_ability
    end
    return unit:FindAbilityByName(ability_name)
end

local function start_cooldown(ability)
    ability:StartCooldown(ability:GetCooldown(ability:GetLevel()))
end

local function execute_level(payload, candidates)
    local queued = {}
    local skipped = 0
    local first_error = nil
    for _, unit in ipairs(candidates) do
        local ability = is_owned_gold_mine(unit, payload.player_id)
            and candidate_ability(
                unit,
                payload.primary,
                payload.primary_ability,
                payload.ability_name
            ) or nil
        if not ability_ready(ability, unit) or unit.survival_upgrade_in_progress then
            skipped = skipped + 1
            first_error = first_error or "部分金矿当前不能升级"
        else
            local quote, quote_error = event_bus.request(
                events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST,
                { entindex = unit:entindex() }
            )
            if not quote or quote.ok ~= true then
                skipped = skipped + 1
                first_error = first_error or (quote and quote.error)
                    or quote_error or "金矿升级费用不可用"
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

    local succeeded = 0
    for _, candidate in ipairs(queued) do
        local unit = candidate.unit
        local ability = candidate.ability
        if not is_owned_gold_mine(unit, payload.player_id)
            or not ability_ready(ability, unit)
            or unit.survival_upgrade_in_progress then
            skipped = skipped + 1
            first_error = first_error or "部分金矿当前不能升级"
        else
            local result, request_error = event_bus.request(
                events.GOLD_MINE_LEVEL_UPGRADE_REQUEST,
                {
                    entindex = unit:entindex(),
                    source_ability = ability,
                    silent_notification = true,
                }
            )
            if result and result.ok == true then
                start_cooldown(ability)
                succeeded = succeeded + 1
            else
                skipped = skipped + 1
                first_error = first_error or (result and result.error)
                    or request_error or "金矿升级失败"
            end
        end
    end
    return succeeded, skipped, first_error, #queued
end

local function execute_technology(payload, action, candidates)
    local eligible = {}
    local skipped = 0
    for _, unit in ipairs(candidates) do
        local ability = is_owned_gold_mine(unit, payload.player_id)
            and candidate_ability(
                unit,
                payload.primary,
                payload.primary_ability,
                payload.ability_name
            ) or nil
        if ability_ready(ability, unit) and not unit.survival_upgrade_in_progress then
            eligible[#eligible + 1] = {
                unit = unit,
                ability = ability,
                entindex = unit:entindex(),
            }
        else
            skipped = skipped + 1
        end
    end
    table.sort(eligible, function(left, right)
        return left.entindex < right.entindex
    end)
    if #eligible == 0 then
        return 0, skipped, "没有可升级该科技的金矿", 0
    end

    request_sequence = request_sequence + 1
    local source = eligible[1]
    local result, request_error = event_bus.request(
        events.TECHNOLOGY_PURCHASE_NEXT_REQUEST,
        {
            player_id = payload.player_id,
            technology_group = action.group,
            source = "gold_mine_ability",
            entindex = source.entindex,
            request_id = "gold_mine_batch_" .. tostring(payload.player_id)
                .. "_" .. tostring(request_sequence),
            silent_notification = true,
        }
    )
    if not result or result.ok ~= true then
        return 0, skipped, (result and result.error)
            or request_error or (action.label .. "升级失败"), #eligible
    end
    for _, candidate in ipairs(eligible) do
        start_cooldown(candidate.ability)
    end
    return #eligible, skipped, nil, #eligible
end

local function execute_auto(payload, action, candidates)
    local changed = 0
    local unchanged = 0
    local skipped = 0
    local first_error = nil
    for _, unit in ipairs(candidates) do
        if not is_owned_gold_mine(unit, payload.player_id) then
            skipped = skipped + 1
            first_error = first_error or "部分金矿不属于当前玩家"
        else
            local current, state_error = event_bus.request(
                events.GOLD_MINE_AUTO_STATE_REQUEST,
                { entindex = unit:entindex() }
            )
            if not current or current.ok ~= true then
                skipped = skipped + 1
                first_error = first_error or (current and current.error)
                    or state_error or "金矿自动升级状态不可用"
            elseif current.enabled == action.enabled then
                unchanged = unchanged + 1
            else
                local ability = candidate_ability(
                    unit,
                    payload.primary,
                    payload.primary_ability,
                    payload.ability_name
                )
                if not ability_ready(ability, unit) then
                    skipped = skipped + 1
                    first_error = first_error or "部分金矿自动升级技能当前不可用"
                else
                    local result, request_error = event_bus.request(
                        events.GOLD_MINE_AUTO_UPGRADE_REQUEST,
                        {
                            entindex = unit:entindex(),
                            enabled = action.enabled,
                        }
                    )
                    if result and result.ok == true then
                        changed = changed + 1
                    else
                        skipped = skipped + 1
                        first_error = first_error or (result
                            and (result.error or result.message))
                            or request_error or "金矿自动升级设置失败"
                    end
                end
            end
        end
    end
    return changed, unchanged, skipped, first_error
end

function M.execute(payload)
    payload = payload or {}
    local player_id = tonumber(payload.player_id)
    local primary = payload.primary
    local ability_name = tostring(payload.ability_name or "")
    local action = ACTIONS[ability_name]
    if not action or player_id == nil
        or not is_owned_gold_mine(primary, player_id) then
        return { ok = false, error = "金矿批量请求无效" }
    end
    local primary_ability = payload.primary_ability
    if not primary_ability or primary_ability:IsNull()
        or primary_ability:GetCaster() ~= primary
        or primary_ability:GetAbilityName() ~= ability_name
        or not ability_ready(primary_ability, primary) then
        return { ok = false, error = "金矿批量请求技能无效" }
    end

    payload.player_id = player_id
    payload.ability_name = ability_name
    local candidates = selected_candidates(primary, payload.selected_entindexes)
    local result
    if action.kind == "level" then
        local success, skipped, first_error, queued = execute_level(payload, candidates)
        result = {
            ok = success > 0,
            success_count = success,
            skipped_count = skipped,
            candidate_count = queued,
        }
        if result.ok then
            notify(player_id, string.format(
                "金矿批量升级：成功%d座，跳过%d座",
                success,
                skipped
            ))
        else
            result.error = first_error or "没有可升级的金矿"
            notify(player_id, result.error, "error")
        end
    elseif action.kind == "technology" then
        local cooled, skipped, first_error, eligible = execute_technology(
            payload,
            action,
            candidates
        )
        result = {
            ok = cooled > 0,
            success_count = cooled,
            skipped_count = skipped,
            candidate_count = eligible,
            technology_levels_purchased = cooled > 0 and 1 or 0,
        }
        if result.ok then
            notify(player_id, string.format(
                "%s提升1级：同步冷却%d座，跳过%d座",
                action.label,
                cooled,
                skipped
            ))
        else
            result.error = first_error or (action.label .. "升级失败")
            notify(player_id, result.error, "error")
        end
    else
        local changed, unchanged, skipped, first_error = execute_auto(
            payload,
            action,
            candidates
        )
        result = {
            ok = changed + unchanged > 0,
            success_count = changed,
            unchanged_count = unchanged,
            skipped_count = skipped,
        }
        if result.ok then
            notify(player_id, string.format(
                "%s：变更%d座，保持%d座，跳过%d座",
                action.label,
                changed,
                unchanged,
                skipped
            ))
        else
            result.error = first_error or "没有可设置的金矿"
            notify(player_id, result.error, "error")
        end
    end
    print(string.format(
        "[GOLD_MINE_BATCH] player=%s action=%s selected=%d success=%d unchanged=%d skipped=%d",
        tostring(player_id), ability_name, #candidates,
        tonumber(result.success_count) or 0,
        tonumber(result.unchanged_count) or 0,
        tonumber(result.skipped_count) or 0
    ))
    return result
end

return M
