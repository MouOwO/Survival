local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/workers_config")
local training_definitions = require("config/generated/training_definitions")
local global_rules = require("config/global_rules")
local technology_stat_manager = require("systems/technology_stat_manager")
local worker_training_progress = require("systems/worker_training_progress")
local armor_balance = require("config/armor_balance")

local M = {}
local workers = {}
local current_tree_entindex = -1
local tree_lumber_efficiency_buff = 0
local population_training_counts = {}
local lumberjack_training = worker_training_progress.create(training_definitions)

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function candidate_is_traversable(position)
    local ok_traversable, traversable = pcall(function()
        return GridNav:IsTraversable(position)
    end)
    if ok_traversable and not traversable then return false end

    local ok_blocked, blocked = pcall(function()
        return GridNav:IsBlocked(position)
    end)
    if ok_blocked and blocked then return false end
    return true
end

local function candidate_has_clearance(city, position)
    local units = FindUnitsInRadius(
        city:GetTeamNumber(),
        position,
        nil,
        config.nearby_unit_clearance or 128,
        DOTA_UNIT_TARGET_TEAM_BOTH,
        DOTA_UNIT_TARGET_ALL,
        DOTA_UNIT_TARGET_FLAG_NONE,
        FIND_ANY_ORDER,
        false
    )
    return #units == 0
end

local function find_worker_spawn_position(city)
    local origin = city:GetAbsOrigin()
    local min_radius = config.spawn_radius_min or 420
    if city.GetHullRadius then
        min_radius = math.max(
            min_radius,
            (city:GetHullRadius() or 0) + (config.spawn_clearance or 160)
        )
    end

    local max_radius = math.max(min_radius, config.spawn_radius_max or 640)
    local attempts = math.max(1, config.spawn_attempts or 24)

    for index = 1, attempts do
        local ratio = attempts == 1 and 0 or (index - 1) / (attempts - 1)
        local radius = min_radius + (max_radius - min_radius) * ratio
        local angle = RandomFloat(0, math.pi * 2)
        local candidate = origin + Vector(
            math.cos(angle) * radius,
            math.sin(angle) * radius,
            0
        )
        candidate.z = GetGroundHeight(candidate, city)

        if candidate_is_traversable(candidate)
            and candidate_has_clearance(city, candidate) then
            return candidate
        end
    end

    local fallback = origin + Vector(max_radius, 0, 0)
    fallback.z = GetGroundHeight(fallback, city)
    return fallback
end

local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end

local function required_city_level(training)
    local configured = tonumber(training and training.requires_city_level)
    if configured then return configured end
    return tonumber(string.match(
        tostring(training and training.prerequisite_text or ""),
        "LV(%d+)"
    )) or 1
end

local function lumberjack_training_state(team)
    return lumberjack_training:get(team)
end

local function refresh_worker_technology(player_id)
    local lumberjack = technology_stat_manager.get(player_id).final.lumberjack or {}
    local efficiency = tonumber(lumberjack.wood_per_hit_bonus) or 0
    local speed_pct = tonumber(lumberjack.attack_speed_bonus_pct) or 0
    local interval_reduction = tonumber(lumberjack.attack_interval_flat) or 0
    local crit_chance = tonumber(lumberjack.critical_chance_pct) or 0
    local attack_growth = tonumber(lumberjack.attack_flat) or 0
    local attack_gain_per_attack = tonumber(lumberjack.attack_gain_per_attack) or 0
    local armor_reduction = tonumber(lumberjack.armor_reduction_per_attack) or 0
    for entindex, state in pairs(workers) do
        if state.worker_type == "lumberjack"
            and state.player_id == player_id and valid_entity(state.unit) then
            local speed = math.max(0.01, (
                tonumber(state.base_attack_speed)
                    or tonumber(config.attack_rate) or 0.5
            ) * (1 + speed_pct / 100))
            local base_interval = 1 / speed
            state.unit:SetBaseAttackTime(math.max(0.05, base_interval - interval_reduction))
            local base_min = tonumber(state.base_damage_min)
            local base_max = tonumber(state.base_damage_max)
            if base_min ~= nil and base_max ~= nil then
                state.unit:SetBaseDamageMin(base_min + attack_growth)
                state.unit:SetBaseDamageMax(base_max + attack_growth)
                state.unit.survival_attack_min = base_min + attack_growth
                state.unit.survival_attack_max = base_max + attack_growth
            end
            state.technology_attack_growth = attack_growth
            state.technology_armor_reduction = armor_reduction
            state.technology_efficiency = efficiency
            state.technology_attack_gain_per_attack = attack_gain_per_attack
            local modifier = state.unit:FindModifierByName("modifier_lumberjack_ai")
            if modifier and modifier.SetTechnologyLumberEfficiency then
                modifier:SetTechnologyLumberEfficiency(state.technology_efficiency)
            end
            if modifier and modifier.SetTechnologyCritChance then
                modifier:SetTechnologyCritChance(crit_chance)
            end
            if modifier and modifier.SetTechnologyArmorReduction then
                modifier:SetTechnologyArmorReduction(armor_reduction)
            end
            if modifier and modifier.SetAttackGainPerAttack then
                modifier:SetAttackGainPerAttack(attack_gain_per_attack)
            end
        end
    end
