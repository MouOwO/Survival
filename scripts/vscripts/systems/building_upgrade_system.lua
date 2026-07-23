local event_bus = require("core/event_bus")
local events = require("core/events")
local arrow_tower_base = require("config/generated/arrow_tower_base")
local tower_routes = require("config/tower_route_config")
local tower_skills = require("systems/tower_skill_runtime")
local tower_ability_sync = require("systems/tower_ability_sync")
local global_rules = require("config/global_rules")

local M = {}
local buildings = {}
local technology_levels = {}
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
    attack_range = global_rules.tower_attack_range
    if unit.Script_SetAttackRange then
        unit:Script_SetAttackRange(attack_range)
    elseif unit.SetAttackRange then
        unit:SetAttackRange(attack_range)
    end
    if unit.SetAcquisitionRange then
        -- Keep autonomous tower aggro after route upgrades. The old value 10
        -- effectively disabled automatic target acquisition.
        unit:SetAcquisitionRange(global_rules.tower_acquisition_range)
    end
end

local function apply_common(unit, data)
    unit:SetBaseMaxHealth(data.health)
    unit:SetMaxHealth(data.health)
    unit:SetHealth(data.health)
    unit:SetPhysicalArmorBaseValue(data.armor)
    unit.survival_armor = tonumber(data.armor) or 0
    if data.model_name and data.model_name ~= "" then
        unit:SetModel(data.model_name)
        unit:SetOriginalModel(data.model_name)
    end
end

local function arrow_data(level)
    for _, row in ipairs(arrow_tower_base.rows) do
        if row.level == level then return row end
    end
    return nil
end

local function technology_level(player_id, group)
    local levels = technology_levels[player_id] or {}
    return tonumber(levels[group]) or 0
end

local function sync_technology_levels(player_id)
    local result = event_bus.request(
        events.TECHNOLOGY_STATE_GET_REQUEST,
        { player_id = player_id }
    )
    if result and result.levels then
        technology_levels[player_id] = result.levels
    end
end

local function apply_research_technology(state)
    local unit = state.unit
    if not valid_entity(unit) then return end
    local player_id = state.player_id
    if state.building_id == "arrow_tower" then
        local base_damage = tonumber(state.research_base_attack_damage)
            or unit:GetBaseDamageMin()
        local bonus = technology_level(player_id, "tower_attack") * 200
            + technology_level(player_id, "advanced_tower_attack") * 1000
            + technology_level(player_id, "researcher_super_tower_attack") * 30000
        local damage = base_damage + bonus
        unit:SetBaseDamageMin(damage)
        unit:SetBaseDamageMax(damage)
        unit.survival_attack_min = damage
        unit.survival_attack_max = damage
        unit.survival_super_tower_crit_chance = technology_level(
            player_id, "researcher_super_tower_crit"
        )
        set_attack_range(unit, global_rules.tower_attack_range)
    elseif state.building_id == "wall" then
        local data = state.definition.levels[state.level or 1] or {}
        local base_health = tonumber(data.health) or unit:GetMaxHealth()
        local bonus_pct = technology_level(player_id, "wall_health") * 15
            + technology_level(player_id, "advanced_wall_health") * 30
            + technology_level(player_id, "researcher_super_wall_health") * 3
        local armor_bonus = technology_level(player_id, "researcher_super_wall_armor") * 3
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
    if not state or state.building_id ~= "farm"
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
    if tonumber(data.projectile_speed) and unit.SetProjectileSpeed then
        unit:SetProjectileSpeed(tonumber(data.projectile_speed))
    end
    set_attack_range(unit, data.attack_range)
end

local function set_class_buttons(unit, active)
    local state = buildings[unit:entindex()]
    if not state then return end
    for _, class_data in pairs(state.definition.class_options) do
        local ability = unit:FindAbilityByName(class_data.ability)
        if active and not ability then
            ability = unit:AddAbility(class_data.ability)
            if ability then ability:SetLevel(1) end
        end
        if ability then ability:SetActivated(active) end
    end
end

