local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local actions = require("config/generated/altar_actions")
local locations = require("config/generated/challenge_locations")
local technology_stat_manager = require("systems/technology_stat_manager")
local return_home = require("systems/hero_return_home_service")

local M = {}
local state_by_player = {}

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

local function marker_for(action)
    local location = (locations.by_id or {})[action.location_id] or {}
    local preferred = tostring(location.entry_target_name or "")
    local target = preferred ~= "" and Entities:FindByName(nil, preferred) or nil
    if valid(target) then return target, preferred, false end
    local fallback = tostring(action.fallback_target_name or "")
    target = fallback ~= "" and Entities:FindByName(nil, fallback) or nil
    if valid(target) then
        print(string.format(
            "[TRAINING_ROOM] marker_missing preferred=%s fallback=%s",
            preferred,
            fallback
        ))
        return target, fallback, true
    end
    return nil, preferred ~= "" and preferred or fallback, false
end

local function clear_target(state)
    if state and valid(state.target) then UTIL_Remove(state.target) end
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

local function spawn_target(player_id, action, marker)
    local unit_name = tostring(action.target_unit_name or "")
    if unit_name == "" then return nil end
    local origin = marker:GetAbsOrigin() + Vector(260, 0, 0)
    local target = CreateUnitByName(
        unit_name, origin, true, nil, nil, DOTA_TEAM_BADGUYS
    )
    if not valid(target) then return nil end
    target.survival_training_owner_player_id = player_id
    target.survival_display_name = "无尽年轮"
    local health = math.max(1, tonumber(action.target_health) or 1000000000)
    target:SetBaseMaxHealth(health)
    target:SetMaxHealth(health)
    target:SetHealth(health)
    target:SetPhysicalArmorBaseValue(tonumber(action.target_armor) or 100000)
    target:AddNewModifier(target, nil, "modifier_endless_training_target", {
        health_regen = tonumber(action.target_health_regen) or 100000000,
    })
    FindClearSpaceForUnit(target, origin, true)
    return target
end

local function spend(team, gold, reason)
    return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
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
        if current ~= state or not alive(state.hero) then
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
        local result = spend(state.team, cost, "endless_training_periodic_fee")
        if not result or not result.ok then
            clear_state(player_id, "training_room_gold_not_enough")
            notify(
                player_id,
                "每秒费用不足，已离开" .. tostring(state.action.name),
                "error"
            )
            return_home.return_unit(state.hero, player_id)
            return false
        end
        return true
    end, "training_room_fee:" .. tostring(player_id))
end

function M.enter(player_id, action_id)
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
    local marker, marker_name = marker_for(action)
    if not valid(marker) then
        return { ok = false, error = "传送地点不存在：" .. tostring(marker_name) }
    end
    local team = hero:GetTeamNumber()
    local entry_cost = math.max(0, tonumber(action.gold_cost) or 0)
    local periodic_cost = math.max(
        0,
        tonumber(action.gold_cost_per_second) or 0
    )
    local minimum_gold = entry_cost + periodic_cost
    local resources = event_bus.request(events.RESOURCE_GET_REQUEST, {
        team = team,
    })
    if not resources then
        return { ok = false, error = "资源状态暂不可用，请稍后再试" }
    end
    if (tonumber(resources.gold) or 0) < minimum_gold then
        return {
            ok = false,
            error = "进入" .. tostring(action.name)
                .. "至少需要" .. tostring(minimum_gold)
                .. "金币（入场费" .. tostring(entry_cost)
                .. (periodic_cost > 0
                    and "，1秒后首笔扣费" .. tostring(periodic_cost)
                    or "") .. "）",
        }
    end
    local target = nil
    if tostring(action.target_unit_name or "") ~= "" then
        target = spawn_target(player_id, action, marker)
        if not valid(target) then
            return { ok = false, error = "练功目标生成失败" }
        end
    end
    local paid = spend(team, entry_cost, "altar_travel_entry:" .. action.action_id)
    if not paid or not paid.ok then
        if valid(target) then UTIL_Remove(target) end
        return { ok = false, error = "金币不足" }
    end

    clear_state(player_id, "training_room_replace")
    hero:Stop()
    ProjectileManager:ProjectileDodge(hero)
    local position = marker:GetAbsOrigin()
    hero:SetAbsOrigin(position)
    FindClearSpaceForUnit(hero, position, true)

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
            tonumber(((locations.by_id or {})[action.location_id] or {}).room_radius)
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

function M.exit(player_id, reason)
    clear_state(tonumber(player_id), reason or "training_room_exit")
    return { ok = true }
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(events.TRAINING_ROOM_EXIT_REQUEST, function(payload)
        return M.exit(payload.player_id, payload.reason)
    end)
end

return M