end

local function on_technology_stats_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    refresh_worker_technology(player_id)
end

local function on_tree_hit(payload)
    if not payload or payload.source ~= "lumberjack" then return end
    local player_id = tonumber(payload.player_id)
    if player_id == nil then return end
    local lumberjack = technology_stat_manager.get(player_id).final.lumberjack or {}
    local amount = tonumber(lumberjack.attack_gain_per_attack) or 0
    if amount <= 0 then return end
    event_bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST, {
        player_id = player_id,
        section = "lumberjack",
        field = "attack",
        amount = amount,
        reason = "lumberjack_attack_growth",
    })
end

local function update_worker_efficiency()
    for entindex, state in pairs(workers) do
        if valid_entity(state.unit) then
            if state.worker_type == "lumberjack" then
                state.tree_lumber_efficiency_buff = tree_lumber_efficiency_buff
                state.lumber_efficiency = (state.base_lumber_efficiency or 0)
                    + tree_lumber_efficiency_buff
                    + (state.technology_efficiency or 0)
                local modifier = state.unit:FindModifierByName(
                    "modifier_lumberjack_ai"
                )
                if modifier and modifier.SetTreeLumberEfficiency then
                    modifier:SetTreeLumberEfficiency(
                        tree_lumber_efficiency_buff
                    )
                end
                if modifier and modifier.SetTechnologyLumberEfficiency then
                    modifier:SetTechnologyLumberEfficiency(
                        state.technology_efficiency or 0
                    )
                end
            end
        else
            workers[entindex] = nil
        end
    end
end

local function update_worker_targets()
    for entindex, state in pairs(workers) do
        if valid_entity(state.unit) then
            if state.worker_type == "lumberjack" then
                local modifier = state.unit:FindModifierByName(
                    "modifier_lumberjack_ai"
                )
                if modifier and modifier.SetTreeEntIndex then
                    modifier:SetTreeEntIndex(current_tree_entindex)
                end
            end
        else
            workers[entindex] = nil
        end
    end
end

