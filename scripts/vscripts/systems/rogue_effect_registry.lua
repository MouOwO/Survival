local event_bus = require("core/event_bus")
local events = require("core/events")
local effect_state = require("systems/rogue_effect_state_service")
local builder_effects = require("systems/rogue_builder_start_effect_service")

local worker_attack_cap = require("systems/worker_native_attack_cap")
local tower_routes = require("config/tower_route_config")
local armor_balance = require("config/armor_balance")
local registered_lanes = require("systems/registered_wave_lane_view")

local M = {}
local handlers = {}

local function valid(unit)
    return unit and not unit:IsNull()
end

local function split_set(value)
    local result = {}
    for item in string.gmatch(tostring(value or ""), "[^|]+") do
        result[item] = true
    end
    return result
end

local function building_list(player_id)
    local result = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = player_id,
    }) or {}
    return result.buildings or result
end

local function apply_enemy_slow(instance, unit)
    if not valid(unit) or (unit.survival_is_wave_monster ~= true
        and unit.survival_is_challenge_monster ~= true) then return false end
    unit:AddNewModifier(unit, nil, "modifier_rogue_enemy_attack_speed", {
        value = tonumber(instance.params.value) or -15,
    })
    return true
end

local function refresh_recruit_tower(instance, building)
    local unit = building and building.unit
    if not valid(unit) then return end
    local record_id = tostring(building.record_id
        or unit.survival_tower_record_id or "")
    local eligible = building.building_id == "arrow_tower"
        and split_set(instance.params.target_record_ids)[record_id] == true
    if eligible then
        unit:AddNewModifier(unit, nil, "modifier_rogue_base_tower_attack", {
            value = tonumber(instance.params.value) or 100,
        })
    elseif unit:HasModifier("modifier_rogue_base_tower_attack") then
        unit:RemoveModifierByName("modifier_rogue_base_tower_attack")
    end
end

local function refresh_attack_projection(instance, building)
    local unit = building and building.unit
    if not valid(unit) or building.building_id ~= "arrow_tower" then return end
    if instance.effect.effect_type == "ballista_damage_bonus_pct" then
        local stages = split_set(instance.params.target_stage_ids)
        unit.survival_rogue_ballista_projection = stages[
            tostring(unit.survival_tower_stage_id or "")
        ] and (tonumber(instance.params.value) or 30) or 0
    end
    -- Ballista eligibility belongs to this tower. Only the frozen network
    -- snapshot is shared by every tower owned by the player.
    local value = (tonumber(unit.survival_rogue_ballista_projection) or 0)
        + effect_state.tower_projection(instance.player_id, "max_tower_count_attack_bonus_pct")
    local modifier = unit:FindModifierByName("modifier_rogue_tower_attack_projection")
    if value > 0 then
        if not modifier or tonumber(modifier.value) ~= value then
            unit:AddNewModifier(unit, nil, "modifier_rogue_tower_attack_projection", { value = value })
        end
        unit.survival_rogue_tower_projection = value
    else
        if modifier then modifier:Destroy() end
        unit.survival_rogue_tower_projection = nil
    end
end

local function team_for(instance)
    return PlayerResource:GetTeam(instance.player_id)
end

local function owned_wall(instance)
    for _, building in ipairs(building_list(instance.player_id)) do
        if building.building_id == "wall" and valid(building.unit) then
            return building.unit
        end
    end
end

local function all_units()
    return registered_lanes.append(Entities and Entities.FindAllByClassname
        and Entities:FindAllByClassname("npc_dota_creature") or {})
end

local function builder_for(instance)
    local result = event_bus.request(events.BUILDER_GET_REQUEST, {
        player_id = instance.player_id,
    }) or {}
    return result.builder or result.unit
end

local function grant_item(instance, item_name, charges)
    local builder = builder_for(instance)
    if not valid(builder) then return false, "builder_unavailable" end
    local item = CreateItem(item_name, builder, builder)
    if not item then return false, "item_create_failed" end
    if charges and item.SetCurrentCharges then item:SetCurrentCharges(charges) end
    local added = builder:AddItem(item)
    if not added then
        UTIL_Remove(item)
        return false, "builder_inventory_full"
    end
    return true
end

