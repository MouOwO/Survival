local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("config/gold_mine_config")

local M = {}
local mines = {}

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function notify(state, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = state.player_id,
        message = message,
        level = level or "info",
    })
end

local function public_state(state, reason)
    return {
        unit = state.unit,
        entindex = state.unit:entindex(),
        team = state.team,
        player_id = state.player_id,
        building_id = "gold_mine",
        level = 1,
        mine_level = state.mine_level,
        crit_level = state.crit_level,
        efficiency = state.mine_level,
        normal_income = config.normal_income(state.mine_level),
        crit_chance = config.crit_chance(state.crit_level),
        crit_multiplier = config.crit_multiplier,
        reason = reason,
    }
end

local function publish(state, reason)
    event_bus.emit(events.GOLD_MINE_CHANGED, public_state(state, reason))
end

local function state_from_mine(mine)
    if not valid_entity(mine) then return nil end
    return mines[mine:entindex()]
end

local function spend(state, cost, reason)
    return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = state.team,
        wood = cost.wood or 0,
        gold = cost.gold or 0,
        population = 0,
        reason = reason,
    })
end

local function upgrade_efficiency(payload)
    local state = state_from_mine(payload.mine)
    if not state then return end
    if state.mine_level >= config.max_level then
        notify(state, "金矿采集效率已达到最高等级", "error")
        return
    end

    local cost = config.efficiency_upgrade_cost(state.mine_level)
    local result = spend(state, cost, "gold_mine_efficiency_upgrade")
    if not result or not result.ok then
        notify(state, result and result.error or "金币不足", "error")
        return
    end

    state.mine_level = state.mine_level + 1
    publish(state, "efficiency_upgraded")
    notify(state, "金矿采集效率提升至Lv." .. tostring(state.mine_level))
end

local function upgrade_crit(payload)
    local state = state_from_mine(payload.mine)
    if not state then return end
    if state.crit_level >= config.max_crit_level then
        notify(state, "金矿暴击率已达到最高等级", "error")
        return
    end

    local cost = config.crit_upgrade_cost(state.crit_level)
    local result = spend(state, cost, "gold_mine_crit_upgrade")
    if not result or not result.ok then
        notify(state, result and result.error or "金币不足", "error")
        return
    end

    state.crit_level = state.crit_level + 1
    publish(state, "crit_upgraded")
    notify(state, string.format(
        "金矿暴击率提升至Lv.%d（%d%%）",
        state.crit_level,
        config.crit_chance(state.crit_level)
    ))
end

local function produce_income(state)
    if not valid_entity(state.unit) or not state.unit:IsAlive() then return false end

    local amount = config.normal_income(state.mine_level)
    local chance = config.crit_chance(state.crit_level)
    local critical = chance > 0 and RandomFloat(0, 100) < chance
    if critical then amount = amount * config.crit_multiplier end

    event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = state.team,
        gold = amount,
        reason = critical and "gold_mine_critical_income" or "gold_mine_income",
    })
    return true
end

local function production_tick()
    for entindex, state in pairs(mines) do
        if not produce_income(state) then mines[entindex] = nil end
    end
    return true
end

local function on_building_created(payload)
    if payload.building_id ~= "gold_mine" or not valid_entity(payload.unit) then return end
    local state = {
        unit = payload.unit,
        team = payload.team,
        player_id = payload.player_id,
        mine_level = 1,
        crit_level = 0,
    }
    mines[payload.entindex] = state
    publish(state, "created")
end

local function on_building_destroyed(payload)
    if payload.building_id ~= "gold_mine" then return end
    mines[payload.entindex] = nil
end

function M.init()
    mines = {}
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_building_destroyed)
    event_bus.subscribe(events.GOLD_MINE_UPGRADE_REQUEST, upgrade_efficiency)
    event_bus.subscribe(events.GOLD_MINE_CRIT_UPGRADE_REQUEST, upgrade_crit)
    scheduler.every(config.production_interval, production_tick, "gold_mine_production")
end

return M