publish = function(state, reason)
    local display_name = state.unit.survival_display_name
        or state.tower_class_name
        or ((tower_routes.current(state) or {}).name)
        or state.definition.display_name
    event_bus.emit(events.BUILDING_CHANGED, {
        entindex = state.unit:entindex(),
        team = state.team,
        player_id = state.player_id,
        building_id = state.building_id,
        level = state.level,
        tower_class = state.tower_class,
        tower_class_name = state.tower_class_name,
        display_name = display_name,
        attack_min = state.unit.survival_attack_min,
        attack_max = state.unit.survival_attack_max,
        armor = state.unit.survival_armor,
        attack_speed = state.unit.survival_attack_speed,
        base_health = tonumber(state.definition.levels[state.level]
            and state.definition.levels[state.level].health)
            or state.unit:GetMaxHealth(),
        base_attack_damage = state.building_id == "arrow_tower"
            and tonumber((arrow_data(state.level) or {}).base_attack_damage)
            or nil,
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
            player_id = unit:GetPlayerOwnerID(),
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
        if row then sync_tower_abilities(state, row) end
        sync_technology_levels(state.player_id)
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
        local owned = unit:GetPlayerOwnerID() == player_id
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

local function on_technology_changed(payload)
    technology_levels[payload.player_id] = payload.levels or {}
    recover_player_towers(payload.player_id)
    for _, state in pairs(buildings) do
        if state.player_id == payload.player_id then
            apply_research_technology(state)
            publish(state, "technology_changed")
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
    state.level = next_level
    state.unit.survival_level = next_level
    state.unit.survival_display_name = state.definition.display_name
    apply_common(state.unit, data)
    apply_research_technology(state)
    publish(state, "wall_upgraded")
    return { ok = true }
end

local function upgrade_city(state)
    local next_level = state.level + 1
    local data = state.definition.levels[next_level]
    if not data then return { ok = false, error = "主城已达最高等级" } end
    local result = spend(state, data.upgrade_cost, "upgrade_city")
    if not result or not result.ok then return result end
    state.level = next_level
    state.unit.survival_level = next_level
    state.unit.survival_display_name = state.definition.display_name
    apply_common(state.unit, data)
    if data.add_population then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = state.team,
            max_population = data.add_population,
            reason = "city_level_population",
        })
    end
    publish(state, "city_upgraded")
    refresh_team_farms(state.team)
    return { ok = true }
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
    state.level = next_level
    state.unit.survival_level = next_level
    state.unit.survival_display_name = data.display_name
        or state.definition.display_name
    apply_common(state.unit, data)
    refresh_farm_upgrade_ability(state)
    publish(state, "farm_upgraded")
    return { ok = true }
end

local function route_unit_data(state, row)
    return {
        health = state.unit:GetMaxHealth(),
        armor = state.unit:GetPhysicalArmorBaseValue(),
        damage = row.base_attack_damage,
        attack_range = global_rules.tower_attack_range,
        attack_rate = row.base_attack_speed or 1,
        base_attack_speed = row.base_attack_speed or 1,
        model_name = row.model_name,
        projectile_model = row.projectile_model,
        projectile_speed = row.projectile_speed,
    }
end

sync_tower_abilities = function(state, row)
    tower_ability_sync.sync(state, row)
end

local function apply_model(unit, row)
    if not row or not row.model_name or row.model_name == "" then return end
    unit:SetModel(row.model_name)
    unit:SetOriginalModel(row.model_name)
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
    return { ok = true }
end

local function on_upgrade_request(payload)
    local unit = payload.building
    if not valid_entity(unit) then
        print("[BuildingUpgrade] invalid building entity")
        return
    end
    local state = recover_state(unit)
    if not state then
        print("[BuildingUpgrade] missing state entindex="
            .. tostring(unit:entindex()))
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = unit:GetPlayerOwnerID(),
            message = "建筑升级状态尚未初始化",
            level = "error",
        })
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
        local ability_name = payload.upgrade_mode == "max"
            and "ability_upgrade_tower_max"
            or "ability_upgrade_tower_lv01"
        local ability = unit:FindAbilityByName(ability_name)
        if ability then ability:EndCooldown() end
    end
    notify(state, result and result.ok and "升级成功" or (result and result.error or "升级失败"),
        result and result.ok and "info" or "error")
end

local function on_class_request(payload)
    local unit = payload.tower
    if not valid_entity(unit) then return end
    local state = recover_state(unit)
    if not state or state.building_id ~= "arrow_tower" then return end
    if state.level < 5 then notify(state, "防御塔未达到5级", "error"); return end
    if state.tower_class then notify(state, "防御塔已经完成转职", "error"); return end

    local class_data = state.definition.class_options[payload.class_index]
    if not class_data then notify(state, "无效的转职方向", "error"); return end
    local row = tower_routes.get(class_data.id, 1)
    if not row then notify(state, "路线配置缺失", "error"); return end
    local result = spend(
        state,
        tower_routes.class_change_cost(row),
        "tower_class_change"
    )
    if not result or not result.ok then
        notify(state, result and result.error or "资源不足", "error")
        return
    end

    state.tower_class = class_data.id
    apply_tower_level(state, row, 6, true)
    if row.population_delta and row.population_delta > 0 then
        event_bus.request(events.RESOURCE_ADD_REQUEST, { team = state.team, max_population = row.population_delta, reason = "tower_route_population" })
    end
    set_class_buttons(state.unit, false)
    publish(state, "tower_class_changed")
    notify(state, "防御塔已转职为" .. state.tower_class_name)
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
        end
    end
    sync_technology_levels(payload.player_id)
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
    buildings = {}
    technology_levels = {}
    event_bus.subscribe(events.BUILDING_CREATED, on_created)
    event_bus.subscribe(events.BUILDING_DESTROYED, on_destroyed)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.BUILDING_UPGRADE_REQUEST, on_upgrade_request)
    event_bus.subscribe(events.TOWER_CLASS_REQUEST, on_class_request)
    event_bus.subscribe(events.TECHNOLOGY_CHANGED, on_technology_changed)
end

return M
