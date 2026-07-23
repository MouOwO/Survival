local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("config/gold_mine_config")

local M = {}
local state_by_entindex = {}
local technology_by_player = {}
local auto_upgrade_by_entindex = {}
local auto_sequence = 0
local upgrade_mine
local GOLD_MINE_ABILITIES = {
    level = "ability_upgrade_gold_mine",
    efficiency = "ability_upgrade_gold_mine_efficiency",
    crit = "ability_upgrade_gold_mine_crit",
    auto = "ability_gold_mine_auto_upgrade",
    stop_auto = "ability_gold_mine_stop_auto_upgrade",
}

local function valid(entity)
    return entity and not entity:IsNull()
end

local function technology_level(player_id, group)
    local levels = technology_by_player[player_id]
    if not levels then
        local result = event_bus.request(
            events.TECHNOLOGY_STATE_GET_REQUEST,
            { player_id = player_id }
        )
        levels = result and result.levels or {}
        technology_by_player[player_id] = levels
    end
    return tonumber(levels[group]) or 0
end

local function set_ability_visible(unit, ability_name, visible)
    local ability = unit:FindAbilityByName(ability_name)
    if not ability then return end
    ability:SetHidden(not visible)
    ability:SetActivated(visible)
end

local function sync_abilities(state)
    if not valid(state.unit) then return end
    local entindex = state.unit:entindex()
    local auto = auto_upgrade_by_entindex[entindex] == true
    local efficiency_level = technology_level(
        state.player_id, "gold_mine_efficiency"
    )
    local crit_level = technology_level(state.player_id, "gold_mine_crit")
    local mine_pending = state.mine_level < config.max_mine_level
    local efficiency_pending = efficiency_level < config.max_efficiency_level
    local crit_pending = crit_level < config.max_crit_level
    local anything_pending = mine_pending or efficiency_pending or crit_pending

    set_ability_visible(
        state.unit, GOLD_MINE_ABILITIES.level, not auto and mine_pending
    )
    set_ability_visible(
        state.unit, GOLD_MINE_ABILITIES.efficiency,
        not auto and efficiency_pending
    )
    set_ability_visible(
        state.unit, GOLD_MINE_ABILITIES.crit, not auto and crit_pending
    )
    set_ability_visible(
        state.unit, GOLD_MINE_ABILITIES.auto, not auto and anything_pending
    )
    set_ability_visible(state.unit, GOLD_MINE_ABILITIES.stop_auto, auto)
end

local function publish(state)
    if not valid(state.unit) then return end
    sync_abilities(state)
    local efficiency_level = technology_level(
        state.player_id,
        "gold_mine_efficiency"
    )
    local crit_level = technology_level(
        state.player_id,
        "gold_mine_crit"
    )
    event_bus.emit(events.GOLD_MINE_CHANGED, {
        unit = state.unit,
        entindex = state.unit:entindex(),
        player_id = state.player_id,
        team = state.team,
        building_id = "gold_mine",
        level = state.mine_level,
        mine_level = state.mine_level,
        efficiency_level = efficiency_level,
        crit_level = crit_level,
        income_per_second = config.normal_income(state.mine_level, efficiency_level),
        efficiency_percent = config.efficiency_percent(efficiency_level),
        crit_chance = config.crit_chance(crit_level),
        crit_multiplier = config.crit_multiplier(state.mine_level),
        auto_upgrading = auto_upgrade_by_entindex[state.unit:entindex()]
            and 1 or 0,
        max_mine_level = config.max_mine_level,
        max_efficiency_level = config.max_efficiency_level,
        max_crit_level = config.max_crit_level,
    })
end

local function state_from_payload(payload)
    local entindex = tonumber(payload.entindex)
    if not entindex or not state_by_entindex[entindex] then return nil end
    return state_by_entindex[entindex]
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

local function player_id_for(state)
    return tonumber(state.player_id)
end

local function purchase_technology(state, group)
    auto_sequence = auto_sequence + 1
    return event_bus.request(events.TECHNOLOGY_PURCHASE_NEXT_REQUEST, {
        player_id = player_id_for(state),
        technology_group = group,
        source = "gold_mine_ability",
        entindex = state.unit:entindex(),
        request_id = "gold_mine_auto_"
            .. tostring(state.unit:entindex()) .. "_" .. tostring(auto_sequence),
    })
end

local function auto_upgrade_step(entindex)
    local state = state_by_entindex[entindex]
    if not auto_upgrade_by_entindex[entindex]
        or not state or not valid(state.unit) then
        return false
    end

    local technology = technology_by_player[player_id_for(state)]
    if not technology then
        local result = event_bus.request(
            events.TECHNOLOGY_STATE_GET_REQUEST,
            { player_id = player_id_for(state) }
        )
        technology = result and result.levels or {}
        technology_by_player[player_id_for(state)] = technology
    end

    if state.mine_level < config.max_mine_level then
        local result = upgrade_mine({ entindex = entindex })
        if result and result.ok then return 1.0 end
        return 2.0
    end

    local efficiency_level = tonumber(technology.gold_mine_efficiency) or 0
    if efficiency_level < config.max_efficiency_level then
        local result = purchase_technology(state, "gold_mine_efficiency")
        if result and result.ok then
            technology.gold_mine_efficiency = efficiency_level + 1
            publish(state)
            return 1.0
        end
        return 2.0
    end

    local crit_level = tonumber(technology.gold_mine_crit) or 0
    if crit_level < config.max_crit_level then
        local result = purchase_technology(state, "gold_mine_crit")
        if result and result.ok then
            technology.gold_mine_crit = crit_level + 1
            publish(state)
            return 1.0
        end
        return 2.0
    end

    auto_upgrade_by_entindex[entindex] = nil
    publish(state)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id_for(state),
        message = "金矿本体、收益和暴击科技均已满级",
        level = "info",
    })
    return false
