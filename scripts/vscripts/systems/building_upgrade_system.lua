local event_bus = require("core/event_bus")
local events = require("core/events")
local arrow_tower_base = require("config/generated/arrow_tower_base")
local tower_routes = require("config/tower_route_config")
local tower_skills = require("systems/tower_skill_runtime")
local tower_ability_sync = require("systems/tower_ability_sync")
local global_rules = require("config/global_rules")
local tower_combat_rules = require("config/tower_combat_rules")
local technology_stat_manager = require("systems/technology_stat_manager")
local player_profile_service = require("systems/player_profile_service")
local building_population = require("systems/building_population_service")
local building_visual = require("systems/building_visual_service")
local asset_preload = require("systems/asset_preload_service")
local upgrade_process = require("systems/building_upgrade_process")
local building_sound = require("systems/building_sound_service")
local building_health_projection = require("systems/building_health_projection")
local tower_utility_abilities = require("systems/tower_utility_ability_sync")
local dev_wall_stats = require("debug/dev_wall_stats")
local war3_armor_target = require("systems/war3_armor_target")
local rogue_effect_state = require("systems/rogue_effect_state_service")

local M = {}
print("[SURVIVAL_FINGERPRINT] building_upgrade_system=20260818_csv_attack_time_no_native_getter")
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

local function configured_base_attack_time(state)
    local row = tower_routes.current(state)
    local attacks_per_second = tonumber(row and row.base_attack_speed)
    if attacks_per_second and attacks_per_second > 0 then
        return 1 / attacks_per_second
    end
    return nil
end

local function apply_tower_attack_time(unit, base_attack_time, attack_speed_bonus)
    local final_attack_time = math.max(0.0001,
        tonumber(base_attack_time) or 1)
        / math.max(0.01, 1 + (tonumber(attack_speed_bonus) or 0) / 100)
    local attacks_per_second = 1 / final_attack_time
    unit:SetBaseAttackTime(final_attack_time)
    -- BUILDING_CHANGED publishes this project-owned value to the custom
    -- ScanPanel. Keep it synchronized with the BAT applied to the engine.
    unit.survival_attack_speed = attacks_per_second
    unit.survival_attack_interval = final_attack_time
    return final_attack_time, attacks_per_second
end