local function train_worker(payload)
    local city = payload.city
    if not valid_entity(city) then
        print("[WorkerTrain] invalid city entity")
        return { ok = false, error = "invalid_city" }
    end

    local city_state = event_bus.request(events.BUILDING_QUERY_REQUEST, {
        entindex = city:entindex(),
    })
    if not city_state then
        print("[WorkerTrain] main city state missing entindex="
            .. tostring(city:entindex()))
        notify(city:GetPlayerOwnerID(), "主城训练状态尚未初始化", "error")
        return { ok = false, error = "training_building_missing" }
    end

    local training_id = tostring(
        payload.training_id or "train_lumberjack_auto"
    )
    if training_id == "train_population_auto" then
        if city_state.building_id ~= "building_farm"
            and city_state.building_id ~= "farm" then
            return { ok = false, error = "not_population_farm" }
        end
        training_id = string.format(
            "train_population_%02d",
            math.max(2, math.min(6, (tonumber(city_state.level) or 1) + 1))
        )
    elseif city_state.building_id ~= "main_city" then
        return { ok = false, error = "not_main_city" }
    end
    local is_lumberjack_request = training_id == "train_lumberjack_auto"
        or string.match(training_id, "^train_lumberjack_") ~= nil
    if is_lumberjack_request then
        local current = lumberjack_training:current(city_state.team)
        if not current then
            return { ok = false, error = "lumberjack_training_missing" }
        end
        training_id = current.training_id
    end
    local training = (training_definitions.by_id or {})[training_id]
    if not training or training.enabled == false then
        return { ok = false, error = "training_definition_invalid" }
    end
    if training.training_type == "population_upgrade" then
        local team = city_state.team
        population_training_counts[team] = population_training_counts[team] or {}
        local count = population_training_counts[team][training_id] or 0
        local maximum = tonumber(training.max_count) or 0
        if maximum > 0 and count >= maximum then
            return { ok = false, error = "该等级人口训练已达上限" }
        end
        local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
            team = team,
            wood = (tonumber(training.wood_cost) or 0)
                + count * (tonumber(training.wood_cost_increment) or 0),
            gold = (tonumber(training.gold_cost) or 0)
                + count * (tonumber(training.gold_cost_increment) or 0),
            population = 0,
            reason = "train:" .. training_id,
        })
        if not spend or not spend.ok then return spend end
        population_training_counts[team][training_id] = count + 1
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = team,
            max_population = tonumber(training.population_add) or 0,
            reason = "population_training:" .. training_id,
        })
        notify(city_state.player_id, tostring(training.name) .. "完成")
        return { ok = true, population_add = training.population_add }
    end
    if training.training_type ~= "unit" then
        return { ok = false, error = "training_type_invalid" }
    end
    local is_lumberjack = string.match(training_id, "^train_lumberjack_") ~= nil
    if is_lumberjack then
        local required_level = required_city_level(training)
        if (tonumber(city_state.level) or 1) < required_level then
            local error_message = "主城达到LV" .. tostring(required_level)
                .. "后才能训练" .. tostring(training.name)
            notify(city_state.player_id, error_message, "error")
            return { ok = false, error = error_message }
        end
    else
        local existing_count = 0
        for _, state in pairs(workers) do
            if state.training_id == training_id and valid_entity(state.unit) then
                existing_count = existing_count + 1
            end
        end
        local max_count = tonumber(training.max_count) or 0
        if max_count > 0 and existing_count >= max_count then
            return { ok = false, error = "training_max_count_reached" }
        end
    end

    local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = city_state.team,
        wood = tonumber(training.wood_cost) or 0,
        gold = tonumber(training.gold_cost) or 0,
        population = tonumber(training.population_cost) or 0,
        reason = "train:" .. training_id,
    })
    if not spend or not spend.ok then
        notify(city_state.player_id, spend and spend.error or "resource_error", "error")
        return spend
    end

    local spawn_position = find_worker_spawn_position(city)
    local worker = CreateUnitByName(
        training.unit_name or config.unit_name,
        spawn_position,
        true,
        city,
        city,
        city_state.team
    )
    if not worker then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = city_state.team,
            wood = tonumber(training.wood_cost) or 0,
            gold = tonumber(training.gold_cost) or 0,
            reason = "train_refund:" .. training_id,
        })
        event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
            team = city_state.team,
            population = tonumber(training.population_cost) or 0,
            reason = "train_refund:" .. training_id,
        })
        return { ok = false, error = "worker_create_failed" }
    end

    FindClearSpaceForUnit(worker, spawn_position, true)
    worker:SetControllableByPlayer(city_state.player_id, true)
    local health = tonumber(training.health) or config.health
    worker:SetBaseMaxHealth(health)
    worker:SetMaxHealth(health)
    worker:SetHealth(health)
    local war3_armor = tonumber(training.war3_armor or training.armor)
    worker:SetPhysicalArmorBaseValue(war3_armor ~= nil
        and armor_balance.from_war3(war3_armor)
        or config.armor)
    local base_attack = tonumber(training.base_attack)
    if base_attack ~= nil then
        worker:SetBaseDamageMin(base_attack)
        worker:SetBaseDamageMax(base_attack)
    end
    local attack_speed = math.max(
        0.01,
        tonumber(training.attack_rate) or config.attack_rate or 0.5
    )
    worker:SetBaseAttackTime(1 / attack_speed)
    worker.survival_attack_speed = attack_speed
    if not worker:HasModifier("modifier_debug_attack_cap") then
        worker:AddNewModifier(worker, nil, "modifier_debug_attack_cap", {})
    end
    worker:SetBaseMoveSpeed(tonumber(training.move_speed) or config.move_speed)
    local attack_range = math.max(0, tonumber(training.attack_range) or 400)
    if worker.Script_SetAttackRange then
        worker:Script_SetAttackRange(attack_range)
    end
    worker.survival_attack_range = attack_range
    if worker.SetAcquisitionRange then
        worker:SetAcquisitionRange(attack_range)
    end
    if training.model_name and training.model_name ~= "" then
        worker:SetModel(training.model_name)
        worker:SetOriginalModel(training.model_name)
    end
    local is_repairer = training_id:match("^train_repairer_") ~= nil
    local technology_efficiency = 0
    if is_repairer then
        worker:SetBaseDamageMin(0)
        worker:SetBaseDamageMax(0)
        if worker.SetAttackCapability then
            worker:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
        end
        worker.survival_worker_type = "repairer"
        worker:AddNewModifier(worker, nil, "modifier_repair_worker_ai", {
            repair_per_second = tonumber(training.repair_per_second) or 0,
            repair_range = tonumber(training.repair_range) or 200,
            detection_range = global_rules.repair_detection_range,
        })
    else
        worker.survival_worker_type = "lumberjack"
        if worker.SetRangedProjectileName then
            worker:SetRangedProjectileName("")
        end
        if worker.SetProjectileSpeed then
            worker:SetProjectileSpeed(10000)
        end
        if worker.SetAttackCapability then
            worker:SetAttackCapability(DOTA_UNIT_CAP_RANGED_ATTACK)
        end
        local lumberjack = technology_stat_manager.get(city_state.player_id).final.lumberjack or {}
        technology_efficiency = tonumber(lumberjack.wood_per_hit_bonus) or 0
        worker:AddNewModifier(worker, nil, "modifier_lumberjack_ai", {
            tree_entindex = current_tree_entindex,
            base_lumber_efficiency = tonumber(training.wood_per_hit)
                or config.wood_per_hit or 1,
            tree_lumber_efficiency_buff = tree_lumber_efficiency_buff,
            technology_lumber_efficiency = technology_efficiency,
            technology_crit_chance = tonumber(lumberjack.critical_chance_pct) or 0,
            technology_armor_reduction = tonumber(lumberjack.armor_reduction_per_attack) or 0,
            attack_gain_per_attack = tonumber(lumberjack.attack_gain_per_attack) or 0,
            player_id = city_state.player_id,
        })
    end

    workers[worker:entindex()] = {
        unit = worker,
        team = city_state.team,
        player_id = city_state.player_id,
        population = tonumber(training.population_cost) or 0,
        training_id = training_id,
        worker_type = is_repairer and "repairer" or "lumberjack",
        base_damage_min = base_attack,
        base_damage_max = base_attack,
        base_attack_speed = attack_speed,
        base_lumber_efficiency = tonumber(training.wood_per_hit) or 0,
        tree_lumber_efficiency_buff = tree_lumber_efficiency_buff,
        technology_efficiency = technology_efficiency,
        lumber_efficiency = (tonumber(training.wood_per_hit) or 0)
            + tree_lumber_efficiency_buff
            + technology_efficiency,
    }
    if not is_repairer then
        refresh_worker_technology(city_state.player_id)
    end
    local training_progress = nil
    if is_lumberjack then
        training_progress = lumberjack_training:record_success(
            city_state.team,
            training_id
        )
    end
    notify(city_state.player_id, tostring(training.name) .. "训练完成")
    local changed = {
        team = city_state.team,
        count_delta = 1,
        training = training_progress,
    }
    event_bus.emit(events.WORKER_CHANGED, changed)
    return {
        ok = true,
        entindex = worker:entindex(),
        training = training_progress,
    }
