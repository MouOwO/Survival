local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/workers_config")
local training_definitions = require("config/generated/training_definitions")
local global_rules = require("config/global_rules")
local technology_stat_manager = require("systems/technology_stat_manager")
local worker_training_progress = require("systems/worker_training_progress")
local armor_balance = require("config/armor_balance")
local rogue_effect_state = require("systems/rogue_effect_state_service")

local M = {}
local workers = {}
local current_tree_entindex = -1
local tree_lumber_efficiency_buff = 0
local population_training_counts = {}
local lumberjack_training = worker_training_progress.create(training_definitions)
local repairer_training = worker_training_progress.create(
    training_definitions,
    "train_repairer_",
    "repairer"
)
local population_training_rows = {}
for _, row in ipairs(training_definitions.rows or {}) do
    if row.enabled ~= false and row.training_type == "population_upgrade" then
        population_training_rows[#population_training_rows + 1] = row
    end
end
table.sort(population_training_rows, function(left, right)
    return (tonumber(left.level) or 0) < (tonumber(right.level) or 0)
end)

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function add_training_abilities(worker, training)
    for _, ability_name in ipairs(training.active_skill_ids or {}) do
        if ability_name ~= "" then
            local ability = worker:FindAbilityByName(ability_name)
            if not ability then ability = worker:AddAbility(ability_name) end
            if ability and ability:GetLevel() < 1 then ability:SetLevel(1) end
        end
    end
end

local function active_worker_count(team, training_id)
    local count = 0
    for _, state in pairs(workers) do
        if state.team == team and state.training_id == training_id
            and valid_entity(state.unit) then
            count = count + 1
        end
    end
    return count
end

local function repairer_training_state(team, training_id, player_id)
    local progress = repairer_training:get_for(team, training_id)
    if not progress then return nil end

    progress.total_trained = progress.count
    progress.count = active_worker_count(team, training_id)
    progress.max_count = (tonumber(progress.max_count) or 0)
        + rogue_effect_state.numeric(
            player_id,
            "repairer_training_capacity_flat:" .. tostring(training_id)
        )
    local maximum = tonumber(progress.max_count) or 0
    progress.completed = maximum > 0 and progress.count >= maximum and 1 or 0
    return progress
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

local function population_training_state(team)
    local key = tonumber(team) or team
    local counts = population_training_counts[key] or {}
    local current = nil
    local current_index = nil
    local count = 0
    local maximum = 0
    local total_count = 0
    local total_max_count = 0
    for index, row in ipairs(population_training_rows) do
        local row_count = counts[row.training_id] or 0
        local row_maximum = tonumber(row.max_count) or 0
        total_count = total_count + row_count
        if row_maximum > 0 then
            total_max_count = total_max_count + row_maximum
        end
        if not current and (row_maximum <= 0 or row_count < row_maximum) then
            current = row
            current_index = index
            count = row_count
            maximum = row_maximum
        end
    end
    local next_row = current_index and population_training_rows[current_index + 1] or nil
    local completed = current == nil
    local wood_cost = current and ((tonumber(current.wood_cost) or 0)
        + count * (tonumber(current.wood_cost_increment) or 0)) or 0
    local gold_cost = current and ((tonumber(current.gold_cost) or 0)
        + count * (tonumber(current.gold_cost_increment) or 0)) or 0
    return {
        training_id = current and current.training_id or nil,
        name = current and current.name or "人口训练",
        level = current and (tonumber(current.level) or current_index) or #population_training_rows,
        count = count,
        max_count = maximum,
        total_count = total_count,
        total_max_count = total_max_count,
        completed = completed and 1 or 0,
        wood_cost = wood_cost,
        gold_cost = gold_cost,
        population_add = current and (tonumber(current.population_add) or 0) or 0,
        prerequisite_text = current and current.prerequisite_text or "",
        requires_farm_level = required_city_level(current),
        next_prerequisite_text = next_row and next_row.prerequisite_text or "已完成",
        next_requires_farm_level = next_row and required_city_level(next_row) or nil,
    }
end

local function record_population_training_success(team, training_id)
    local key = tonumber(team) or team
    local state = population_training_state(key)
    if state.completed == 1 then return state end
    if training_id and state.training_id ~= training_id then
        return nil, "population_training_not_current"
    end
    population_training_counts[key] = population_training_counts[key] or {}
    population_training_counts[key][state.training_id] = state.count + 1
    return population_training_state(key)
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

local function train_worker_one(payload)
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
        local population_state = population_training_state(city_state.team)
        if population_state.completed == 1 or not population_state.training_id then
            return { ok = false, error = "人口训练已完成" }
        end
        training_id = population_state.training_id
    elseif city_state.building_id ~= "main_city" then
        return { ok = false, error = "not_main_city" }
    end
    local is_lumberjack_request = training_id == "train_lumberjack_auto"
        or string.match(training_id, "^train_lumberjack_") ~= nil
    local is_repairer_request = training_id == "train_repairer_auto"
        or string.match(training_id, "^train_repairer_") ~= nil
    if is_lumberjack_request then
        local current = lumberjack_training:current(city_state.team)
        if not current then
            return { ok = false, error = "lumberjack_training_missing" }
        end
        training_id = current.training_id
    elseif is_repairer_request then
        if training_id == "train_repairer_auto" then
            training_id = "train_repairer_01"
        end
        local progress = repairer_training_state(
            city_state.team, training_id, city_state.player_id
        )
        if not progress then
            return { ok = false, error = "repairer_training_missing" }
        end
        if progress.completed == 1 and payload.allow_extra_slot ~= true then
            return { ok = false, error = tostring(progress.name) .. "训练已完成" }
        end
    end
    local training = (training_definitions.by_id or {})[training_id]
    if not training or training.enabled == false then
        return { ok = false, error = "training_definition_invalid" }
    end
    if training.training_type == "population_upgrade" then
        local team = city_state.team
        local state = population_training_state(team)
        if state.completed == 1 or state.training_id ~= training_id then
            return { ok = false, error = "人口训练阶段无效" }
        end
        local farm_level = tonumber(city_state.level) or 1
        if farm_level < state.requires_farm_level then
            local error_message = "农场达到LV" .. tostring(state.requires_farm_level)
                .. "后才能进行下一次人口训练"
            notify(city_state.player_id, error_message, "error")
            return { ok = false, error = error_message }
        end
        local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
            team = team,
            wood = state.wood_cost,
            gold = state.gold_cost,
            population = 0,
            reason = "train:" .. training_id,
        })
        if not spend or not spend.ok then return spend end
        local completed_state = record_population_training_success(team, training_id)
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = team,
            max_population = tonumber(training.population_add) or 0,
            reason = "population_training:" .. training_id,
        })
        notify(city_state.player_id, tostring(training.name) .. "完成")
        event_bus.emit(events.WORKER_CHANGED, {
            team = team,
            population_training = completed_state,
        })
        return {
            ok = true,
            population_add = training.population_add,
            training = completed_state,
        }
    end
    if training.training_type ~= "unit" then
        return { ok = false, error = "training_type_invalid" }
    end
    local is_lumberjack = string.match(training_id, "^train_lumberjack_") ~= nil
    if is_lumberjack or is_repairer_request then
        local required_level = required_city_level(training)
        if (tonumber(city_state.level) or 1) < required_level then
            local error_message = "主城达到LV" .. tostring(required_level)
                .. "后才能训练" .. tostring(training.name)
            notify(city_state.player_id, error_message, "error")
            return { ok = false, error = error_message }
        end
    end
    if is_repairer_request and payload.allow_extra_slot ~= true then
        local progress = repairer_training_state(
            city_state.team, training_id, city_state.player_id
        )
        local max_count = (tonumber(training.max_count) or 0)
            + rogue_effect_state.numeric(
                city_state.player_id,
                "repairer_training_capacity_flat:" .. tostring(training_id)
            )
        if not progress or (max_count > 0 and progress.count >= max_count) then
            return { ok = false, error = "training_max_count_reached" }
        end
    elseif not is_lumberjack then
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

    local wood_cost = payload.wood_cost_override ~= nil
        and math.max(0, tonumber(payload.wood_cost_override) or 0)
        or tonumber(training.wood_cost) or 0
    local gold_cost = payload.gold_cost_override ~= nil
        and math.max(0, tonumber(payload.gold_cost_override) or 0)
        or tonumber(training.gold_cost) or 0
    local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = city_state.team,
        wood = wood_cost,
        gold = gold_cost,
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
            wood = wood_cost,
            gold = gold_cost,
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
    worker.survival_player_id = city_state.player_id
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
    add_training_abilities(worker, training)
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
            repair_max_health_pct_per_second = tonumber(
                training.repair_max_health_pct_per_second
            ) or 0,
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
    elseif is_repairer and payload.skip_training_progress ~= true then
        repairer_training:record_explicit(
            city_state.team,
            training_id
        )
        training_progress = repairer_training_state(
            city_state.team, training_id, city_state.player_id
        )
    end
    notify(city_state.player_id, tostring(training.name) .. "训练完成")
    local changed = {
        team = city_state.team,
        player_id = city_state.player_id,
        count_delta = 1,
        unit = worker,
        entindex = worker:entindex(),
        worker_type = is_repairer and "repairer" or "lumberjack",
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

local function remove_worker(worker, entindex, reason)
    entindex = tonumber(entindex)
        or (worker and worker.entindex and worker:entindex())
    if not entindex then return nil end

    local state = workers[entindex]
    if not state then return end

    workers[entindex] = nil
    event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
        team = state.team,
        population = state.population,
        reason = reason or (state.worker_type .. "_died"),
    })
    event_bus.emit(events.WORKER_CHANGED, {
        team = state.team,
        count_delta = -1,
    })
    return state
