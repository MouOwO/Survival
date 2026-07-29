local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/buildings_config")
local arrow_tower_base = require("config/generated/arrow_tower_base")
local global_rules = require("config/global_rules")
local logger = require("core/logger")
local modifier_registry = require("core/modifier_registry")
local team_alignment = require("core/team_alignment")
local tower_skills = require("systems/tower_skill_runtime")
local scheduler = require("core/scheduler")
local grid_config = require("config/grid_config")
local building_population = require("systems/building_population_service")
local building_visual = require("systems/building_visual_service")
local M = {}
local RELOCATION_RANGE = 1000
print("[SURVIVAL_FINGERPRINT] building_system=20260727_arrow_completion_fix")
local buildings = {}
local counts = {}
local wall_ever_built = {}
local function valid_entity(entity)
    return entity and not entity:IsNull()
end
local function position_is_clear(position)
    local traversable = true
    local blocked = false
    pcall(function() traversable = GridNav:IsTraversable(position) end)
    pcall(function() blocked = GridNav:IsBlocked(position) end)
    return traversable and not blocked
end
local function builder_work_position(caster, definition, origin)
    if not valid_entity(caster) then return nil end
    local footprint = definition.footprint or { x = 1, y = 1 }
    local cell_size = tonumber(grid_config.cell_size) or 128
    local building_radius = math.max(footprint.x, footprint.y) * cell_size * 0.5
    local hull = caster.GetHullRadius and (caster:GetHullRadius() or 0) or 0
    local safe_radius = building_radius + hull + 160
    local direction = caster:GetAbsOrigin() - origin
    direction.z = 0
    if direction:Length2D() < 1 then
        direction = caster:GetForwardVector()
    end
    direction = direction:Normalized()
    for step = 0, 11 do
        local angle = math.rad(step * 30)
        local candidate_direction = Vector(
            direction.x * math.cos(angle) - direction.y * math.sin(angle),
            direction.x * math.sin(angle) + direction.y * math.cos(angle),
            0
        )
        local candidate = origin + candidate_direction * safe_radius
        candidate.z = GetGroundHeight(candidate, caster)
        if position_is_clear(candidate) then
            return candidate
        end
    end
    return origin + Vector(safe_radius, 0, 0)
end
local function builder_ready(caster, definition, origin, work_position)
    if not valid_entity(caster) then return false end
    if not work_position then return false end
    local distance = (caster:GetAbsOrigin() - origin):Length2D()
    local work_distance = (caster:GetAbsOrigin() - work_position):Length2D()
    local cell_size = tonumber(grid_config.cell_size) or 128
    local footprint = definition.footprint or { x = 1, y = 1 }
    local hull = caster.GetHullRadius and (caster:GetHullRadius() or 0) or 0
    local safe_radius = math.max(footprint.x, footprint.y) * cell_size * 0.5
        + hull + 160
    return distance >= safe_radius - 48 and work_distance <= 48
end
local function notify(player_id, message, level)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = message,
        level = level or "info",
    })
end
local function count_for(team, building_id)
    counts[team] = counts[team] or {}
    return counts[team][building_id] or 0
end
local function change_count(team, building_id, delta)
    counts[team] = counts[team] or {}
    counts[team][building_id] = math.max(0, (counts[team][building_id] or 0) + delta)
end
local function building_limit_reached(definition, existing_count)
    local maximum = tonumber(definition and definition.max_count) or 0
    return maximum > 0 and (tonumber(existing_count) or 0) >= maximum
end
local function main_city_level(team)
    for _, state in pairs(buildings) do
        if state.team == team
            and state.building_id == "main_city"
            and valid_entity(state.unit) then
            return state.level or 0
        end
    end
    return 0
end
local function set_attack_range(unit, attack_range)
    attack_range = tonumber(attack_range) or global_rules.tower_attack_range
    if unit.Script_SetAttackRange then
        unit:Script_SetAttackRange(attack_range)
    elseif unit.SetAttackRange then
        unit:SetAttackRange(attack_range)
    end
    if unit.SetAcquisitionRange then
        unit:SetAcquisitionRange(math.max(
            global_rules.tower_acquisition_range,
            attack_range
        ))
    end
end
local function arrow_data(level)
    for _, row in ipairs(arrow_tower_base.rows) do
        if row.level == level then return row end
    end
    return nil
