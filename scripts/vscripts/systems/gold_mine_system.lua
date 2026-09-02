local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local config = require("config/gold_mine_config")
local building_visual = require("systems/building_visual_service")
local upgrade_process = require("systems/building_upgrade_process")
local building_sound = require("systems/building_sound_service")
local technology_stat_manager = require("systems/technology_stat_manager")

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

local function permanent_stats(player_id)
    -- Gold mines can be initialized by isolated map/test flows before the
    -- permanent-profile service has registered its request handler.
    local ok, result = pcall(
        event_bus.request,
        events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
        { player_id = player_id }
    )
    if not ok then return {} end
    return result and result.totals or {}
end

local function profile_income(state, base_amount)
    local permanent = permanent_stats(state.player_id)
    local technology = {}
    local technology_ok, technology_state = pcall(
        technology_stat_manager.get,
        state.player_id
    )
    if technology_ok and technology_state then
        technology = technology_state.final.gold_mine or {}
    end
    local percent = (tonumber(technology.income_bonus_pct) or 0)
        + (tonumber(permanent.gold_mine_efficiency_pct) or 0)
        + (tonumber(permanent.gold_mine_yield_bonus_pct) or 0)
    local amount = ((tonumber(base_amount) or 0)
        + (tonumber(permanent.gold_mine_yield_flat) or 0))
        * (1 + percent / 100)
        + (tonumber(permanent.gold_mine_final_output_flat) or 0)
    local interval = math.max(0.05, config.production_interval
        - (tonumber(permanent.gold_mine_income_interval_reduction) or 0))
    return math.max(0, amount), interval, percent
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
    local level_data = config.level_data(state.mine_level) or {}
    local normal_income, effective_interval, profile_percent = profile_income(
        state,
        config.normal_income(state.mine_level, efficiency_level)
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
        income_per_second = normal_income / effective_interval,
        efficiency_percent = config.efficiency_percent(efficiency_level)
            + profile_percent,
        efficiency_bonus = config.efficiency_bonus(
            tonumber(level_data.base_income) or 0,
            efficiency_level
        ),
        crit_chance = config.crit_chance(crit_level),
        crit_multiplier = config.crit_multiplier(state.mine_level),
        auto_upgrading = auto_upgrade_by_entindex[state.unit:entindex()]
            and 1 or 0,
        upgrade_in_progress = state.unit.survival_upgrade_in_progress and 1 or 0,
        upgrade_target_level = state.unit.survival_upgrade_target_level,
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
        player_id = state.player_id,
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

local function auto_technology_leader(player_id)
    local leader = nil
    for entindex, enabled in pairs(auto_upgrade_by_entindex) do
        local state = enabled and state_by_entindex[entindex] or nil
        if state and player_id_for(state) == player_id
            and valid(state.unit) and state.unit:IsAlive()
            and (leader == nil or entindex < leader) then
            leader = entindex
        end
    end
    return leader
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
        if result and result.ok then return 1.1 end
        return 2.0
    end

    if auto_technology_leader(player_id_for(state)) ~= entindex then
        return 2.0
    end

    local efficiency_level = tonumber(technology.gold_mine_efficiency) or 0
    if efficiency_level < config.max_efficiency_level then
        local result = purchase_technology(state, "gold_mine_efficiency")
        if result and result.ok then
            publish(state)
            return 1.0
        end
        return 2.0
    end

    local crit_level = tonumber(technology.gold_mine_crit) or 0
    if crit_level < config.max_crit_level then
        local result = purchase_technology(state, "gold_mine_crit")
        if result and result.ok then
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

local function auto_state(payload)
    local state = state_from_payload(payload)
    if not state or not valid(state.unit) or not state.unit:IsAlive() then
        return { ok = false, error = "金矿不存在" }
    end
    local entindex = state.unit:entindex()
    return {
        ok = true,
        enabled = auto_upgrade_by_entindex[entindex] == true,
    }
end

local function toggle_auto_upgrade(payload)
    local state = state_from_payload(payload)
    if not state or not valid(state.unit) or not state.unit:IsAlive() then
        return { ok = false, message = "金矿不存在" }
    end
    local entindex = state.unit:entindex()
    local current = auto_upgrade_by_entindex[entindex] == true
    local requested = payload.enabled
    local enabled = requested == nil and not current or requested == true
    if enabled == current then
        return {
            ok = true,
            changed = false,
            enabled = current,
            message = current and "金矿自动升级已经开启"
                or "金矿自动升级已经停止",
        }
    end
    if not enabled then
        auto_upgrade_by_entindex[entindex] = nil
        scheduler.cancel("gold_mine_auto_upgrade_" .. tostring(entindex))
        publish(state)
        return {
            ok = true,
            changed = true,
            enabled = false,
            message = "已停止金矿自动升级",
        }
    end
    local efficiency_level = technology_level(
        state.player_id,
        "gold_mine_efficiency"
    )
    local crit_level = technology_level(state.player_id, "gold_mine_crit")
    if state.mine_level >= config.max_mine_level
        and efficiency_level >= config.max_efficiency_level
        and crit_level >= config.max_crit_level then
        return { ok = false, message = "金矿本体、收益和暴击科技均已满级" }
    end
    auto_upgrade_by_entindex[entindex] = true
    publish(state)
    scheduler.after(
        0,
        function() return auto_upgrade_step(entindex) end,
        "gold_mine_auto_upgrade_" .. tostring(entindex)
    )
    return {
        ok = true,
        changed = true,
        enabled = true,
        message = "已开始金矿自动升级",
    }
end

local function apply_level_stats(state)
    local data = config.level_data(state.mine_level)
    if not data or not valid(state.unit) then return end
    state.unit:SetBaseMaxHealth(data.health)
    state.unit:SetMaxHealth(data.health)
    state.unit:SetHealth(data.health)
    state.unit:SetPhysicalArmorBaseValue(data.armor)
    state.unit.survival_armor = tonumber(data.armor) or 0
    state.unit.survival_level = state.mine_level
    building_visual.apply(state.unit, data)
end

upgrade_mine = function(payload)
    local state = state_from_payload(payload)
    if not state then return { ok = false, error = "金矿不存在" } end
    if upgrade_process.is_active(state.unit) then
        return { ok = false, error = "金矿正在升级中" }
    end
    if state.mine_level >= config.max_mine_level then
        return { ok = false, error = "金矿已达到最高等级" }
    end
    local cost = config.mine_upgrade_cost(state.mine_level)
    if not cost then
        return { ok = false, error = "金矿下一等级升级费用未配置" }
    end
    local result = spend(state, cost, "gold_mine_level_upgrade")
    if not result or not result.ok then return result end
    local target_level = state.mine_level + 1
    local target_data = config.level_data(target_level)
    local pending = upgrade_process.begin(state.unit, {
        duration = 1.0,
        particle = state.definition and state.definition.build_particle,
        target_level = target_level,
        target_model_asset_id = target_data and target_data.model_asset_id,
        target_model_name = target_data and target_data.model_name,
        on_start = function() publish(state) end,
        on_visual_status = function() publish(state) end,
        on_complete = function()
            state.mine_level = target_level
            state.unit.__building_level = target_level
            apply_level_stats(state)
            publish(state)
            event_bus.emit(events.BUILDING_CHANGED, {
                unit = state.unit, entindex = state.unit:entindex(),
                player_id = state.player_id, team = state.team,
                building_id = "gold_mine", level = target_level,
            })
            if payload.silent_notification ~= true then
                event_bus.emit(events.UI_NOTIFICATION, {
                    player_id = state.player_id,
                    message = "金矿升级完成",
                    level = "info",
                })
            end
            building_sound.upgrade_completed({
                unit = state.unit,
                team = state.team,
                building_id = "gold_mine",
            })
        end,
        on_cancel = function() publish(state) end,
    })
    if not pending or not pending.ok then return pending end
    return { ok = true, pending = true, level = target_level }
end

local function level_upgrade_quote(payload)
    local state = state_from_payload(payload)
    if not state or not valid(state.unit) or not state.unit:IsAlive() then
        return { ok = false, error = "金矿不存在" }
    end
    if upgrade_process.is_active(state.unit) then
        return { ok = false, error = "金矿正在升级中" }
    end
    if state.mine_level >= config.max_mine_level then
        return { ok = false, error = "金矿已达到最高等级" }
    end
    local cost = config.mine_upgrade_cost(state.mine_level)
    if not cost then
        return { ok = false, error = "金矿下一等级升级费用未配置" }
    end
    return {
        ok = true,
        current_level = state.mine_level,
        target_level = state.mine_level + 1,
        wood = tonumber(cost.wood) or 0,
        gold = tonumber(cost.gold) or 0,
    }
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
        definition = payload.definition,
        player_id = payload.player_id,
        team = payload.team,
        mine_level = tonumber(payload.level) or 1,
    }
    publish(state_by_entindex[entindex])