end

local function on_tree_spawned(payload)
    current_tree_entindex = payload.entindex or -1
    tree_lumber_efficiency_buff = math.max(
        0, tonumber(payload.lumber_efficiency_buff) or 0
    )
    update_worker_targets()
    update_worker_efficiency()
end

local function on_tree_destroyed(payload)
    current_tree_entindex = -1
    tree_lumber_efficiency_buff = math.max(
        0, tonumber(payload and payload.lumber_efficiency_buff) or 0
    )
    update_worker_targets()
    update_worker_efficiency()
end

local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) then return end
    local state = workers[victim:entindex()]
    if not state then return end

    workers[victim:entindex()] = nil
    event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
        team = state.team,
        population = state.population,
        reason = "lumberjack_died",
    })
    event_bus.emit(events.WORKER_CHANGED, {
        team = state.team,
        count_delta = -1,
    })
end

function M.init()
    workers = {}
    current_tree_entindex = -1
    tree_lumber_efficiency_buff = 0
    population_training_counts = {}
    lumberjack_training:reset()
    event_bus.subscribe(events.WORKER_TRAIN_REQUEST, train_worker)
    event_bus.handle_request(
        events.WORKER_TRAINING_GET_REQUEST,
        function(payload)
            return lumberjack_training_state(payload.team)
        end
    )
    event_bus.subscribe(events.TREE_SPAWNED, on_tree_spawned)
    event_bus.subscribe(events.TREE_CHANGED, on_tree_spawned)
    event_bus.subscribe(events.TREE_DESTROYED, on_tree_destroyed)
    event_bus.subscribe(events.TREE_HIT, on_tree_hit)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, on_technology_stats_changed)
end

return M