local function apply_research_technology(state)
    local unit = state.unit
    if not valid_entity(unit) then return end
    local player_id = state.player_id
    local technology = technology_stat_manager.get(player_id).final
    local profile = player_profile_service.get_profile(player_id)
    local profile_stats = profile and profile.save
        and profile.save.gameplay_stats or {}
    if state.building_id == "arrow_tower" then
        local base_damage = tonumber(state.research_base_attack_damage)
            or unit:GetBaseDamageMin()
        local tower = technology.tower or {}
        local permanent_result = event_bus.request(
            events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
            { player_id = player_id }
        )
        local permanent = permanent_result and permanent_result.totals or {}
        local bonus = (tonumber(tower.attack_flat) or 0)
            + (tonumber(permanent.tower_attack_flat) or 0)
        local bonus_pct = (tonumber(tower.attack_bonus_pct) or 0)
            + (tonumber(permanent.tower_attack_bonus_pct) or 0)
        local damage = (base_damage + bonus) * (1 + bonus_pct / 100)
        unit:SetBaseDamageMin(damage)
        unit:SetBaseDamageMax(damage)
        unit.survival_attack_min = damage
        unit.survival_attack_max = damage
        unit.survival_super_tower_crit_chance =
            tonumber(tower.critical_chance_pct) or 0
        local attack_speed_bonus = tonumber(tower.attack_speed_bonus_pct) or 0
        attack_speed_bonus = attack_speed_bonus
            + (tonumber(permanent.tower_attack_speed_bonus_pct) or 0)
        -- GetBaseAttackTime has different native signatures between the Dev
        -- harness and the live engine. The CSV route data is authoritative for
        -- tower attack speed, so do not call the engine getter here.
        local base_attack_time = tonumber(unit.survival_research_base_attack_time)
            or configured_base_attack_time(state) or 1
        unit.survival_research_base_attack_time = base_attack_time
        -- Both interval fields are additive reductions. They intentionally
        -- stack instead of one replacing the other; the gameplay-stats field
        -- is no longer interpreted as an absolute BAT.
        local profile_interval_reduction = tonumber(permanent.tower_attack_interval)
            or tonumber(profile_stats.tower_attack_interval) or 0
        base_attack_time = math.max(0.05, base_attack_time
            - profile_interval_reduction
            - (tonumber(permanent.tower_attack_interval_reduction)
                or tonumber(profile_stats.tower_attack_interval_reduction) or 0))
        apply_tower_attack_time(unit, base_attack_time, attack_speed_bonus)
        local attack_range = tower_combat_rules.attack_range(
            tower.attack_range_bonus
        ) + (tonumber(permanent.tower_attack_range) or 0)
        set_attack_range(unit, attack_range)
        unit.survival_super_tower_crit_chance =
            (tonumber(unit.survival_super_tower_crit_chance) or 0)
            + (tonumber(permanent.tower_critical_chance_pct) or 0)
        unit.survival_inherited_critical_damage_pct = 200
            + (tonumber(permanent.tower_critical_damage_bonus_pct) or 0)
        unit.survival_gameplay_critical_damage_pct = 200
            + (tonumber(permanent.tower_critical_damage_bonus_pct) or 0)
        unit.survival_gameplay_final_damage_pct =
            (tonumber(permanent.tower_final_damage_bonus_pct) or 0)
            + (tonumber(permanent.global_final_damage_bonus_pct) or 0)
    elseif state.building_id == "wall" then
        local data = state.definition.levels[state.level or 1] or {}
        local base_health = tonumber(data.health) or unit:GetMaxHealth()
        local wall = technology.wall or {}
        local permanent_result = event_bus.request(
            events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,
            { player_id = player_id }
        )
        local permanent = permanent_result and permanent_result.totals or {}
        local bonus_pct = (tonumber(wall.health_bonus_pct) or 0)
            + (tonumber(wall.technology_health_bonus_pct) or 0)
            + (tonumber(permanent.wall_health_bonus_pct) or 0)
        -- Technology/challenge aggregation retains the legacy Dota-armor unit.
        -- Convert it back to the CSV-authored War3 value for custom mitigation.
        local base_war3_armor = tonumber(data.war3_armor or data.armor) or 0
        local armor_bonus = (tonumber(wall.technology_armor_bonus) or 0) * 3
            + (tonumber(permanent.wall_armor) or 0)
            + (tonumber(permanent.wall_armor_growth_flat) or 0)
            + (tonumber(permanent.team_hero_wall_armor_bonus) or 0)
            + base_war3_armor
                * (tonumber(permanent.wall_armor_bonus_pct) or 0) / 100
        local old_max = math.max(1, unit:GetMaxHealth())
        local old_health = math.max(0, unit:GetHealth())
        local health_ratio = old_health / old_max
        local max_health = building_health_projection.maximum_with_flat_bonus(
            base_health,
            bonus_pct,
            rogue_effect_state.wall_health_flat(player_id)
                + (tonumber(permanent.wall_initial_health) or 0)
                + (tonumber(permanent.wall_health_growth_flat) or 0)
        )
        unit:SetBaseMaxHealth(max_health)
        unit:SetMaxHealth(max_health)
        unit:SetHealth(old_health > 0
            and math.max(1, math.floor(max_health * health_ratio)) or 0)
        war3_armor_target.apply(
            unit,
            data.war3_armor or data.armor,
            armor_bonus
        )
        unit.survival_gameplay_damage_reduction_pct =
            tonumber(permanent.wall_damage_reduction_pct) or 0
        unit.survival_gameplay_damage_block =
            tonumber(permanent.wall_damage_block) or 0
        unit.survival_gameplay_health_growth_per_second =
            tonumber(permanent.wall_health_per_second) or 0
        unit.survival_gameplay_armor_growth_per_second =
            tonumber(permanent.wall_armor_per_second) or 0
        if unit.SetBaseHealthRegen then
            unit:SetBaseHealthRegen(
                tonumber(permanent.wall_health_regen_per_second) or 0
            )
        end
        dev_wall_stats.apply(state)
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
    unit.survival_research_base_attack_time = 1 / attacks_per_second
    unit.survival_attack_interval = unit.survival_research_base_attack_time
    unit:SetBaseAttackTime(unit.survival_research_base_attack_time)
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
    for _, skill_id in ipairs(data.skill_ids or {}) do
        if string.match(skill_id, "^machine_gun_")
            and unit.SetRangedProjectileName then
            unit:SetRangedProjectileName("")
            unit.survival_projectile_model = ""
            break
        end
    end
    set_tower_projectile_speed(unit, data.projectile_speed)
    set_attack_range(unit, global_rules.tower_attack_range)
