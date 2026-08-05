local event_bus = require("core/event_bus")
local events = require("core/events")
local arrow_tower_base = require("config/generated/arrow_tower_base")
local tower_routes = require("config/tower_route_config")
local tower_skills = require("systems/tower_skill_runtime")
local tower_ability_sync = require("systems/tower_ability_sync")
local global_rules = require("config/global_rules")
local tower_combat_rules = require("config/tower_combat_rules")
local technology_stat_manager = require("systems/technology_stat_manager")
local building_population = require("systems/building_population_service")
local building_visual = require("systems/building_visual_service")
local asset_preload = require("systems/asset_preload_service")
local upgrade_process = require("systems/building_upgrade_process")

local M = {}
local buildings = {}
local publish
local sync_tower_abilities

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

local function set_attack_range(unit, attack_range)
    attack_range = tonumber(attack_range) or global_rules.tower_attack_range
    if unit.Script_SetAttackRange then
        unit:Script_SetAttackRange(attack_range)
    elseif unit.SetAttackRange then
        unit:SetAttackRange(attack_range)
    end
    if unit.SetAcquisitionRange then
        -- Keep autonomous target acquisition at least as far as the attack range.
        unit:SetAcquisitionRange(math.max(
            global_rules.tower_acquisition_range,
            attack_range
        ))
    end
end

local function set_tower_projectile_speed(unit, configured_speed)
    local base_speed = tonumber(configured_speed)
    if not base_speed and unit.survival_base_projectile_speed == nil then
        base_speed = tonumber(global_rules.tower_base_projectile_speed)
        if not base_speed and unit.GetProjectileSpeed then
            base_speed = tonumber(unit:GetProjectileSpeed())
        end
    end
    if base_speed then unit.survival_base_projectile_speed = base_speed end
    base_speed = tonumber(unit.survival_base_projectile_speed)
    if base_speed and unit.SetProjectileSpeed then
        local projectile_speed = tower_combat_rules.projectile_speed(base_speed)
        unit:SetProjectileSpeed(projectile_speed)
        unit.survival_projectile_speed = projectile_speed
    end
end

local function apply_common(unit, data)
    unit:SetBaseMaxHealth(data.health)
    unit:SetMaxHealth(data.health)
    unit:SetHealth(data.health)
    unit:SetPhysicalArmorBaseValue(data.armor)
    unit.survival_armor = tonumber(data.armor) or 0
    building_visual.apply(unit, data)
end

local function arrow_data(level)
    for _, row in ipairs(arrow_tower_base.rows) do
        if row.level == level then return row end
    end
    return nil
end

local function configured_projectile_speed(state, row)
    if not state.tower_class then return row and row.projectile_speed end
    return tonumber(row and row.projectile_speed)
        or global_rules.tower_route_default_projectile_speed
end

local function apply_research_technology(state)
    local unit = state.unit
    if not valid_entity(unit) then return end
    local player_id = state.player_id
    local technology = technology_stat_manager.get(player_id).final
    if state.building_id == "arrow_tower" then
        local base_damage = tonumber(state.research_base_attack_damage)
            or unit:GetBaseDamageMin()
        local tower = technology.tower or {}
        local bonus = tonumber(tower.attack_flat) or 0
        local bonus_pct = tonumber(tower.attack_bonus_pct) or 0
        local damage = (base_damage + bonus) * (1 + bonus_pct / 100)
        unit:SetBaseDamageMin(damage)
        unit:SetBaseDamageMax(damage)
        unit.survival_attack_min = damage
        unit.survival_attack_max = damage
        unit.survival_super_tower_crit_chance =
            tonumber(tower.critical_chance_pct) or 0
        local attack_range = tower_combat_rules.attack_range(
            tower.attack_range_bonus
        )
        set_attack_range(unit, attack_range)
    elseif state.building_id == "wall" then
        local data = state.definition.levels[state.level or 1] or {}
        local base_health = tonumber(data.health) or unit:GetMaxHealth()
        local wall = technology.wall or {}
        local bonus_pct = (tonumber(wall.health_bonus_pct) or 0)
            + (tonumber(wall.technology_health_bonus_pct) or 0)
        local armor_bonus = tonumber(wall.technology_armor_bonus) or 0
        local old_max = math.max(1, unit:GetMaxHealth())
        local old_health = math.max(0, unit:GetHealth())
        local health_ratio = old_health / old_max
        local max_health = math.max(1, math.floor(base_health * (1 + bonus_pct / 100)))
        unit:SetBaseMaxHealth(max_health)
        unit:SetMaxHealth(max_health)
        unit:SetHealth(old_health > 0
            and math.max(1, math.floor(max_health * health_ratio)) or 0)
        local base_armor = tonumber(data.armor) or 0
        unit:SetPhysicalArmorBaseValue(base_armor + armor_bonus)
        unit.survival_armor = base_armor + armor_bonus
    end