local function apply_combat_modifier(instance, unit)
    if not valid(unit) or tonumber(unit.survival_player_id) ~= instance.player_id then
        return false
    end
    local is_tower = unit.survival_building_id == "arrow_tower"
    local is_hero = unit.IsRealHero and unit:IsRealHero()
    if not is_tower and not is_hero then return false end
    unit:AddNewModifier(unit, nil, "modifier_rogue_combat_bonus", {
        player_id = instance.player_id,
    })
    return true
end

handlers.random_building_upgrade_count = {
    apply = function(instance)
        local count = math.max(0, math.floor(tonumber(instance.params.count) or 3))
        instance.upgrade_remaining = count
        local function finish(reason)
            instance.upgrade_remaining = 0
            instance.upgrade_target_entindex = nil
            instance.complete_on_apply = true
            instance.complete_reason = reason
            if instance.status == "active" then
                instance.status = "completed"
                instance.completed_reason = reason
            end
        end
        local function request_upgrade(building)
            local request = {
                building = building.unit, entindex = building.entindex,
                upgrade_mode = "one", player_id = instance.player_id,
                reason = "rogue_reward:infrastructure_maniac",
                system_free_upgrade = true, silent_notification = true,
            }
            local upgrade_event = building.building_id == "gold_mine"
                and events.GOLD_MINE_LEVEL_UPGRADE_REQUEST or events.BUILDING_UPGRADE_FREE_REQUEST
            return event_bus.request(upgrade_event, request)
        end
        local function next_upgrade(excluded_entindex)
            if instance.upgrade_remaining <= 0 then return end
            local eligible = {}
            for _, building in ipairs(building_list(instance.player_id)) do
                if building.entindex ~= excluded_entindex
                    and valid(building.unit) and building.unit:IsAlive()
                    and not building.unit.survival_upgrade_in_progress
                    and not building.unit:HasModifier("modifier_building_under_construction") then
                    local quote_event = building.building_id == "gold_mine"
                        and events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST or events.BUILDING_UPGRADE_QUOTE_REQUEST
                    local quote = event_bus.request(quote_event, {
                        building = building.unit,
                        entindex = building.entindex,
                        upgrade_mode = "one",
                        player_id = instance.player_id,
                        reason = "rogue_reward:infrastructure_maniac",
                    })
                    if quote and quote.ok == true then
                        eligible[#eligible + 1] = building
                    end
                end
            end
            -- Prefer another target after cancellation, but retain the reward
            -- if the cancelled building is the only eligible candidate left.
            if #eligible == 0 and excluded_entindex then return next_upgrade() end
            if #eligible == 0 then finish("upgrade_candidates_exhausted") return end
            local target = eligible[RandomInt(1, #eligible)]
            local result = request_upgrade(target)
            if result and result.ok then
                instance.upgrade_target_entindex = target.entindex
                return
            end
            -- A quote can become stale between selection and submission. Remove
            -- that target from this pass and try another quoted building.
            for index, candidate in ipairs(eligible) do
                if candidate == target then
                    table.remove(eligible, index)
                    break
                end
            end
            while #eligible > 0 do
                target = eligible[RandomInt(1, #eligible)]
                result = request_upgrade(target)
                if result and result.ok then
                    instance.upgrade_target_entindex = target.entindex
                    return
                end
                for index, candidate in ipairs(eligible) do
                    if candidate == target then
                        table.remove(eligible, index)
                        break
                    end
                end
            end
            finish("upgrade_candidates_exhausted")
        end
        instance.next_upgrade = next_upgrade
        next_upgrade()
        return true
    end,
    recompute = function(instance, payload)
        if not instance.next_upgrade or not payload
            or payload.player_id ~= instance.player_id
            or payload.entindex ~= instance.upgrade_target_entindex then return end
        local reason = tostring(payload.reason or "")
        local completed = reason:match("upgraded") ~= nil
        local cancelled = reason:match("^upgrade_cancelled_") ~= nil
            or not valid(payload.unit) or not payload.unit:IsAlive()
        if not completed and not cancelled then return end
        if completed then instance.upgrade_remaining = instance.upgrade_remaining - 1 end
        instance.upgrade_target_entindex = nil
        if instance.upgrade_remaining <= 0 then
            instance.status = "completed"
            instance.completed_reason = "upgrades_completed"
            return
        end
        event_bus.after_dispatch("rogue_random_upgrade:" .. tostring(instance.effect_instance_id or instance), function()
            if instance.status == "completed" then return end
            instance.next_upgrade(cancelled and payload.entindex or nil)
        end)
    end,
}

handlers.grant_building_upgrade_action = {
    apply = function(instance)
        local count = math.max(0, math.floor(tonumber(instance.params.count) or 1))
        if count < 1 then return false, "construction_order_count_invalid" end
        return grant_item(instance, "item_survival_rogue_building_upgrade", count)
    end,
}

handlers.ballista_damage_bonus_pct = {
    apply = function(instance)
        effect_state.add_effect(instance.player_id, instance.effect.effect_type)
        for _, building in ipairs(building_list(instance.player_id)) do refresh_attack_projection(instance, building) end
        return true
    end,
    recompute = function(instance, payload)
        if payload and payload.player_id == instance.player_id then
            effect_state.add_effect(instance.player_id, instance.effect.effect_type)
            refresh_attack_projection(instance, payload)
        end
    end,
}

handlers.slowed_target_damage_taken_pct = {
    apply = function(instance)
        effect_state.add_effect(instance.player_id, instance.effect.effect_type)
        return true
    end,
}

handlers.max_tower_count_attack_bonus_pct = {
    apply = function(instance)
        local count = 0
        for _, building in ipairs(building_list(instance.player_id)) do
            local route_state = {
                level = tonumber(building.level),
                tower_class = building.tower_class
                    or (building.unit and building.unit.survival_tower_class),
            }
            if building.building_id == "arrow_tower" and valid(building.unit)
                and route_state.level and route_state.tower_class
                and tower_routes.current(route_state)
                and not tower_routes.row_at_level(route_state, route_state.level + 1) then
                count = count + 1
            end
        end
        instance.snapshot_bonus = math.min(tonumber(instance.params.max_value) or 50,
            count * (tonumber(instance.params.value_per_target) or 5))
        effect_state.set_tower_projection(instance.player_id,
            instance.effect.effect_type, instance.snapshot_bonus)
        effect_state.add_effect(instance.player_id, instance.effect.effect_type)
        for _, building in ipairs(building_list(instance.player_id)) do
            refresh_attack_projection(instance, building)
        end
        return true
    end,
    recompute = function(instance, payload)
        if payload and payload.player_id == instance.player_id then
            refresh_attack_projection(instance, payload)
        end
    end,
}

handlers.owned_target_attacker_armor_reduction = {
    apply = function(instance)
        effect_state.add_effect(instance.player_id, instance.effect.effect_type)
        for _, unit in ipairs(all_units()) do
            if valid(unit) and (unit.survival_is_wave_monster == true
                or unit.survival_is_challenge_monster == true) then
                unit:AddNewModifier(unit, nil, "modifier_rogue_corrosive_shield_attack", {
                    armor_reduction_per_attack = armor_balance.from_war3_linear(
                        math.abs(tonumber(instance.params.value) or -1)),
                })
            end
        end
        return true
    end,
    recompute = function(instance, payload)
        local unit = payload and payload.unit
        if valid(unit) and (unit.survival_is_wave_monster == true
            or unit.survival_is_challenge_monster == true)
            and not unit:HasModifier("modifier_rogue_corrosive_shield_attack") then
            unit:AddNewModifier(unit, nil, "modifier_rogue_corrosive_shield_attack", {
                armor_reduction_per_attack = armor_balance.from_war3_linear(
                    math.abs(tonumber(instance.params.value) or -1)),
            })
        end
    end,
}

handlers.next_boss_attack_pct = {
    apply = function(instance)
        local wave = event_bus.request(events.WAVE_STATE_GET_REQUEST, {}) or {}
        if not wave.next_special_wave_number or not wave.next_special_role then
            instance.complete_on_apply = true
            instance.complete_reason = "special_target_unavailable"
            return true
        end
        instance.target_wave_number = tonumber(wave.next_special_wave_number)
        instance.target_member_role = tostring(wave.next_special_role)
        return true
    end,
    on_event = function(instance, payload)
        if payload.monster_source ~= "wave"
            or tonumber(payload.player_id) ~= instance.player_id
            or tonumber(payload.wave_number) ~= instance.target_wave_number
            or tostring(payload.member_role or "") ~= instance.target_member_role
            or not valid(payload.unit) then return false end
        payload.unit:AddNewModifier(payload.unit, nil, "modifier_rogue_weakening_attack", {
            value = tonumber(instance.params.value) or -50,
        })
        event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
            unit = payload.unit, entindex = payload.unit:entindex(),
            player_id = instance.player_id, reason = "rogue_weakening_orb",
        })
        return true
    end,
}

handlers.grant_random_cards = {
    apply = function(instance)
        local result = event_bus.request(events.ROGUE_REWARD_GRANT_RANDOM_REQUEST, {
            player_id = instance.player_id,
            parent_card_id = instance.card_id,
            parent_grant_id = instance.grant_id,
            reward_type = instance.reward_type,
            count = tonumber(instance.params.count) or 3,
        })
        return result and result.ok == true, result and result.error
    end,
}

handlers.tower_upgrade_attack_bonus_pct = {
    apply = function() return true end,
    recompute = function(instance, payload)
        if not payload or payload.building_id ~= "arrow_tower"
            or not string.match(tostring(payload.reason or ""), "^tower_upgraded_")
            or not valid(payload.unit) then return end
        payload.unit:AddNewModifier(payload.unit, nil, "modifier_rogue_tower_growth", {
            value = tonumber(instance.params.value) or 10,
            stacks = 1,
        })
    end,
}

handlers.wall_health_multiplier = {
    apply = function(instance)
        local wall = owned_wall(instance)
        if not wall then return false, "wall_missing" end
        local multiplier = math.max(1, tonumber(instance.params.multiplier) or 2)
        local old_max = math.max(1, tonumber(wall:GetMaxHealth()) or 1)
        local ratio = math.max(0, math.min(1, (tonumber(wall:GetHealth()) or 1) / old_max))
        local health_increase = math.max(0, math.floor(
            old_max * (multiplier - 1) + 0.5
        ))
        if not effect_state.add_wall_health_flat(instance.player_id, health_increase) then
            return false, "wall_health_state_failed"
        end
        local new_max = old_max + health_increase
        wall:SetBaseMaxHealth(new_max)
        wall:SetMaxHealth(new_max)
        wall:SetHealth(math.max(1, math.floor(new_max * ratio + 0.5)))
        return true
    end,
}

local function apply_lumberjack_speed(instance, worker)
    local unit = worker and worker.unit
    if worker and worker.player_id == instance.player_id
        and worker.worker_type ~= "repairer" and valid(unit) then
        local value = tonumber(instance.params.value) or 100
        if value ~= 0 then worker_attack_cap.restore_or_error(unit) end
        unit:AddNewModifier(unit, nil, "modifier_rogue_lumberjack_attack_speed", {
            value = value,
        })
    end
end

handlers.lumberjack_attack_speed_bonus_pct = {
    apply = function(instance)
        for _, worker in ipairs(event_bus.request(events.WORKER_LIST_REQUEST, {
            player_id = instance.player_id,
        }) or {}) do apply_lumberjack_speed(instance, worker) end
        return true
    end,
    recompute = function(instance, payload)
        apply_lumberjack_speed(instance, payload)
    end,
    remove = function(instance)
        for _, worker in ipairs(event_bus.request(events.WORKER_LIST_REQUEST, {
            player_id = instance.player_id,
        }) or {}) do
            if valid(worker.unit) then
                worker.unit:RemoveModifierByName("modifier_rogue_lumberjack_attack_speed")
            end
        end
    end,
}

handlers.grant_gold_flat = {
    apply = function(instance)
        local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
            player_id = instance.player_id,
            team = team_for(instance),
            gold = tonumber(instance.params.value) or 0,
            wood = 0,
            reason = "rogue_reward:" .. instance.card_id,
        })
        return result and result.ok == true, result and result.error
    end,
}

handlers.grant_current_wood_pct = {
    apply = function(instance)
        local team = team_for(instance)
        local resource = event_bus.request(events.RESOURCE_GET_REQUEST, {
            player_id = instance.player_id,
            team = team,
        }) or {}
        local amount = math.floor(
            (tonumber(resource.wood) or 0)
                * (tonumber(instance.params.value) or 0) / 100
        )
        local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
            player_id = instance.player_id,
            team = team,
            gold = 0,
            wood = amount,
            reason = "rogue_reward:" .. instance.card_id,
        })
        return result and result.ok == true, result and result.error
    end,
}