end

local function set_class_buttons(unit, active)
    local state = buildings[unit:entindex()]
    if not state then return end
    tower_ability_sync.sync(state, tower_routes.current(state), true)
end

local function refresh_class_buttons(state, tower_class_counts)
    if not state or state.tower_class or state.level < 5
        or not valid_entity(state.unit) then
        return
    end
    tower_ability_sync.sync(state, tower_routes.current(state), true)
end

local function base_health(state)
    local definition = state.definition or {}
    local levels = definition.levels or definition.pre_class_levels or {}
    local data = levels[state.level] or {}
    return tonumber(data.health) or state.unit:GetMaxHealth()
end

local function configured_display_name(state, route_row)
    if state.building_id == "arrow_tower" then
        return state.unit.survival_display_name
            or state.tower_class_name
            or (route_row and route_row.name)
            or state.definition.display_name
    end
    if state.building_id == "wall" or state.building_id == "main_city" then
        local level_data = (state.definition.levels or {})[state.level] or {}
        return level_data.display_name or state.definition.display_name
    end
    return state.unit.survival_display_name or state.definition.display_name
end

publish = function(state, reason)
    local route_row = state.building_id == "arrow_tower"
        and tower_routes.current(state) or nil
    local display_name = configured_display_name(state, route_row)
    state.unit.survival_display_name = display_name
    event_bus.emit(events.BUILDING_CHANGED, {
        entindex = state.unit:entindex(),
        team = state.team,
        player_id = state.player_id,
        building_id = state.building_id,
        level = state.level,
        absolute_level = state.level,
        route_level = route_row and route_row.level or state.level,
        record_id = route_row and route_row.record_id or nil,
        tower_class = state.tower_class,
        tower_class_name = state.tower_class_name,
        fusion_participated = state.fusion_participated == true and 1 or 0,
        display_name = display_name,
        attack_min = state.unit.survival_attack_min,
        attack_max = state.unit.survival_attack_max,
        runtime_armor = state.unit.survival_armor,
        attack_speed = state.unit.survival_attack_speed,
        attack_interval = state.unit.survival_attack_interval
            or (tonumber(state.unit.survival_attack_speed) or 0) > 0
                and 1 / tonumber(state.unit.survival_attack_speed)
            or 0,
        base_health = base_health(state),
        base_attack_damage = state.building_id == "arrow_tower"
            and tonumber((arrow_data(state.level) or {}).base_attack_damage)
            or nil,
        upgrade_in_progress = state.unit.survival_upgrade_in_progress and 1 or 0,
        upgrade_target_level = state.unit.survival_upgrade_target_level,
        population_occupied = tonumber(state.population_occupied) or 0,
        reason = reason,
    })
end

local function spend(state, cost, reason)
    if not cost then return { ok = false, error = "升级费用未配置" } end
    if state.free_upgrade_request == true then
        return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
            player_id = state.player_id,
            team = state.team,
            wood = 0,
            gold = 0,
            population = cost.population or 0,
            reason = reason,
        })
    end
    return event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        player_id = state.player_id,
        team = state.team,
        wood = cost.wood or 0,
        gold = cost.gold or 0,
        population = cost.population or 0,
        reason = reason,
    })
end

local function charged_cost(state, cost)
    if state.free_upgrade_request ~= true then return cost end
    return {
        wood = 0,
        gold = 0,
        population = cost and cost.population or 0,
    }