end
local function apply_attack_speed(unit, attacks_per_second)
    local speed = tonumber(attacks_per_second) or 1
    speed = math.max(0.01, speed)
    unit.survival_attack_speed = speed
    unit:SetBaseAttackTime(1 / speed)
    if not unit:HasModifier("modifier_debug_attack_cap") then
        unit:AddNewModifier(unit, nil, "modifier_debug_attack_cap", {})
    end
end
local function apply_projectile(unit, projectile_model)
    if projectile_model and projectile_model ~= ""
        and unit.SetRangedProjectileName then
        unit:SetRangedProjectileName(projectile_model)
        unit.survival_projectile_model = projectile_model
    end
end
local function apply_initial_stats(unit, definition)
    local data = definition.id == "arrow_tower"
        and definition.pre_class_levels[1]
        or definition.levels[1]
    unit:SetBaseMaxHealth(data.health)
    unit:SetMaxHealth(data.health)
    unit:SetHealth(data.health)
    unit:SetPhysicalArmorBaseValue(data.armor)
    unit.survival_armor = tonumber(data.armor) or 0
    if definition.id == "arrow_tower" and unit.SetAttackCapability then
        unit:SetAttackCapability(DOTA_UNIT_CAP_RANGED_ATTACK)
    end
    if data.model_name and data.model_name ~= "" then
        unit:SetModel(data.model_name)
        unit:SetOriginalModel(data.model_name)
    end
    if definition.id == "arrow_tower" then
        local combat = arrow_data(1) or {}
        unit:SetBaseDamageMin(combat.base_attack_damage or data.damage)
        unit:SetBaseDamageMax(combat.base_attack_damage or data.damage)
        unit.survival_level = 1
        unit.survival_display_name = combat.name or definition.display_name
        apply_attack_speed(unit, combat.base_attack_speed or 1)
        apply_projectile(unit, combat.projectile_model)
        set_attack_range(unit, data.attack_range)
    end
end
local function add_ability(unit, ability_name, active)
    print("[BuildingAbility] add begin unit=" .. tostring(unit:entindex()) .. " ability=" .. tostring(ability_name))
    local ability = unit:FindAbilityByName(ability_name) or unit:AddAbility(ability_name)
    if not ability then
        print("[BuildingAbility] AddAbility FAILED unit=" .. tostring(unit:entindex()) .. " ability=" .. tostring(ability_name))
        return false
    end
    ability:SetLevel(1)
    if ability.SetHidden then ability:SetHidden(false) end
    ability:SetActivated(active ~= false)
    print("[BuildingAbility] AddAbility OK unit=" .. tostring(unit:entindex()) .. " ability=" .. tostring(ability_name) .. " index=" .. tostring(ability:GetAbilityIndex()))
    return true
end
local function add_building_abilities(unit, definition, active)
    -- Building relocation is driven by Panorama; creature point abilities do
    -- not reliably enter OnSpellStart in this project.
    if definition.id == "arrow_tower" then
        local row = arrow_data(1)
        for _, ability_name in ipairs(row and row.active_skill_ids or {}) do
            add_ability(unit, ability_name, active ~= false)
        end
        return
    end
    for _, ability_name in ipairs(definition.abilities or {}) do
        add_ability(unit, ability_name, active ~= false)
    end
end
local function completion_level_data(definition, level)
    definition = definition or {}
    local levels = definition.levels or definition.pre_class_levels or {}
    return levels[tonumber(level) or 1] or {}
end
local function public_state(state)
    return {
        entindex = state.unit:entindex(),
        unit = state.unit,
        definition = state.definition,
        team = state.team,
        player_id = state.player_id,
        building_id = state.building_id,
        level = state.level,
        tower_class = state.tower_class,
        tower_class_name = state.tower_class_name,
        display_name = state.tower_class_name
            or (state.building_id == "arrow_tower"
                and ((arrow_data(state.level) or {}).name)
                or state.definition.display_name),
        configured_attack_damage = state.building_id == "arrow_tower"
            and (arrow_data(state.level) or {}).base_attack_damage or nil,
        configured_attack_speed = state.building_id == "arrow_tower"
            and (arrow_data(state.level) or {}).base_attack_speed or nil,
        base_health = state.unit:GetMaxHealth(),
        runtime_armor = tonumber(state.unit.survival_armor)
            or state.unit:GetPhysicalArmorBaseValue(),
        base_attack_damage = state.building_id == "arrow_tower"
            and tonumber((arrow_data(state.level) or {}).base_attack_damage)
            or nil,
    }