end

local function team_city_level(team)
    local level = 0
    for _, building in pairs(buildings) do
        if building.team == team and building.building_id == "main_city"
            and valid_entity(building.unit) then
            level = math.max(level, tonumber(building.level) or 0)
        end
    end
    return level
end

local function refresh_farm_upgrade_ability(state)
    if not state or (state.building_id ~= "farm"
        and state.building_id ~= "building_farm")
        or not valid_entity(state.unit) then return end
    local ability = state.unit:FindAbilityByName("ability_upgrade_farm")
    if ability then
        local has_next_level = state.definition.levels[(state.level or 1) + 1] ~= nil
        ability:SetActivated(
            has_next_level and (state.level or 1) < team_city_level(state.team)
        )
    end
end

local function refresh_team_farms(team)
    for _, state in pairs(buildings) do
        if state.team == team then refresh_farm_upgrade_ability(state) end
    end
end


local function apply_tower(unit, data, level)
    apply_common(unit, data)
    if unit.SetAttackCapability then
        -- Arrow-tower route units are immobile. An empty projectile override
        -- means "keep the unit's/default projectile", not "become melee".
        -- Laser routes explicitly switch to melee contact after skill sync.
        unit:SetAttackCapability(DOTA_UNIT_CAP_RANGED_ATTACK)
    end
    local combat = arrow_data(level or 1) or {}
    local damage = tonumber(combat.base_attack_damage or data.damage) or 0
    unit:SetBaseDamageMin(damage)
    unit:SetBaseDamageMax(damage)
    unit.survival_attack_min = damage
    unit.survival_attack_max = damage
    local attacks_per_second = tonumber(data.base_attack_speed)
        or tonumber(combat.base_attack_speed) or 1
    attacks_per_second = math.max(0.01, attacks_per_second)
    unit.survival_attack_speed = attacks_per_second
    unit:SetBaseAttackTime(1 / attacks_per_second)
    if not unit:HasModifier("modifier_debug_attack_cap") then
        unit:AddNewModifier(unit, nil, "modifier_debug_attack_cap", {})
    end
    if not unit:HasModifier("modifier_tower_attack_effects") then
        unit:AddNewModifier(unit, nil, "modifier_tower_attack_effects", {})
    end
    if data.projectile_model and data.projectile_model ~= ""
        and unit.SetRangedProjectileName then
        unit:SetRangedProjectileName(data.projectile_model)
        unit.survival_projectile_model = data.projectile_model
    elseif tonumber(data.projectile_speed)
        and unit.SetRangedProjectileName then
        -- A configured speed with an empty model is an explicit invisible
        -- projectile (for example lightning), not an instruction to retain
        -- the previous route's arrow particle.
        unit:SetRangedProjectileName("")
        unit.survival_projectile_model = ""
    end
    set_tower_projectile_speed(unit, data.projectile_speed)
    set_attack_range(unit, global_rules.tower_attack_range)
end

local function set_class_buttons(unit, active)
    local state = buildings[unit:entindex()]
    if not state then return end
    for _, class_data in ipairs(state.definition.class_options or {}) do
        local ability = unit:FindAbilityByName(class_data.ability)
        if active and not ability then
            ability = unit:AddAbility(class_data.ability)
            if ability then ability:SetLevel(1) end
        end
        if ability then ability:SetActivated(active) end
    end
end

local function base_health(state)
    local definition = state.definition or {}
    local levels = definition.levels or definition.pre_class_levels or {}
    local data = levels[state.level] or {}
    return tonumber(data.health) or state.unit:GetMaxHealth()
end