handlers.tower_attack_speed_bonus_pct = {
    apply = function(instance)
        local result = event_bus.request(events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST, {
            player_id = instance.player_id,
            effects = {{
                effect_type = instance.effect.effect_type,
                value = tonumber(instance.params.value) or 0,
            }},
            reason = "rogue_reward:" .. instance.card_id,
        })
        return result and result.ok == true, result and result.error
    end,
}

handlers.wall_attacker_attack_speed_pct = {
    apply = function(instance)
        local units = all_units()
        for _, unit in ipairs(units) do
            apply_enemy_slow(instance, unit)
        end
        return true
    end,
    recompute = function(instance, payload)
        apply_enemy_slow(instance, payload and payload.unit)
    end,
}

handlers.base_tower_attack_bonus_pct = {
    apply = function(instance)
        for _, building in ipairs(building_list(instance.player_id)) do
            refresh_recruit_tower(instance, building)
        end
        return true
    end,
    recompute = function(instance, payload)
        if payload and payload.building_id == "arrow_tower" then
            refresh_recruit_tower(instance, payload)
        end
    end,
}

handlers.wall_hit_damage_cap_pct = {
    apply = function(instance)
        return effect_state.set_wall_damage_cap(
            instance.player_id,
            tonumber(instance.params.value) or 20
        )
    end,
}