end

local function refund_spend(state, cost, reason)
    if not cost then return end
    local wood = math.max(0, tonumber(cost.wood) or 0)
    local gold = math.max(0, tonumber(cost.gold) or 0)
    local population = math.max(0, tonumber(cost.population) or 0)
    if wood > 0 or gold > 0 then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            player_id = state.player_id,
            team = state.team,
            wood = wood,
            gold = gold,
            reason = reason or "tower_upgrade_refund",
        })
    end
    if population > 0 then
        event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
            player_id = state.player_id,
            team = state.team,
            population = population,
            reason = (reason or "tower_upgrade_refund") .. "_population",
        })
    end
end

local function reserve_tower_class_slot(state, class_id)
    return event_bus.request(events.TOWER_CLASS_SLOT_REQUEST, {
        operation = "reserve",
        player_id = state.player_id,
        class_id = class_id,
        entindex = state.unit:entindex(),
    })
end

local function release_tower_class_slot(state, class_id)
    if not state or not class_id then return end
    event_bus.request(events.TOWER_CLASS_SLOT_REQUEST, {
        operation = "release",
        player_id = state.player_id,
        class_id = class_id,
        entindex = state.unit:entindex(),
    })
end

local function start_upgrade(
    state,
    target_data,
    target_level,
    on_complete,
    reason,
    on_cancel
)
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
            local ok, error_message = pcall(on_complete)
            if ok then
                notify(state, "升级完成")
            else
                print("[BuildingUpgrade] completion failed: "
                    .. tostring(error_message))
                if on_cancel then on_cancel("completion_failed") end
                publish(state, "upgrade_cancelled_completion_failed")
                notify(
                    state,
                    on_cancel and "升级失败，资源已返还" or "升级失败",
                    "error"
                )
            end
        end,
        on_cancel = function(cancel_reason)
            if on_cancel then on_cancel(cancel_reason) end
            publish(state, "upgrade_cancelled_" .. tostring(cancel_reason))
        end,
    })
end

local function play_upgrade_sound(state, options)
    options = options or {}
    options.unit = state.unit
    options.team = state.team
    options.building_id = state.building_id
    options.tower_class = state.tower_class
    building_sound.upgrade_completed(options)
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
        player_id = tonumber(snapshot.player_id),
        building_id = snapshot.building_id,
        level = tonumber(snapshot.level) or tonumber(unit.survival_level) or 1,
        tower_class = snapshot.tower_class,
        tower_class_name = snapshot.tower_class_name,
        fusion_participated = snapshot.fusion_participated == 1
            or unit.survival_fusion_participated == true,
        population_occupied = tonumber(snapshot.population_occupied)
            or tonumber(unit.survival_population_occupied),
        tower_combat = nil,
        research_base_attack_damage = snapshot.base_attack_damage,
    }
    buildings[entindex] = state
    if state.population_occupied == nil and state.building_id == "arrow_tower" then
        state.population_occupied = tower_routes.population_occupied(
            tower_routes.current(state)
        )
    end
    if state.population_occupied ~= nil then
        unit.survival_population_occupied = state.population_occupied
    end

    if state.building_id == "arrow_tower" then
        local row = tower_routes.current(state) or arrow_data(state.level)
        if row then
            unit.survival_route_level = tonumber(row.level) or state.level
            unit.survival_tower_record_id = row.record_id
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
        if tonumber(state.player_id) == player_id then
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
    local cost = charged_cost(state, data.upgrade_cost)
    local result = spend(state, cost, "upgrade_wall")
    if not result or not result.ok then return result end
    local pending = start_upgrade(state, data, next_level, function()
        state.level = next_level
        state.unit.survival_level = next_level
        state.unit.survival_display_name = data.display_name
            or state.definition.display_name
        building_health_projection.apply_maximum_health_increase(state.unit, function()
            apply_common(state.unit, data)
            apply_research_technology(state)
        end)
        publish(state, "wall_upgraded")
        play_upgrade_sound(state)
    end, "wall", function(cancel_reason)
        refund_spend(state, cost, "wall_upgrade_cancelled:" .. tostring(cancel_reason))
    end)
    if not pending or not pending.ok then
        refund_spend(state, cost, "wall_upgrade_start_failed")
    end
    return pending