publish = function(state, reason)
    local route_row = state.building_id == "arrow_tower"
        and tower_routes.current(state) or nil
    local display_name = state.unit.survival_display_name
        or state.tower_class_name
        or (route_row and route_row.name)
        or state.definition.display_name
    event_bus.emit(events.BUILDING_CHANGED, {
        entindex = state.unit:entindex(),
        team = state.team,
        player_id = state.player_id,
        building_id = state.building_id,
        level = state.level,
        absolute_level = state.level,
        route_level = route_row and route_row.level or state.level,
        tower_class = state.tower_class,
        tower_class_name = state.tower_class_name,
        display_name = display_name,
        attack_min = state.unit.survival_attack_min,
        attack_max = state.unit.survival_attack_max,
        runtime_armor = state.unit.survival_armor,
        attack_speed = state.unit.survival_attack_speed,
        base_health = base_health(state),
        base_attack_damage = state.building_id == "arrow_tower"
            and tonumber((arrow_data(state.level) or {}).base_attack_damage)
            or nil,
        upgrade_in_progress = state.unit.survival_upgrade_in_progress and 1 or 0,
        upgrade_target_level = state.unit.survival_upgrade_target_level,
        reason = reason,
    })
end

local function spend(state, cost, reason)
    if not cost then return { ok = false, error = "升级费用未配置" } end
    return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = state.team,
        wood = cost.wood or 0,
        gold = cost.gold or 0,
        population = 0,
        reason = reason,
    })
end

local function start_upgrade(state, target_data, target_level, on_complete, reason)
    return upgrade_process.begin(state.unit, {
        duration = 1.0,
        particle = state.definition.build_particle,
        target_level = target_level,
        target_model_asset_id = target_data and target_data.model_asset_id,
        target_model_name = target_data and target_data.model_name,
        on_start = function()
            publish(state, "upgrade_started_" .. tostring(reason))
        end,
        on_visual_status = function(status)
            publish(state, "upgrade_visual_" .. tostring(status))
        end,
        on_complete = function()
            on_complete()
            notify(state, "升级完成")
        end,
        on_cancel = function(cancel_reason)
            publish(state, "upgrade_cancelled_" .. tostring(cancel_reason))
        end,
    })
end

-- The upgrade system owns a runtime cache, while building_system owns the
-- authoritative building state. A script reload or an early ability click can
-- leave the cache empty even though the building is still valid.
local function recover_state(unit)
    if not valid_entity(unit) then return nil end

    local entindex = unit:entindex()
    local state = buildings[entindex]
    if state then return state end

    local snapshot = event_bus.request(events.BUILDING_QUERY_REQUEST, {
        entindex = entindex,
    })
    if not snapshot and unit:GetUnitName() == "building_arrow_tower" then
        snapshot = {
            unit = unit,
            definition = require("config/buildings_config").arrow_tower,
            team = unit:GetTeamNumber(),
            player_id = tonumber(unit.survival_player_id)
                or unit:GetPlayerOwnerID(),
            building_id = "arrow_tower",
            level = tonumber(unit.survival_level) or 1,
            tower_class = unit.survival_tower_class,
            tower_class_name = unit.survival_display_name,
            base_attack_damage = tonumber((arrow_data(
                tonumber(unit.survival_level) or 1
            ) or {}).base_attack_damage) or unit:GetBaseDamageMin(),
        }
        print("[BuildingUpgrade] recovered unregistered arrow tower entindex="
            .. tostring(entindex))
    end
    if not snapshot or not snapshot.unit or not snapshot.definition then
        return nil
    end

    state = {
        unit = snapshot.unit,
        definition = snapshot.definition,
        team = snapshot.team,
        player_id = snapshot.player_id,
        building_id = snapshot.building_id,
        level = tonumber(snapshot.level) or tonumber(unit.survival_level) or 1,
        tower_class = snapshot.tower_class,
        tower_class_name = snapshot.tower_class_name,
        tower_combat = nil,
        research_base_attack_damage = snapshot.base_attack_damage,
    }
    buildings[entindex] = state

    if state.building_id == "arrow_tower" then
        local row = tower_routes.current(state) or arrow_data(state.level)
        if row then
            unit.survival_route_level = tonumber(row.level) or state.level
            sync_tower_abilities(state, row)
            set_tower_projectile_speed(
                unit,
                configured_projectile_speed(state, row)
            )
        end
        apply_research_technology(state)
        if not unit:HasModifier("modifier_tower_attack_effects") then
            unit:AddNewModifier(unit, nil, "modifier_tower_attack_effects", {})
        end
    end
    refresh_farm_upgrade_ability(state)
    return state