end

local function dismiss_worker(payload)
    local worker = payload and payload.worker
    if not valid_entity(worker) then
        return { ok = false, error = "worker_invalid" }
    end
    local state = workers[worker:entindex()]
    if not state or state.worker_type ~= "repairer" then
        return { ok = false, error = "repairer_not_registered" }
    end

    local entindex = worker:entindex()
    worker:ForceKill(false)
    remove_worker(worker, entindex, payload.reason or "repairer_suicide")
    return { ok = true }
end

local function run_batch_training(count, create_one, rollback_one)
    local created = {}
    for _ = 1, count do
        local one = create_one()
        if not one or not one.ok then
            for index = #created, 1, -1 do rollback_one(created[index]) end
            return one or { ok = false, error = "worker_create_failed" }
        end
        created[#created + 1] = one.entindex
    end
    return { ok = true, entindices = created, count = #created }
end

local function train_worker(payload)
    payload = payload or {}
    local count = payload.source == "rogue_reward"
        and math.max(1, math.floor(tonumber(payload.count) or 1)) or 1
    if count == 1 then return train_worker_one(payload) end

    local training = (training_definitions.by_id or {})[payload.training_id]
    if not training or training.enabled == false then
        return { ok = false, error = "training_definition_invalid" }
    end
    local city = payload.city
    if not valid_entity(city) then return { ok = false, error = "invalid_city" } end
    local city_state = event_bus.request(events.BUILDING_QUERY_REQUEST, {
        entindex = city:entindex(),
    })
    if not city_state then return { ok = false, error = "training_building_missing" } end
    local resources = event_bus.request(events.RESOURCE_GET_REQUEST, {
        team = city_state.team,
    })
    local population_cost = math.max(0, tonumber(training.population_cost) or 0) * count
    if not resources or resources.population + population_cost > resources.max_population then
        return { ok = false, error = "population_not_enough" }
    end

    return run_batch_training(count, function()
        return train_worker_one({
            city = city,
            training_id = payload.training_id,
            wood_cost_override = payload.wood_cost_override,
            gold_cost_override = payload.gold_cost_override,
            allow_extra_slot = true,
            skip_training_progress = true,
        })
    end, function(entindex)
        local worker = EntIndexToHScript(entindex)
        if valid_entity(worker) then
            dismiss_worker({ worker = worker, reason = "rogue_training_rollback" })
        end
    end)
end

local function on_entity_killed(payload)
    remove_worker(
        payload.victim,
        payload.victim_entindex
            or (payload.keys and payload.keys.entindex_killed),
        nil
    )
end

function M.init()
    workers = {}
    current_tree_entindex = -1
    tree_lumber_efficiency_buff = 0
    population_training_counts = {}
    lumberjack_training:reset()
    repairer_training:reset()
    event_bus.handle_request(events.WORKER_TRAIN_REQUEST, train_worker)
    event_bus.handle_request(events.WORKER_DISMISS_REQUEST, dismiss_worker)
    event_bus.handle_request(events.WORKER_LIST_REQUEST, function(payload)
        local result = {}
        local player_id = tonumber(payload and payload.player_id)
        for _, worker in pairs(workers) do
            if (player_id == nil or worker.player_id == player_id)
                and valid_entity(worker.unit) then
                result[#result + 1] = worker
            end
        end
        return result
    end)
    event_bus.handle_request(
        events.WORKER_TRAINING_GET_REQUEST,
        function(payload)
            if payload and payload.training_type == "population_upgrade" then
                return population_training_state(payload.team)
            end
            if payload and payload.training_type == "repairer" then
                if payload.training_id then
                    return repairer_training_state(
                        payload.team,
                        payload.training_id,
                        payload.player_id
                    )
                end
                local progress = repairer_training:get(payload.team)
                progress.max_count = (tonumber(progress.max_count) or 0)
                    + rogue_effect_state.numeric(
                        payload.player_id,
                        "repairer_training_capacity_flat:"
                            .. tostring(progress.training_id)
                    )
                progress.completed = progress.max_count > 0
                    and progress.count >= progress.max_count and 1 or 0
                return progress
            end
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

M._population_training_state_for_test = population_training_state
M._record_population_training_success_for_test = record_population_training_success
M._train_worker_for_test = train_worker
M._run_batch_training_for_test = run_batch_training
M._reset_population_training_for_test = function()
    population_training_counts = {}
end

return M