end

local function upgrade_city(state)
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "主城已达最高等级" } end
    local cost = charged_cost(state, data.upgrade_cost)
    local result = spend(state, cost, "upgrade_city")
    if not result or not result.ok then return result end
    local pending = start_upgrade(state, data, next_level, function()
        state.level = next_level
        state.unit.survival_level = next_level
        state.unit.survival_display_name = data.display_name
            or state.definition.display_name
        apply_common(state.unit, data)
        building_population.grant_level(
            state,
            next_level,
            "city_level_population"
        )
        if rogue_effect_state.has_effect(state.player_id,
            "builder_main_city_wood_refund") then
            event_bus.request(events.RESOURCE_ADD_REQUEST, {
                player_id = state.player_id,
                team = state.team,
                wood = tonumber(cost and cost.wood) or 0,
                gold = 0,
                reason = "rogue_reward:infrastructure_maniac_start",
            })
        end
        publish(state, "city_upgraded")
        refresh_team_farms(state.team)
        play_upgrade_sound(state)
    end, "city", function(cancel_reason)
        refund_spend(state, cost, "city_upgrade_cancelled:" .. tostring(cancel_reason))
    end)
    if not pending or not pending.ok then
        refund_spend(state, cost, "city_upgrade_start_failed")
    end
    return pending
end

local function upgrade_farm(state)
    local city_level = team_city_level(state.team)
    if state.level >= city_level then
        return { ok = false, error = "农场等级不能高于主城等级" }
    end
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "农场已达最高等级" } end
    local cost = charged_cost(state, data.upgrade_cost)
    local result = spend(state, cost, "upgrade_farm")
    if not result or not result.ok then return result end
    local pending = start_upgrade(state, data, next_level, function()
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
        play_upgrade_sound(state)
    end, "farm", function(cancel_reason)
        refund_spend(state, cost, "farm_upgrade_cancelled:" .. tostring(cancel_reason))
    end)
    if not pending or not pending.ok then
        refund_spend(state, cost, "farm_upgrade_start_failed")
    end
    return pending
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
    state.unit.survival_tower_stage_id = row.stage_id
    state.unit.survival_tower_class = state.tower_class
    state.unit.survival_display_name = state.tower_class_name
    sync_tower_abilities(state, row)
    tower_skills.apply(state.unit, row.skill_ids)
    local attack_effects = state.unit:FindModifierByName(
        "modifier_tower_attack_effects"
    )
    if attack_effects and attack_effects.ResetAntiAirSequence then
        attack_effects:ResetAntiAirSequence()
    end
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
    state.population_occupied = tower_routes.population_occupied(row)
    state.unit.survival_population_occupied = state.population_occupied
end

local function restore_tower_level(state, row, level, tower_class, population)
    state.tower_class = tower_class
    state.level = level
    state.population_occupied = population
    if not valid_entity(state.unit) or not row then return false end
    local ok, error_message = pcall(
        apply_tower_level,
        state,
        row,
        level,
        true
    )
    if not ok then
        state.level = level
        state.tower_class = tower_class
        state.population_occupied = population
        state.unit.survival_level = level
        state.unit.survival_tower_class = tower_class
        state.unit.survival_population_occupied = population
        print("[BuildingUpgrade] tower rollback failed: "
            .. tostring(error_message))
        return false
    end
    state.population_occupied = population
    state.unit.survival_population_occupied = population
    return true
end