end

local function recover_player_towers(player_id)
    local units = Entities:FindAllByClassname("npc_dota_creature") or {}
    local player_team = PlayerResource:GetTeam(player_id)
    for _, unit in ipairs(units) do
        local owned = tonumber(unit.survival_player_id) == player_id
            or unit:GetPlayerOwnerID() == player_id
            or unit:GetTeamNumber() == player_team
        if valid_entity(unit) and unit:GetUnitName() == "building_arrow_tower"
            and owned then
            local state = recover_state(unit)
            if state and (tonumber(state.player_id) or -1) < 0 then
                state.player_id = player_id
            end
        end
    end
end

local function on_technology_stats_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    recover_player_towers(player_id)
    for _, state in pairs(buildings) do
        if state.player_id == player_id then
            apply_research_technology(state)
            publish(state, "technology_stats_changed")
        end
    end
end

local function upgrade_wall(state)
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "城墙已达最高等级" } end
    if next_level > 1 and data.requires_city_level
        and data.requires_city_level > 0 then
        local city_level = 0
        for _, building in pairs(buildings) do
            if building.team == state.team
                and building.building_id == "main_city"
                and valid_entity(building.unit) then
                city_level = math.max(city_level, building.level or 0)
            end
        end
        if city_level < data.requires_city_level then
            return {
                ok = false,
                error = "基地达到Lv." .. tostring(data.requires_city_level)
                    .. "后才能升级城墙",
            }
        end
    end
    local result = spend(state, data.upgrade_cost, "upgrade_wall")
    if not result or not result.ok then return result end
    return start_upgrade(state, data, next_level, function()
        state.level = next_level
        state.unit.survival_level = next_level
        state.unit.survival_display_name = state.definition.display_name
        apply_common(state.unit, data)
        apply_research_technology(state)
        publish(state, "wall_upgraded")
    end, "wall")
end

local function upgrade_city(state)
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "主城已达最高等级" } end
    local result = spend(state, data.upgrade_cost, "upgrade_city")
    if not result or not result.ok then return result end
    return start_upgrade(state, data, next_level, function()
        state.level = next_level
        state.unit.survival_level = next_level
        state.unit.survival_display_name = state.definition.display_name
        apply_common(state.unit, data)
        building_population.grant_level(
            state,
            next_level,
            "city_level_population"
        )
        publish(state, "city_upgraded")
        refresh_team_farms(state.team)
    end, "city")
end

local function upgrade_farm(state)
    local city_level = team_city_level(state.team)
    if state.level >= city_level then
        return { ok = false, error = "农场等级不能高于主城等级" }
    end
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "农场已达最高等级" } end
    local result = spend(state, data.upgrade_cost, "upgrade_farm")
    if not result or not result.ok then return result end
    return start_upgrade(state, data, next_level, function()
        state.level = next_level
        state.unit.survival_level = next_level
        state.unit.survival_display_name = data.display_name
            or state.definition.display_name
        apply_common(state.unit, data)
        building_population.grant_level(
            state,
            next_level,
            "farm_level_population"
        )
        refresh_farm_upgrade_ability(state)
        publish(state, "farm_upgraded")
    end, "farm")
end

local function route_unit_data(state, row)
    return {
        health = state.unit:GetMaxHealth(),
        armor = state.unit:GetPhysicalArmorBaseValue(),
        damage = row.base_attack_damage,
        attack_range = global_rules.tower_attack_range,
        attack_rate = row.base_attack_speed or 1,
        base_attack_speed = row.base_attack_speed or 1,
        model_asset_id = row.model_asset_id,
        model_name = row.model_name,
        projectile_model = row.projectile_model,
        projectile_speed = tonumber(row.projectile_speed)
            or global_rules.tower_route_default_projectile_speed,
    }
end

sync_tower_abilities = function(state, row)
    tower_ability_sync.sync(state, row)
end

local function apply_model(unit, row)
    if not row then return end
    -- apply_tower/apply_common owns model application. Registered legacy model
    -- paths are resolved to asset IDs there and are committed only after the
    -- asynchronous preload is ready. Never SetModel directly in this path:
    -- network replication of a nonresident model handle asserts the engine.
    asset_preload.queue_particle(row.projectile_model, {
        urgent = true,
        priority = 1900,
    })
end