handlers.training_capacity_flat = {
    apply = function(instance)
        return effect_state.add_numeric(instance.player_id,
            "repairer_training_capacity_flat:"
                .. tostring(instance.params.training_id or "train_repairer_01"),
            tonumber(instance.params.value) or 2)
    end,
}

handlers.next_hero_reroll_count = {
    apply = function(instance)
        return effect_state.add_numeric(instance.player_id,
            "next_rogue_reroll_count:" .. tostring(instance.reward_type or "boss"),
            tonumber(instance.params.count) or 1)
    end,
}

handlers.challenge_reward_multiplier = {
    apply = function(instance)
        return effect_state.add_numeric(instance.player_id,
            "building_challenge_reward_doubles", tonumber(instance.params.count) or 5)
    end,
}

handlers.grant_nuclear_bomb_action = {
    apply = function(instance)
        local builder = builder_for(instance)
        if not valid(builder) then return false, "builder_unavailable" end
        local item = CreateItem("item_survival_rogue_nuclear_bomb", builder, builder)
        if not item then return false, "item_create_failed" end
        item.survival_nuclear_batch_size = math.max(1,
            math.floor(tonumber(instance.params.batch_size) or 1))
        item.survival_nuclear_batch_interval = math.max(0.01,
            tonumber(instance.params.batch_interval_seconds) or 0.05)
        local added = builder:AddItem(item)
        if not added then
            UTIL_Remove(item)
            return false, "builder_inventory_full"
        end
        return true
    end,
}

