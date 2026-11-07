local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local actions = require("config/generated/altar_actions")
local room_locations = require("systems/player_room_locations")
local technology_stat_manager = require("systems/technology_stat_manager")
local return_home = require("systems/hero_return_home_service")
local destination_validation = require("systems/destination_validation_service")

local M = {}
local state_by_player = {}
local entering_by_player = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function alive(unit)
    return valid(unit) and unit:IsAlive()
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function action_for(action_id)
    local row = (actions.by_id or {})[tostring(action_id or "")]
    return row and row.enabled ~= false and row or nil
end

local function hero_for(player_id)
    local result = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = player_id,
    })
    return result and result.ok and alive(result.unit) and result.unit or nil
end

local function progression_for(player_id)
    local result = event_bus.request(events.HERO_PROGRESSION_GET_REQUEST, {
        player_id = player_id,
    })
    return result and result.snapshot or {}
end

local function marker_for(action, player_id)
    local location = room_locations.resolve(action.location_id, player_id) or {}
    local preferred = tostring(location.entry_target_name or "")
    local target = preferred ~= "" and Entities:FindByName(nil, preferred) or nil
    if valid(target) then return target, preferred, false, location end
    local fallback = tostring(room_locations.marker_name(action.fallback_target_name, player_id) or "")
    target = fallback ~= "" and Entities:FindByName(nil, fallback) or nil
    if valid(target) then
        print(string.format(
            "[TRAINING_ROOM] marker_missing preferred=%s fallback=%s",
            preferred,
            fallback
        ))
        return target, fallback, true, location
    end
    return nil, preferred ~= "" and preferred or fallback, false
end

local function remove_prepared_target(target)
    if valid(target) then
        local removed, result = pcall(UTIL_Remove, target)
        if (not removed or result == false) and target.RemoveSelf then
            pcall(target.RemoveSelf, target)
        end
    end
end

local function clear_target(state)
    if state then remove_prepared_target(state.target) end
    if state then state.target = nil end
end

local function clear_state(player_id, reason)
    local state = state_by_player[player_id]
    if not state then
        technology_stat_manager.set_training_room_state(
            player_id, false, 1, "", reason or "training_room_exit"
        )
        return
    end
    scheduler.cancel("training_room_fee:" .. tostring(player_id))
    clear_target(state)
    state_by_player[player_id] = nil
    technology_stat_manager.set_training_room_state(
        player_id, false, 1, "", reason or "training_room_exit"
    )
end

local function spawn_target(player_id, action, marker, location)
    local unit_name = tostring(action.target_unit_name or "")
    if unit_name == "" then return nil end
    local origin = marker:GetAbsOrigin() + Vector(260, 0, 0)
    local target_name = location and (location.spawn_target_names or {})[1]
    local target_marker = target_name and Entities:FindByName(nil, target_name)
    if valid(target_marker) then origin = target_marker:GetAbsOrigin() end
    -- Retain the handle before fallible native setup so a rejected entry never
    -- leaves a partially configured training target behind.
    local target
    local ok = pcall(function()
        target = CreateUnitByName(unit_name, origin, true, nil, nil, DOTA_TEAM_BADGUYS)
        if not valid(target) then return end
        target.survival_training_owner_player_id = player_id
        target.survival_display_name = "长青轮纹"
        local health = math.max(1, tonumber(action.target_health) or 1000000000)
        target:SetBaseMaxHealth(health)
        target:SetMaxHealth(health)
        target:SetHealth(health)
        target:SetPhysicalArmorBaseValue(tonumber(action.target_armor) or 100000)
        target:AddNewModifier(target, nil, "modifier_endless_training_target", {
            health_regen = tonumber(action.target_health_regen) or 100000000,
        })
        FindClearSpaceForUnit(target, origin, true)
    end)
    if not ok then remove_prepared_target(target); return nil end
    return target
end

local function effective_costs(player_id, action)
    local discounted = require("systems/commerce_effects").owned(player_id, "growth_ring")
    local function cost(raw)
        local value = math.max(0, tonumber(raw) or 0)
        return discounted and math.floor(value * .75 + .5) or value
    end
    return cost(action.gold_cost), cost(action.gold_cost_per_second)
end

local function spend(player_id, team, gold, reason)
    return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        player_id = player_id,
        team = team,
        wood = 0,
        gold = math.max(0, tonumber(gold) or 0),
        population = 0,
        reason = reason,
    })
end

local function start_fee_task(player_id, state)
    local cost = math.max(0, tonumber(state.action.gold_cost_per_second) or 0)
    if cost <= 0 then return end
    scheduler.every(1, function()
        local current = state_by_player[player_id]
        if current ~= state then return false end
        if not alive(state.hero) then
            clear_state(player_id, "training_room_hero_unavailable")
            return false
        end
        if state.room_origin and state.room_radius then
            local distance = (state.hero:GetAbsOrigin() - state.room_origin):Length2D()
            if distance > state.room_radius then
                clear_state(player_id, "training_room_left_area")
                notify(
                    player_id,
                    "已离开" .. tostring(state.action.name) .. "，停止扣费"
                )
                return false
            end
        end
        local _, periodic_cost = effective_costs(player_id, state.action)
        local result = spend(player_id, state.team, periodic_cost, "endless_training_periodic_fee")
        if not result or not result.ok then
            clear_state(player_id, "training_room_gold_not_enough")
            notify(
                player_id,
                "金币不足，无法支付每秒费用，已离开" .. tostring(state.action.name),
                "error"
            )
            return_home.return_unit(state.hero, player_id)
            return false
        end
        return true
    end, "training_room_fee:" .. tostring(player_id))