end

local function toggle_auto_upgrade(payload)
    local state = state_from_payload(payload)
    if not state then return { ok = false, message = "金矿不存在" } end
    local entindex = state.unit:entindex()
    if auto_upgrade_by_entindex[entindex] then
        auto_upgrade_by_entindex[entindex] = nil
        scheduler.cancel("gold_mine_auto_upgrade_" .. tostring(entindex))
        publish(state)
        return { ok = true, message = "已停止金矿自动升级" }
    end
    auto_upgrade_by_entindex[entindex] = true
    publish(state)
    scheduler.after(
        0,
        function() return auto_upgrade_step(entindex) end,
        "gold_mine_auto_upgrade_" .. tostring(entindex)
    )
    return { ok = true, message = "已开始金矿自动升级" }
end

local function apply_level_stats(state)
    local data = config.level_data(state.mine_level)
    if not data or not valid(state.unit) then return end
    state.unit:SetBaseMaxHealth(data.health)
    state.unit:SetMaxHealth(data.health)
    state.unit:SetHealth(data.health)
    state.unit:SetPhysicalArmorBaseValue(data.armor)
    state.unit.survival_level = state.mine_level
end

upgrade_mine = function(payload)
    local state = state_from_payload(payload)
    if not state then return { ok = false, error = "金矿不存在" } end
    if state.mine_level >= config.max_mine_level then
        return { ok = false, error = "金矿已达到最高等级" }
    end
    local cost = config.mine_upgrade_cost(state.mine_level)
    if not cost then
        return { ok = false, error = "金矿下一等级升级费用未配置" }
    end
    local result = spend(state, cost, "gold_mine_level_upgrade")
    if not result or not result.ok then return result end
    state.mine_level = state.mine_level + 1
    state.unit.__building_level = state.mine_level
    apply_level_stats(state)
    publish(state)
    event_bus.emit(events.BUILDING_CHANGED, {
        unit = state.unit, entindex = state.unit:entindex(),
        player_id = state.player_id, team = state.team,
        building_id = "gold_mine", level = state.mine_level,
    })
    return { ok = true, level = state.mine_level }
end

local function on_technology_changed(payload)
    technology_by_player[payload.player_id] = payload.levels or {}
    for _, state in pairs(state_by_entindex) do
        if state.player_id == payload.player_id then
            publish(state)
        end
    end
end

local function on_created(payload)
    if payload.building_id ~= "gold_mine" or not valid(payload.unit) then return end
    local entindex = payload.unit:entindex()
    state_by_entindex[entindex] = {
        unit = payload.unit,
        player_id = payload.player_id,
        team = payload.team,
        mine_level = tonumber(payload.level) or 1,
    }
    publish(state_by_entindex[entindex])
end

local function on_destroyed(payload)
    if payload.building_id == "gold_mine" then
        local entindex = tonumber(payload.entindex)
        auto_upgrade_by_entindex[entindex] = nil
        scheduler.cancel("gold_mine_auto_upgrade_" .. tostring(entindex))
        state_by_entindex[payload.entindex] = nil
    end
end

local function tick()
    for entindex, state in pairs(state_by_entindex) do
        if not valid(state.unit) or not state.unit:IsAlive() then
            state_by_entindex[entindex] = nil
        else
            local efficiency_level = technology_level(
                state.player_id,
                "gold_mine_efficiency"
            )
            local crit_level = technology_level(
                state.player_id,
                "gold_mine_crit"
            )
            local crit = RandomFloat(0, 100) < config.crit_chance(crit_level)
            local amount = config.income_amount(
                state.mine_level,
                efficiency_level,
                crit
            )
            local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
                team = state.team, gold = amount,
                reason = crit and "gold_mine_critical_income" or "gold_mine_income",
            })
            if result and result.ok then
                local player = PlayerResource:GetPlayer(state.player_id)
                SendOverheadEventMessage(
                    player,
                    OVERHEAD_ALERT_GOLD,
                    state.unit,
                    amount,
                    nil
                )
                if crit then
                    SendOverheadEventMessage(
                        player,
                        OVERHEAD_ALERT_CRITICAL,
                        state.unit,
                        amount,
                        nil
                    )
                end
            end
        end
    end
    return config.production_interval
end

function M.init()
    state_by_entindex = {}
    technology_by_player = {}
    auto_upgrade_by_entindex = {}
    auto_sequence = 0
    event_bus.handle_request(events.GOLD_MINE_AUTO_UPGRADE_REQUEST, toggle_auto_upgrade)
    event_bus.handle_request(events.GOLD_MINE_LEVEL_UPGRADE_REQUEST, upgrade_mine)
    event_bus.subscribe(events.TECHNOLOGY_CHANGED, on_technology_changed)
    event_bus.subscribe(events.BUILDING_CREATED, on_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_destroyed)
    scheduler.every(config.production_interval, tick, "gold_mine_production")
end

return M