handlers.unit_attack_bonus_pct = {
    apply = function(instance)
        effect_state.add_numeric(instance.player_id,
            "unit_attack_bonus_pct", tonumber(instance.params.value) or 30)
        for _, building in ipairs(building_list(instance.player_id)) do
            apply_combat_modifier(instance, building.unit)
        end
        local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
            player_id = instance.player_id,
        }) or {}
        apply_combat_modifier(instance, summoned.unit or summoned.hero)
        return true
    end,
    recompute = function(instance, payload)
        apply_combat_modifier(instance, payload and payload.unit)
    end,
}

handlers.tower_hero_attack_projection_pct = {
    apply = function(instance)
        effect_state.add_numeric(instance.player_id,
            "tower_hero_attack_projection_pct", tonumber(instance.params.value) or 10)
        for _, building in ipairs(building_list(instance.player_id)) do
            apply_combat_modifier(instance, building.unit)
        end
        return true
    end,
    recompute = function(instance, payload)
        apply_combat_modifier(instance, payload and payload.unit)
    end,
}

handlers.physical_armor_ignore_pct = {
    apply = function(instance)
        return effect_state.add_numeric(instance.player_id,
            "physical_armor_ignore_pct", tonumber(instance.params.value) or 40)
    end,
}

handlers.hero_lifesteal_pct = {
    apply = function(instance)
        effect_state.add_numeric(instance.player_id, "hero_lifesteal_pct",
            tonumber(instance.params.initial_value) or 100)
        local summoned = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
            player_id = instance.player_id,
        }) or {}
        apply_combat_modifier(instance, summoned.unit or summoned.hero)
        return true
    end,
    remove_phase = function(instance)
        effect_state.add_numeric(instance.player_id, "hero_lifesteal_pct",
            -(tonumber(instance.params.initial_value) or 100))
    end,
    apply_phase = function(instance)
        effect_state.add_numeric(instance.player_id, "hero_lifesteal_pct",
            tonumber(instance.params.later_value) or 20)
    end,
    recompute = function(instance, payload)
        apply_combat_modifier(instance, payload and payload.unit)
    end,
}