local function upgrade_tower(state, mode)
    if not state.tower_class and state.level >= 5 then
        set_class_buttons(state.unit, true)
        return { ok = false, error = "请先选择防御塔转职" }
    end
    local target = mode == "max" and tower_routes.stage_end_level(state)
        or state.level + 1
    local final_row = tower_routes.row_at_level(state, target)
    local cost = charged_cost(state, tower_routes.cost_to(state, target))
    if target <= state.level or not final_row or not cost then
        return { ok = false, error = "防御塔已达当前阶段最高等级" }
    end
    local result = spend(state, cost, "upgrade_tower_" .. tostring(mode or "one"))
    if not result or not result.ok then return result end
    local previous_row = tower_routes.current(state)
    local previous_level = state.level
    local previous_class = state.tower_class
    local previous_population = tonumber(state.population_occupied)
        or tower_routes.population_occupied(previous_row)
    local stage_changed = previous_row
        and previous_row.stage_id ~= final_row.stage_id
    local pending = start_upgrade(state, final_row, target, function()
        apply_tower_level(state, final_row, target, stage_changed)
        if not state.tower_class and state.level == 5 then
            sync_tower_abilities(state, final_row)
            set_class_buttons(state.unit, true)
        end
        publish(state, "tower_upgraded_" .. tostring(mode or "one"))
        play_upgrade_sound(state, { stage_changed = stage_changed })
    end, "tower_" .. tostring(mode or "one"), function(cancel_reason)
        if cancel_reason == "completion_failed" then
            restore_tower_level(
                state,
                previous_row,
                previous_level,
                previous_class,
                previous_population
            )
        else
            state.population_occupied = previous_population
            if valid_entity(state.unit) then
                state.unit.survival_population_occupied = previous_population
            end
        end
        refund_spend(
            state,
            cost,
            "tower_upgrade_cancelled:" .. tostring(cancel_reason)
        )
    end)
    if not pending or not pending.ok then
        refund_spend(state, cost, "tower_upgrade_start_failed")
    end
    return pending
end

local function upgrade_quote(payload)
    payload = payload or {}
    local unit = payload.building
    if not valid_entity(unit) or not unit:IsAlive() then
        return { ok = false, error = "升级建筑不存在" }
    end
    local state = recover_state(unit)
    if not state then
        return { ok = false, error = "建筑升级状态尚未初始化" }
    end
    local player_id = tonumber(payload.player_id)
    if player_id ~= nil and player_id ~= tonumber(state.player_id) then
        return { ok = false, error = "只能升级自己的建筑" }
    end
    if upgrade_process.is_active(unit) then
        return { ok = false, error = "建筑正在升级中" }
    end

    local mode = payload.upgrade_mode == "max" and "max" or "one"
    local target_level = state.level + 1
    local cost = nil
    if state.building_id == "arrow_tower" then
        if not state.tower_class and state.level >= 5 then
            return { ok = false, error = "请先选择防御塔转职" }
        end
        if mode == "max" then
            target_level = tower_routes.stage_end_level(state)
        end
        local target_row = tower_routes.row_at_level(state, target_level)
        cost = tower_routes.cost_to(state, target_level)
        if target_level <= state.level or not target_row or not cost then
            return { ok = false, error = "防御塔已达当前阶段最高等级" }
        end
    else
        if mode ~= "one" then
            return { ok = false, error = "该建筑不支持直升最高级" }
        end
        if state.building_id ~= "wall" and state.building_id ~= "main_city"
            and state.building_id ~= "building_farm"
            and state.building_id ~= "farm" then
            return { ok = false, error = "该建筑不能升级" }
        end
        local data = state.definition.levels
            and state.definition.levels[target_level] or nil
        if not data then
            return { ok = false, error = "该建筑已达最高等级" }
        end
        if state.building_id == "wall" and data.requires_city_level
            and data.requires_city_level > team_city_level(state.team) then
            return {
                ok = false,
                error = "基地达到Lv." .. tostring(data.requires_city_level)
                    .. "后才能升级城墙",
            }
        end
        if (state.building_id == "building_farm" or state.building_id == "farm")
            and state.level >= team_city_level(state.team) then
            return { ok = false, error = "农场等级不能高于主城等级" }
        end
        cost = data.upgrade_cost
        if not cost then
            return { ok = false, error = "升级费用未配置" }
        end
    end

    return {
        ok = true,
        building_id = state.building_id,
        current_level = state.level,
        target_level = target_level,
        upgrade_mode = mode,
        wood = math.max(0, tonumber(cost.wood) or 0),
        gold = math.max(0, tonumber(cost.gold) or 0),
        population = math.max(0, tonumber(cost.population) or 0),
    }