end
require("systems/building_relocation").bind(
    function(entindex) return buildings[entindex] end,
    public_state
)
local function can_place(payload)
    local definition = config[payload.building_id]
    local caster = payload.caster
    if not definition or not valid_entity(caster) then
        return { ok = false, error = "invalid_build_request" }
    end
    local team = DOTA_TEAM_GOODGUYS
    team_alignment.enforce(caster, team, "builder_caster")
    if definition.build_once and wall_ever_built[team] then
        return { ok = false, error = "城墙整局只能建造一次" }
    end
    if building_limit_reached(definition, count_for(team, definition.id)) then
        return { ok = false, error = "建筑数量已达上限" }
    end
    if definition.unlock_city_level
        and main_city_level(team) < definition.unlock_city_level then
        return {
            ok = false,
            error = "主城达到Lv." .. tostring(definition.unlock_city_level) .. "后解锁",
        }
    end
    local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = payload.position,
        footprint = definition.footprint,
    })
    if not grid or not grid.ok then
        return grid or { ok = false, error = "建造位置验证失败" }
    end
    return {
        ok = true,
        definition = definition,
        team = team,
        player_id = caster:GetPlayerOwnerID(),
        grid = grid,
    }
end
local function start_building(payload)
    print("[SURVIVAL_FINGERPRINT] create_building=20260720_1045_direct_path")
    local check = can_place(payload)
    if not check.ok then
        notify(payload.caster and payload.caster:GetPlayerOwnerID() or -1, check.error, "error")
        return check
    end
    local cost = check.definition.build_cost
    local spend = event_bus.request(events.RESOURCE_TRY_SPEND_REQUEST, {
        team = check.team,
        wood = cost.wood,
        gold = cost.gold,
        population = check.definition.population_cost or 0,
        reason = "build:" .. check.definition.id,
    })
    if not spend or not spend.ok then
        notify(check.player_id, spend and spend.error or "资源扣除失败", "error")
        return spend
    end
    local unit = CreateUnitByName(
        check.definition.unit_name,
        check.grid.world_position,
        true,
        payload.caster,
        payload.caster,
        check.team
    )
    if not unit then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            team = check.team,
            wood = cost.wood,
            gold = cost.gold,
            reason = "build_refund:" .. check.definition.id,
        })
        event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
            team = check.team,
            population = check.definition.population_cost or 0,
            reason = "build_population_refund:" .. check.definition.id,
        })
        notify(check.player_id, "建筑创建失败", "error")
        return { ok = false, error = "building_create_failed" }
    end
    team_alignment.enforce(unit, check.team, "building")
    unit.survival_level = 1
    unit.survival_display_name = check.definition.display_name
    unit.survival_is_building = true
    unit:SetOwner(payload.caster)
    apply_initial_stats(unit, check.definition)
    add_building_abilities(unit, check.definition, false)
    local state = {
        unit = unit,
        definition = check.definition,
        team = check.team,
        player_id = check.player_id,
        building_id = check.definition.id,
        level = 1,
        grid_x = check.grid.grid_x,
        grid_y = check.grid.grid_y,
        tower_class = nil,
        tower_class_name = nil,
        tower_combat = arrow_data(1),
    }
    change_count(check.team, check.definition.id, 1)
    if check.definition.build_once then wall_ever_built[check.team] = true end
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = state.grid_x,
        grid_y = state.grid_y,
        footprint = state.definition.footprint,
        entindex = unit:entindex(),
    })
    unit:AddNewModifier(
        unit,
        nil,
        "modifier_building_under_construction",
        {}
    )
    local maximum_health = unit:GetMaxHealth()
    local build_time = math.max(0.1, tonumber(check.definition.build_time) or 3)
    local started_at = GameRules:GetGameTime()
    unit:SetHealth(1)
    local particle = nil
    if check.definition.build_particle
        and check.definition.build_particle ~= "" then
        particle = ParticleManager:CreateParticle(
            check.definition.build_particle,
            PATTACH_ABSORIGIN_FOLLOW,
            unit
        )
    end
    if valid_entity(payload.caster) then
        payload.caster:StartGesture(ACT_DOTA_ATTACK)
        if payload.caster.survival_build_task == payload.build_task then
            payload.caster.survival_build_task = nil
        end
    end
    scheduler.every(0.1, function()
        if not valid_entity(unit) then
            if particle then
                ParticleManager:DestroyParticle(particle, false)
                ParticleManager:ReleaseParticleIndex(particle)
            end
            change_count(check.team, check.definition.id, -1)
            event_bus.request(events.GRID_RELEASE_REQUEST, {
                grid_x = state.grid_x,
                grid_y = state.grid_y,
                footprint = state.definition.footprint,
            })
            return false
        end
        local progress = math.min(
            1,
            (GameRules:GetGameTime() - started_at) / build_time
        )
        unit:SetHealth(math.max(1, math.floor(maximum_health * progress)))
        if progress < 1 then return true end

        if particle then
            ParticleManager:DestroyParticle(particle, false)
            ParticleManager:ReleaseParticleIndex(particle)
        end
        unit:RemoveModifierByName("modifier_building_under_construction")
        -- Restore construction-disabled abilities before applying optional
        -- completion visuals. Arrow towers use pre_class_levels rather than
        -- levels, and a malformed visual row must never leave their abilities
        -- permanently deactivated.
        add_building_abilities(unit, check.definition, true)
        local completed_level = completion_level_data(
            state.definition,
            state.level
        )
        building_visual.apply(unit, completed_level)
        unit:SetHealth(maximum_health)
        unit:SetControllableByPlayer(check.player_id, true)
        buildings[unit:entindex()] = state
        -- Keep ability entity indexes stable for runtime tooltip data. Activate
        -- once now and once after the construction modifier state has replicated.
        scheduler.after(0.1, function()
            if valid_entity(unit) then
                add_building_abilities(unit, check.definition, true)
            end
        end, "activate_building_abilities_" .. tostring(unit:entindex()))
        if check.definition.id == "arrow_tower" then
            for _, ability_name in ipairs({
                "ability_upgrade_tower_lv01",
                "ability_upgrade_tower_max",
            }) do
                local ability = unit:FindAbilityByName(ability_name)
                print(string.format(
                    "[TowerUpgradeReady] tower=%d ability=%s entindex=%s level=%s activated=%s",
                    unit:entindex(), ability_name,
                    ability and tostring(ability:entindex()) or "nil",
                    ability and tostring(ability:GetLevel()) or "nil",
                    ability and tostring(ability:IsActivated()) or "nil"
                ))
            end
        end
        local data = public_state(state)
        event_bus.emit(events.BUILDING_CREATED, data)
        if check.definition.id == "arrow_tower" then
            unit:AddNewModifier(unit, nil, "modifier_tower_auto_attack", {})
            unit:AddNewModifier(unit, nil, "modifier_tower_attack_effects", {})
        end
        if check.definition.id == "arrow_tower" then
            local initial_row = arrow_data(1)
            tower_skills.apply(
                unit,
                initial_row and initial_row.skill_ids or {}
            )
        end
        building_population.grant_level(
            state,
            state.level,
            state.building_id .. "_created_population"
        )
        data.reason = "created"
        event_bus.emit(events.BUILDING_CHANGED, data)
        notify(state.player_id, state.definition.display_name .. "已建造")
        return false
    end, "construct_building_" .. tostring(unit:entindex()))
    notify(check.player_id, check.definition.display_name .. "开始建造")
    return {
        ok = true,
        entindex = unit:entindex(),
        constructing = true,
        build_time = build_time,
    }