handlers.building_count_gold = {
    apply = function(instance)
        local wave = event_bus.request(events.WAVE_STATE_GET_REQUEST, {}) or {}
        local difficulty = tonumber(tostring(wave.difficulty_id or ""):match("(%d+)$"))
        if not difficulty then return false, "difficulty_invalid" end
        local amount = #building_list(instance.player_id) * difficulty
            * (tonumber(instance.params.value_per_target) or 100)
        local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
            player_id = instance.player_id,
            team = team_for(instance), gold = amount, wood = 0,
            reason = "rogue_reward:" .. instance.card_id,
        })
        return result and result.ok == true, result and result.error
    end,
}

handlers.training_dummy_attack_gain = {
    apply = function(instance)
        local builder = builder_for(instance)
        if not valid(builder) then return false, "builder_unavailable" end
        local building_system = require("systems/building_system")
        local player_context = require("systems/player_context_service")
        local slot = player_context.slot(instance.player_id)
        local wall = building_system.wall_for_player(instance.player_id)
        local spawn_marker = slot and Entities:FindByName(
            nil, slot.wave_spawn_marker
        ) or nil
        if not valid(spawn_marker) and tonumber(instance.player_id) == 0 then
            spawn_marker = require("systems/monster_spawn_marker").find()
        end
        if not valid(wall) then return false, "training_dummy_wall_unavailable" end
        if not valid(spawn_marker) then return false, "training_dummy_spawn_unavailable" end
        local wall_position = wall:GetAbsOrigin()
        local spawn_position = spawn_marker:GetAbsOrigin()
        local direction = spawn_position - wall_position
        direction.z = 0
        if direction:Length2D() < 1 then
            return false, "training_dummy_direction_unavailable"
        end
        direction = direction:Normalized()
        local distance = math.max(1, tonumber(instance.params.distance) or 1)
        local position = wall_position + direction * distance
        position.z = GetGroundHeight(position, nil) + 32
        if GridNav and GridNav.IsTraversable then
            if not GridNav:IsTraversable(position) then
                return false, "training_dummy_position_blocked"
            end
        end
        local unit = CreateUnitByName("npc_survival_rogue_training_dummy",
            position, true, builder, builder, DOTA_TEAM_BADGUYS)
        if not valid(unit) then return false, "training_dummy_create_failed" end
        FindClearSpaceForUnit(unit, position, true)
        if (unit:GetAbsOrigin() - position):Length2D() > 96 then
            unit:ForceKill(false)
            return false, "training_dummy_position_unavailable"
        end
        unit.survival_player_id = instance.player_id
        unit.survival_is_training_dummy = true
        unit:AddNewModifier(unit, nil, "modifier_rogue_training_dummy", {
            duration = tonumber(instance.params.duration_seconds) or 30,
            value = tonumber(instance.params.value) or 100,
            wall_entindex = wall:entindex(),
        })
        return true
    end,
}

handlers.builder_start_effect = {
    apply = function(instance)
        return builder_effects.apply(instance)
    end,
    remove = function(instance, reason)
        builder_effects.remove(instance, reason)
    end,
}

function M.get(effect_type)
    return handlers[tostring(effect_type or "")]
end

function M.register_for_test(effect_type, handler)
    handlers[effect_type] = handler
end

return M