end

local function on_upgrade_request(payload)
    payload = payload or {}
    local unit = payload.building
    if not valid_entity(unit) then
        print("[BuildingUpgrade] invalid building entity")
        payload.result = { ok = false, error = "升级建筑不存在" }
        return payload.result
    end
    local state = recover_state(unit)
    if not state then
        print("[BuildingUpgrade] missing state entindex="
            .. tostring(unit:entindex()))
        if not payload.silent_notification then
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = tonumber(unit.survival_player_id)
                    or unit:GetPlayerOwnerID(),
                message = "建筑升级状态尚未初始化",
                level = "error",
            })
        end
        payload.result = { ok = false, error = "建筑升级状态尚未初始化" }
        return payload.result
    end

    if upgrade_process.is_active(unit) then
        if not payload.silent_notification then
            notify(state, "建筑正在升级中", "error")
        end
        payload.result = { ok = false, error = "建筑正在升级中" }
        return payload.result
    end

    local free_effect_type = "grant_building_upgrade_action"
    local has_free_upgrade = payload.system_free_upgrade ~= true
        and rogue_effect_state.numeric(state.player_id, free_effect_type) > 0
    local requested_mode = payload.upgrade_mode or "one"
    if has_free_upgrade then
        state.free_upgrade_request = true
        requested_mode = "one"
    end

    local ok, result = pcall(function()
        if state.building_id == "wall" then return upgrade_wall(state) end
        if state.building_id == "main_city" then return upgrade_city(state) end
        if state.building_id == "building_farm" or state.building_id == "farm" then
            return upgrade_farm(state)
        end
        if state.building_id == "arrow_tower" then
            return upgrade_tower(state, requested_mode)
        end
        return { ok = false, error = "该建筑不能升级" }
    end)
    state.free_upgrade_request = nil
    if not ok then
        print("[BuildingUpgrade] upgrade failed: " .. tostring(result))
        result = { ok = false, error = "升级失败" }
    end
    if has_free_upgrade and result.ok == true then
        rogue_effect_state.consume_numeric(state.player_id, free_effect_type, 1)
    end

    if not payload.silent_notification then
        notify(state, result and result.ok and "开始升级" or (result and result.error or "升级失败"),
            result and result.ok and "info" or "error")
    end
    payload.result = result or { ok = false, error = "升级失败" }
    return payload.result
end

local function on_free_upgrade_request(payload)
    payload = payload or {}
    payload.silent_notification = true
    payload.system_free_upgrade = true
    local quote = upgrade_quote(payload)
    if not quote.ok then return quote end
    local state = recover_state(payload.building)
    state.free_upgrade_request = true
    local ok, result = pcall(on_upgrade_request, payload)
    state.free_upgrade_request = nil
    if not ok then
        print("[BuildingUpgrade] free upgrade failed: " .. tostring(result))
        return { ok = false, error = "升级失败" }
    end
    return result
end