end
local function queue_building(payload)
    local check = can_place(payload)
    if not check.ok then
        notify(payload.caster and payload.caster:GetPlayerOwnerID() or -1, check.error, "error")
        return check
    end
    local caster = payload.caster
    if caster.survival_build_task then
        if caster.survival_build_task.constructing then
            return { ok = false, error = "建筑正在施工中" }
        end
        caster.survival_build_task = nil
    end
    local target = check.grid.world_position
    local work_position = builder_work_position(caster, check.definition, target)
    if not work_position then
        return { ok = false, error = "找不到可建造位置" }
    end
    local task = {
        building_id = payload.building_id,
        target = target,
        work_position = work_position,
    }
    caster.survival_build_task = task
    ExecuteOrderFromTable({
        UnitIndex = caster:entindex(),
        OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        Position = work_position,
        Queue = false,
    })
    scheduler.every(0.1, function()
        if not valid_entity(caster) then return false end
        if caster.survival_build_task ~= task then return false end
        local current = event_bus.request(events.BUILD_CAN_PLACE_REQUEST, {
            caster = caster,
            building_id = payload.building_id,
            position = target,
        })
        if not current or not current.ok then
            if caster.survival_build_task == task then
                caster.survival_build_task = nil
            end
            notify(caster:GetPlayerOwnerID(), current and current.error or "建造位置失效", "error")
            return false
        end
        if not builder_ready(
            caster,
            current.definition,
            target,
            work_position
        ) then
            return true
        end
        payload.build_task = task
        local result = start_building(payload)
        if not result or not result.ok then
            if caster.survival_build_task == task then
                caster.survival_build_task = nil
            end
        end
        return false
    end, "queue_building_" .. tostring(caster:entindex()))
    notify(caster:GetPlayerOwnerID(), check.definition.display_name .. "正在前往建造位置")
    return { ok = true, moving = true, target = target }