end

local function on_destroyed(payload)
    if payload.building_id == "gold_mine" then
        upgrade_process.cancel_by_entindex(payload.entindex, "building_destroyed")
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
            local exact, effective_interval = profile_income(state, amount)
            exact = exact * config.production_interval / effective_interval
                + (tonumber(state.income_fraction) or 0)
            amount = math.floor(exact + 0.0000001)
            state.income_fraction = exact - amount
            local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
                player_id = state.player_id,
                team = state.team, gold = amount,
                reason = crit and "gold_mine_critical_income" or "gold_mine_income",
            })
            if result and result.ok then
                local player = PlayerResource:GetPlayer(state.player_id)
                if player then
                    CustomGameEventManager:Send_ServerToPlayer(
                        player,
                        "survival_gold_mine_income_number",
                        {
                            target_entindex = state.unit:entindex(),
                            amount = math.floor(amount + 0.5),
                            critical = crit and 1 or 0,
                        }
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
    event_bus.handle_request(
        events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST,
        level_upgrade_quote
    )
    event_bus.handle_request(events.GOLD_MINE_AUTO_STATE_REQUEST, auto_state)
    event_bus.handle_request(events.GOLD_MINE_AUTO_UPGRADE_REQUEST, toggle_auto_upgrade)
    event_bus.handle_request(events.GOLD_MINE_LEVEL_UPGRADE_REQUEST, upgrade_mine)
    event_bus.subscribe(events.TECHNOLOGY_CHANGED, on_technology_changed)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, function(payload)
        for _, state in pairs(state_by_entindex) do
            if state.player_id == tonumber(payload and payload.player_id) then
                publish(state)
            end
        end
    end)
    event_bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED, function(payload)
        for _, state in pairs(state_by_entindex) do
            if state.player_id == tonumber(payload and payload.player_id) then
                publish(state)
            end
        end
    end)
    event_bus.subscribe(events.BUILDING_CREATED, on_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_destroyed)
    scheduler.every(config.production_interval, tick, "gold_mine_production")
end

return M