local function on_class_request(payload)
    local unit = payload.tower
    if not valid_entity(unit) then
        payload.result = { ok = false, error = "防御塔不存在" }
        return payload.result
    end
    local state = recover_state(unit)
    local function reject(message)
        if state then notify(state, message, "error") end
        payload.result = { ok = false, error = message }
        return payload.result
    end
    if not state or state.building_id ~= "arrow_tower" then
        return reject("防御塔升级状态不存在")
    end
    if upgrade_process.is_active(unit) then return reject("建筑正在升级中") end
    if state.level < 5 then return reject("防御塔未达到5级") end
    if state.tower_class then return reject("防御塔已经完成转职") end

    local class_data = state.definition.class_options[payload.class_index]
    if not class_data then return reject("无效的转职方向") end
    local row = tower_routes.get(class_data.id, 1)
    if not row then return reject("路线配置缺失") end
    local slot = reserve_tower_class_slot(state, class_data.id)
    if not slot or not slot.ok then
        return reject("该转职路线数量已达上限（"
            .. tostring(slot and slot.maximum or global_rules.tower_class_max_count)
            .. "）")
    end
    local cost = tower_routes.class_change_cost(row, state)
    local result = spend(
        state,
        cost,
        "tower_class_change"
    )
    if not result or not result.ok then
        release_tower_class_slot(state, class_data.id)
        return reject(result and result.error or "资源不足")
    end
    local previous_population = tonumber(state.population_occupied)
        or tower_routes.population_occupied(tower_routes.current(state))
    local previous_row = tower_routes.current(state)
    local previous_level = state.level
    local previous_class = state.tower_class
    local pending = start_upgrade(state, row, 6, function()
        state.tower_class = class_data.id
        apply_tower_level(state, row, 6, true)
        set_class_buttons(state.unit, false)
        publish(state, "tower_class_changed")
        release_tower_class_slot(state, class_data.id)
        play_upgrade_sound(state, { class_changed = true })
    end, "tower_class", function(cancel_reason)
        release_tower_class_slot(state, class_data.id)
        if cancel_reason == "completion_failed" then
            restore_tower_level(
                state,
                previous_row,
                previous_level,
                previous_class,
                previous_population
            )
        else
            state.population_occupied = previous_population
            if valid_entity(state.unit) then
                state.unit.survival_population_occupied = previous_population
            end
        end
        refund_spend(
            state,
            cost,
            "tower_class_cancelled:" .. tostring(cancel_reason)
        )
    end)
    if not pending or not pending.ok then
        release_tower_class_slot(state, class_data.id)
        refund_spend(state, cost, "tower_class_start_failed")
        reject(pending and pending.error or "转职失败")
    else
        payload.result = pending
        notify(state, "开始转职")
    end
    return payload.result
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
        fusion_participated = payload.fusion_participated == 1
            or payload.unit.survival_fusion_participated == true,
        population_occupied = 0,
        tower_combat = nil,
        research_base_attack_damage = payload.base_attack_damage,
    }
    buildings[payload.entindex] = state
    if valid_entity(state.unit) then
        state.unit.survival_population_occupied = state.population_occupied
    end
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
        state.fusion_participated = payload.fusion_participated == 1
            or state.fusion_participated == true
        state.population_occupied = tonumber(payload.population_occupied)
            or state.population_occupied
        refresh_farm_upgrade_ability(state)
    end
    if payload.building_id == "main_city" then refresh_team_farms(payload.team) end
end

local function on_tower_class_counts_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    for _, state in pairs(buildings) do
        if tonumber(state.player_id) == player_id then
            refresh_class_buttons(state, payload.tower_class_counts or {})
            publish(state, "tower_class_availability_changed")
        end
    end
end

local function on_tower_fusion_state_changed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    for _, state in pairs(buildings) do
        if tonumber(state.player_id) == player_id
            and state.building_id == "arrow_tower" then
            local row = tower_routes.current(state) or arrow_data(state.level)
            if row then sync_tower_abilities(state, row) end
            publish(state, "tower_fusion_eligibility_changed")
        end
    end
end

function M.init()
    upgrade_process.reset()
    tower_ability_sync.reset()
    buildings = {}
    event_bus.handle_request(events.BUILDING_UPGRADE_QUOTE_REQUEST, upgrade_quote)
    event_bus.subscribe(events.BUILDING_CREATED, on_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_destroyed)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.TOWER_CLASS_COUNTS_CHANGED,
        on_tower_class_counts_changed)
    event_bus.subscribe(events.TOWER_FUSION_STATE_CHANGED,
        on_tower_fusion_state_changed)
    event_bus.handle_request(events.BUILDING_UPGRADE_REQUEST, on_upgrade_request)
    event_bus.handle_request(events.BUILDING_UPGRADE_FREE_REQUEST, on_free_upgrade_request)
    event_bus.handle_request(events.TOWER_CLASS_REQUEST, on_class_request)
    event_bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, on_technology_stats_changed)
    event_bus.subscribe(events.PERMANENT_REWARD_EFFECTS_CHANGED,
        on_technology_stats_changed)
end

M._base_health_for_test = base_health
M._apply_tower_attack_time_for_test = apply_tower_attack_time

return M