end
local function query_building(payload)
    local state = buildings[payload.entindex]
    if not state or not valid_entity(state.unit) then return nil end
    return public_state(state)
end
local function on_building_changed(payload)
    local state = buildings[payload.entindex]
    if not state then return end
    state.level = payload.level or state.level
    state.tower_class = payload.tower_class
    state.tower_class_name = payload.tower_class_name
end
local function on_entity_killed(payload)
    local victim = payload.victim
    if not valid_entity(victim) then return end
    local state = buildings[victim:entindex()]
    if not state then return end
    building_visual.clear(victim)
    buildings[victim:entindex()] = nil
    change_count(state.team, state.building_id, -1)
    event_bus.request(events.GRID_RELEASE_REQUEST, {
        grid_x = state.grid_x,
        grid_y = state.grid_y,
        footprint = state.definition.footprint,
    })
    event_bus.emit(events.BUILDING_DESTROYED, public_state(state))
    if (state.definition.population_cost or 0) > 0 then
        event_bus.request(events.RESOURCE_RELEASE_POP_REQUEST, {
            team = state.team,
            population = state.definition.population_cost,
            reason = "building_destroyed:" .. state.building_id,
        })
    end
    if state.building_id == "main_city" then
        GameRules:SetGameWinner(DOTA_TEAM_BADGUYS)
    end
end
function M.relocate_building(unit, position)
    return require("systems/building_relocation").move(unit, position)
end

function M.main_city_for_team(team)
    for _, state in pairs(buildings) do
        if state.team == team
            and state.building_id == "main_city"
            and valid_entity(state.unit)
            and state.unit:IsAlive() then
            return state.unit
        end
    end
    return nil
end

function M.relocate_for_player(player_id, entindex, position)
    local state = buildings[tonumber(entindex) or -1]
    if not state or not valid_entity(state.unit) then
        return false, "building_not_found"
    end
    if state.player_id ~= player_id then
        return false, "building_not_owned"
    end
    if state.building_id ~= "wall" and state.building_id ~= "arrow_tower" then
        return false, "building_not_movable"
    end
    local origin = state.unit:GetAbsOrigin()
    local dx = position.x - origin.x
    local dy = position.y - origin.y
    if (dx * dx + dy * dy) > (RELOCATION_RANGE * RELOCATION_RANGE) then
        notify(player_id, "超出范围", "error")
        return false, "relocation_out_of_range"
    end
    local grid = event_bus.request(events.GRID_CAN_PLACE_REQUEST, {
        position = position,
        footprint = state.definition.footprint,
        ignore_entindex = state.unit:entindex(),
    })
    if not grid or not grid.ok then
        notify(player_id, grid and grid.error or "移动位置不可用", "error")
        return false, grid and grid.error or "relocation_position_invalid"
    end
    return M.relocate_building(state.unit, grid.world_position)
end

function M.init()
    modifier_registry.register()
    buildings = {}
    counts = {}
    wall_ever_built = {}
    event_bus.handle_request(events.BUILD_CAN_PLACE_REQUEST, can_place)
    event_bus.handle_request(events.BUILDING_QUERY_REQUEST, query_building)
    event_bus.subscribe(events.BUILD_REQUEST, queue_building)
    event_bus.subscribe(events.BUILDING_CHANGED, on_building_changed)
    event_bus.subscribe(events.ENGINE_ENTITY_KILLED, on_entity_killed)
    logger.info("BuildingSystem", "initialized")
end
M._completion_level_data_for_test = completion_level_data
M._public_state_for_test = public_state
M._building_limit_for_test = {
    reached = building_limit_reached,
    count_for = count_for,
    change_count = change_count,
    reset = function() counts = {} end,
}
return M