local function apply_tower_level(state, row, level, change_model)
    apply_tower(state.unit, route_unit_data(state, row), level)
    state.research_base_attack_damage = state.unit:GetBaseDamageMin()
    -- Route rows are authoritative for the model. Reapply on every route-level
    -- update so an engine refresh or entity model reset cannot restore the shell.
    apply_model(state.unit, row)
    state.level = level
    state.tower_class_name = state.tower_class and tower_routes.display_name(row) or row.name
    state.unit.survival_level = level
    state.unit.survival_route_level = tonumber(row.level) or level
    state.unit.survival_tower_class = state.tower_class
    state.unit.survival_display_name = state.tower_class_name
    sync_tower_abilities(state, row)
    tower_skills.apply(state.unit, row.skill_ids)
    for _, skill_id in ipairs(row.skill_ids or {}) do
        if string.match(skill_id, "^laser_") then
            -- Laser routes use instant attack contact; the persistent beam is
            -- rendered and damaged by modifier_tower_attack_effects.
            state.unit:SetAttackCapability(DOTA_UNIT_CAP_MELEE_ATTACK)
            break
        end
    end
    apply_research_technology(state)
    local auto_attack = state.unit:FindModifierByName("modifier_tower_auto_attack")
    if not auto_attack then
        auto_attack = state.unit:AddNewModifier(state.unit, nil, "modifier_tower_auto_attack", {})
    end
    if auto_attack and auto_attack.ResetTarget then
        auto_attack:ResetTarget()
    end
    if state.unit.SetControllableByPlayer
        and tonumber(state.player_id) and tonumber(state.player_id) >= 0 then
        -- Route upgrades keep the original tower entity. Reassert its owner-side
        -- controllability after model and attachment changes so it remains
        -- selectable when the player clicks it again.
        state.unit:SetControllableByPlayer(state.player_id, true)
    end
end

local function upgrade_tower(state, mode)
    if not state.tower_class and state.level >= 5 then
        set_class_buttons(state.unit, true)
        return { ok = false, error = "请先选择防御塔转职" }
    end
    local target = mode == "max" and tower_routes.stage_end_level(state)
        or state.level + 1
    local final_row = tower_routes.row_at_level(state, target)
    local cost = tower_routes.cost_to(state, target)
    if target <= state.level or not final_row or not cost then
        return { ok = false, error = "防御塔已达当前阶段最高等级" }
    end
    local result = spend(state, cost, "upgrade_tower_" .. tostring(mode or "one"))
    if not result or not result.ok then return result end
    local previous_row = tower_routes.current(state)
    local stage_changed = previous_row
        and previous_row.stage_id ~= final_row.stage_id
    return start_upgrade(state, final_row, target, function()
        apply_tower_level(state, final_row, target, stage_changed)
        if cost.population > 0 then
            event_bus.request(events.RESOURCE_ADD_REQUEST, {
                team = state.team, max_population = cost.population,
                reason = "tower_route_population",
            })
        end
        if not state.tower_class and state.level == 5 then
            sync_tower_abilities(state, final_row)
            set_class_buttons(state.unit, true)
        end
        publish(state, "tower_upgraded_" .. tostring(mode or "one"))
    end, "tower_" .. tostring(mode or "one"))
end

local function on_upgrade_request(payload)
    local unit = payload.building
    if not valid_entity(unit) then
        print("[BuildingUpgrade] invalid building entity")
        payload.result = { ok = false, error = "升级建筑不存在" }
        return
    end
    local state = recover_state(unit)
    if not state then
        print("[BuildingUpgrade] missing state entindex="
            .. tostring(unit:entindex()))
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = tonumber(unit.survival_player_id)
                or unit:GetPlayerOwnerID(),
            message = "建筑升级状态尚未初始化",
            level = "error",
        })
        payload.result = { ok = false, error = "建筑升级状态尚未初始化" }
        return
    end

    if upgrade_process.is_active(unit) then
        if payload.source_ability then payload.source_ability:EndCooldown() end
        notify(state, "建筑正在升级中", "error")
        payload.result = { ok = false, error = "建筑正在升级中" }
        return
    end

    local result
    if state.building_id == "wall" then result = upgrade_wall(state)
    elseif state.building_id == "main_city" then result = upgrade_city(state)
    elseif state.building_id == "building_farm"
        or state.building_id == "farm" then result = upgrade_farm(state)
    elseif state.building_id == "arrow_tower" then result = upgrade_tower(state, payload.upgrade_mode or "one")
    else result = { ok = false, error = "该建筑不能升级" } end

    if not result or not result.ok then
        if payload.source_ability then payload.source_ability:EndCooldown() end
    end
    notify(state, result and result.ok and "开始升级" or (result and result.error or "升级失败"),
        result and result.ok and "info" or "error")
    payload.result = result or { ok = false, error = "升级失败" }