end

local function enter_room(player_id, action_id)
    player_id = tonumber(player_id)
    local action = action_for(action_id)
    if player_id == nil then return { ok = false, error = "player_id_invalid" } end
    if not action then return { ok = false, error = "training_room_action_missing" } end
    local hero = hero_for(player_id)
    if not hero then return { ok = false, error = "请先召唤英雄" } end
    local required = tonumber(action.required_rebirth_level) or 0
    local rebirth = tonumber(progression_for(player_id).rebirth_level) or 0
    if rebirth < required then
        return { ok = false, error = "需要英雄" .. tostring(required) .. "转" }
    end
    local team = hero:GetTeamNumber()
    -- Preserve the existing entry + first-second reserve, but quote and debit
    -- the same owned discount. This is one O(1) cached entitlement lookup.
    local entry_cost, periodic_cost = effective_costs(player_id, action)
    local minimum_gold = entry_cost + periodic_cost
    local resources = event_bus.request(events.RESOURCE_GET_REQUEST, {
        player_id = player_id,
        team = team,
    })
    if not resources or resources.ok == false then
        return { ok = false, error = "资源状态暂不可用，请稍后再试" }
    end
    if (tonumber(resources.gold) or 0) < minimum_gold then
        return {
            ok = false,
            error = "金币不足，进入" .. tostring(action.name)
                .. "至少需要" .. tostring(minimum_gold)
                .. "金币（入场费" .. tostring(entry_cost)
                .. (periodic_cost > 0
                    and "，1秒后首笔扣费" .. tostring(periodic_cost)
                    or "") .. "），当前" .. tostring(tonumber(resources.gold) or 0) .. "金币",
        }
    end
    local marker, marker_name, _, location = marker_for(action, player_id)
    if not valid(marker) then
        return { ok = false, error = "传送地点不存在：" .. tostring(marker_name) }
    end
    local position = marker:GetAbsOrigin()
    local destination_ok, destination_error = destination_validation.validate(position, hero)
    if not destination_ok then
        return { ok = false, error = "传送落点暂不可用，请稍后重试", reason = destination_error }
    end
    local previous_state = state_by_player[player_id]
    local original = hero:GetAbsOrigin()
    original = Vector(original.x, original.y, original.z)
    local target = nil
    if tostring(action.target_unit_name or "") ~= "" then
        target = spawn_target(player_id, action, marker, location)
        if not valid(target) then
            return { ok = false, error = "练功目标生成失败" }
        end
    end
    local function rollback()
        -- Do not call return_home: it clears the existing room/encounter.
        if valid(hero) then pcall(hero.SetOrigin, hero, original) end
        remove_prepared_target(target)
    end
    local move_ok, moved, move_error = pcall(function()
        hero:Stop()
        ProjectileManager:ProjectileDodge(hero)
        return destination_validation.teleport(hero, position, false)
    end)
    if not move_ok or not moved then
        rollback()
        return { ok = false, error = "传送落点暂不可用，请稍后重试",
            reason = move_ok and move_error or "teleport_failed" }
    end
    -- Native preparation must not commit to a replaced hero or changed room.
    if hero_for(player_id) ~= hero or state_by_player[player_id] ~= previous_state then
        rollback()
        return { ok = false, error = "英雄状态已变化，请重试" }
    end
    local paid = spend(player_id, team, entry_cost, "altar_travel_entry:" .. action.action_id)
    if not paid or not paid.ok then
        rollback()
        return { ok = false, error = paid and paid.error == "gold_not_enough"
            and "金币不足" or "资源状态暂不可用，请稍后再试" }
    end

    clear_state(player_id, "training_room_replace")

    local multiplier = math.max(
        1,
        tonumber(action.training_room_income_multiplier) or 1
    )
    local state = {
        player_id = player_id,
        team = team,
        hero = hero,
        action = action,
        room_origin = position,
        room_radius = math.max(
            256,
            tonumber((location or {}).room_radius)
                or 1200
        ),
    }
    state.target = target
    state_by_player[player_id] = state
    technology_stat_manager.set_training_room_state(
        player_id,
        multiplier > 1,
        multiplier,
        action.action_id,
        "training_room_enter"
    )
    start_fee_task(player_id, state)
    notify(
        player_id,
        "已进入" .. tostring(action.name)
            .. (periodic_cost > 0
                and "，1秒后开始每秒消耗" .. tostring(periodic_cost) .. "金币"
                or "")
    )
    return { ok = true, action_id = action.action_id, marker_name = marker_name }
end

function M.enter(player_id, action_id)
    player_id = tonumber(player_id)
    if not player_id or player_id < 0 or player_id ~= math.floor(player_id) then
        return { ok = false, error = "player_id_invalid" }
    end
    if entering_by_player[player_id] then return { ok = false, error = "正在进入，请稍候" } end
    local token = {}
    entering_by_player[player_id] = token
    local ok, result = pcall(enter_room, player_id, action_id)
    if entering_by_player[player_id] == token then entering_by_player[player_id] = nil end
    if not ok then
        print("[TRAINING_ROOM] entry_failed player=" .. tostring(player_id) .. " error=" .. tostring(result))
        return { ok = false, error = "进入失败，请稍后重试" }
    end
    return result
end

function M.exit(player_id, reason)
    clear_state(tonumber(player_id), reason or "training_room_exit")
    return { ok = true }
end

function M.init()
    state_by_player = {}
    entering_by_player = {}
    event_bus.handle_request(events.TRAINING_ROOM_EXIT_REQUEST, function(payload)
        return M.exit(payload.player_id, payload.reason)
    end)
end

return M