end

local function on_class_request(payload)
    local unit = payload.tower
    if not valid_entity(unit) then
        payload.result = { ok = false, error = "防御塔不存在" }
        return
    end
    local state = recover_state(unit)
    local function reject(message)
        if payload.source_ability then payload.source_ability:EndCooldown() end
        if state then notify(state, message, "error") end
        payload.result = { ok = false, error = message }
    end
    if not state or state.building_id ~= "arrow_tower" then
        reject("防御塔升级状态不存在")
        return
    end
    if upgrade_process.is_active(unit) then reject("建筑正在升级中"); return end
    if state.level < 5 then reject("防御塔未达到5级"); return end
    if state.tower_class then reject("防御塔已经完成转职"); return end

    local class_data = state.definition.class_options[payload.class_index]
    if not class_data then reject("无效的转职方向"); return end
    local row = tower_routes.get(class_data.id, 1)
    if not row then reject("路线配置缺失"); return end
    local result = spend(
        state,
        tower_routes.class_change_cost(row),
        "tower_class_change"
    )
    if not result or not result.ok then
        reject(result and result.error or "资源不足")
        return
    end
    local pending = start_upgrade(state, row, 6, function()
        state.tower_class = class_data.id
        apply_tower_level(state, row, 6, true)
        if row.population_delta and row.population_delta > 0 then
            event_bus.request(events.RESOURCE_ADD_REQUEST, {
                team = state.team,
                max_population = row.population_delta,
                reason = "tower_route_population",
            })
        end
        set_class_buttons(state.unit, false)
        publish(state, "tower_class_changed")
    end, "tower_class")
    if not pending or not pending.ok then reject(pending and pending.error or "转职失败")
    else
        payload.result = pending
        notify(state, "开始转职")
    end
end

local function on_created(payload)
    local state = {
        unit = payload.unit,
        definition = payload.definition,
        team = payload.team,
        player_id = payload.player_id,
        building_id = payload.building_id,
        level = tonumber(payload.level) or 1,
        tower_class = nil,
        tower_class_name = nil,
        tower_combat = nil,
        research_base_attack_damage = payload.base_attack_damage,
    }
    buildings[payload.entindex] = state
    if state.building_id == "arrow_tower" and valid_entity(state.unit) then
        local row = arrow_data(state.level)
        if row then
            -- Make creation independent of event subscriber order. The tower's
            -- upgrade abilities must be active before ability runtime metadata
            -- is published, otherwise Panorama keeps the initial grey state.
            sync_tower_abilities(state, row)
            set_tower_projectile_speed(state.unit, row.projectile_speed)
        end
    end
    apply_research_technology(state)
    if payload.building_id == "arrow_tower"
        and valid_entity(payload.unit)
        and not payload.unit:HasModifier("modifier_tower_attack_effects") then
        payload.unit:AddNewModifier(
            payload.unit, nil, "modifier_tower_attack_effects", {}
        )
    end
    refresh_farm_upgrade_ability(state)
end

local function on_destroyed(payload)
    upgrade_process.cancel_by_entindex(payload.entindex, "building_destroyed")
    buildings[payload.entindex] = nil
    if payload.building_id == "main_city" then refresh_team_farms(payload.team) end
end

local function on_building_changed(payload)
    local state = buildings[payload.entindex]
    if state then
        state.level = tonumber(payload.level) or state.level
        refresh_farm_upgrade_ability(state)
    end
    if payload.building_id == "main_city" then refresh_team_farms(payload.team) end
end

function M.init()
    upgrade_process.reset()
    buildings = {}
    event_bus.subscribe(events.BUILDING_CREATED, on_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_destroyed)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_UPGRADE_REQUEST, on_upgrade_request)
    event_bus.subscribe(events.TOWER_CLASS_REQUEST, on_class_request)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, on_technology_stats_changed)
end

M._base_health_for_test = base_health

return M
