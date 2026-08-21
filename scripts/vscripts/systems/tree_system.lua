local event_bus = require("core/event_bus")
local events = require("core/events")
local config = require("config/tree_config")
local particle_manager = require("core/particle_manager")
local rogue_effect_state = require("systems/rogue_effect_state_service")

local M = {}
local current_tree = nil
local main_city = nil
local tree_level = 1
local reserved_grid = nil

local function valid_entity(entity)
    return entity and not entity:IsNull()
end

local function wall_is_under_attack(player_id)
    local response = event_bus.request(events.BUILDING_LIST_REQUEST, {
        player_id = player_id,
    }) or {}
    local wall = nil
    for _, building in ipairs(response.buildings or response) do
        if building.building_id == "wall" and valid_entity(building.unit) then
            wall = building.unit
            break
        end
    end
    if not wall or not Entities or not Entities.FindAllByClassname then return false end
    for _, unit in ipairs(Entities:FindAllByClassname("npc_dota_creature") or {}) do
        if valid_entity(unit) and unit:IsAlive()
            and (unit.survival_is_wave_monster == true
                or unit.survival_is_challenge_monster == true)
            and unit.GetAttackTarget and unit:GetAttackTarget() == wall then
            return true
        end
    end
    return false
end

local function level_row(level)
    return config.levels[math.max(
        1,
        math.min(config.max_level, tonumber(level) or 1)
    )]
end

local function tree_grid()
    local point = config.spawn_point
    local footprint = config.footprint
    local size = tonumber(config.grid_cell_size) or 64
    local anchor_x = math.floor(point.x / size + 0.5)
    local anchor_y = math.floor(point.y / size + 0.5)
    return {
        grid_x = anchor_x - math.floor(footprint.x / 2),
        grid_y = anchor_y - math.floor(footprint.y / 2),
        footprint = footprint,
    }
end

local function lumber_efficiency_buff(level)
    return math.max(
        0,
        tonumber(config.lumber_efficiency_buff_per_level) or 0
    ) * math.max(0, (tonumber(level) or tree_level) - 1)
end

local function tree_snapshot()
    local row = level_row(tree_level)
    return {
        level = tree_level,
        max_level = config.max_level,
        health = row.health,
        armor = row.armor,
        war3_armor = row.war3_armor,
        minimum_armor = row.minimum_armor,
        war3_minimum_armor = row.war3_minimum_armor,
        lumber_efficiency_buff = lumber_efficiency_buff(tree_level),
    }
end

local function publish_changed(reason)
    local snapshot = tree_snapshot()
    snapshot.reason = reason or "unknown"
    snapshot.entindex = valid_entity(current_tree)
        and current_tree:entindex() or -1
    event_bus.emit(events.TREE_CHANGED, snapshot)
end

local function clear_armor_reduction(tree)
    if tree.HasModifier
        and tree:HasModifier("modifier_research_armor_reduction") then
        tree:RemoveModifierByName("modifier_research_armor_reduction")
    end
end

local function apply_level(tree, level)
    tree_level = math.max(
        1,
        math.min(config.max_level, tonumber(level) or 1)
    )
    local row = level_row(tree_level)
    clear_armor_reduction(tree)
    tree:SetBaseMaxHealth(row.health)
    tree:SetMaxHealth(row.health)
    tree:SetPhysicalArmorBaseValue(row.armor)
    tree.survival_minimum_armor = row.minimum_armor
    tree.survival_tree_level = tree_level
    tree.survival_level = tree_level
    tree:SetHealth(row.health)
end

local function reserve_tree_grid(entindex)
    reserved_grid = reserved_grid or tree_grid()
    event_bus.request(events.GRID_OCCUPY_REQUEST, {
        grid_x = reserved_grid.grid_x,
        grid_y = reserved_grid.grid_y,
        footprint = reserved_grid.footprint,
        entindex = entindex or "survival_tree_reserved",
    })
end

local function upgrade_tree(tree)
    if not valid_entity(tree) or tree ~= current_tree then return end
    local previous_level = tree_level
    local next_level = math.min(config.max_level, tree_level + 1)
    apply_level(tree, next_level)
    reserve_tree_grid(tree:entindex())
    local reason = next_level > previous_level
        and "tree_level_up" or "tree_max_level_reset"
    publish_changed(reason)
end

local function spawn_tree(payload)
    local city = payload and payload.unit or main_city
    if not valid_entity(city) then
        print("[TreeSystem] main city entity is unavailable")
        return
    end
    if valid_entity(current_tree) then return end

    local point = config.spawn_point
    local position = Vector(point.x, point.y, point.z)
    local tree = CreateUnitByName(
        config.unit_name,
        position,
        false,
        nil,
        nil,
        DOTA_TEAM_BADGUYS
    )
    if not tree then
        print("[TreeSystem] failed to create tree")
        return
    end

    tree:SetAbsOrigin(position)
    tree:SetModel(config.model_name)
    tree:SetOriginalModel(config.model_name)
    tree:SetModelScale(config.model_scale)
    tree:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK)
    tree.survival_tree_depleted_callback = upgrade_tree
    apply_level(tree, tree_level)
    if not tree:HasModifier("modifier_tree_progression") then
        tree:AddNewModifier(tree, nil, "modifier_tree_progression", {})
    end
    current_tree = tree
    reserve_tree_grid(tree:entindex())

    local snapshot = tree_snapshot()
    snapshot.entindex = tree:entindex()
    event_bus.emit(events.TREE_SPAWNED, snapshot)
    publish_changed("tree_spawned")
end

local function on_tree_hit(payload)
    if not valid_entity(current_tree) then return end
    if not payload.target
        or payload.target:entindex() ~= current_tree:entindex() then
        return
    end
    local attacker = payload.attacker
    if not valid_entity(attacker) then return end
    local base_efficiency = payload.source == "hero"
        and config.hero_base_lumber_efficiency
        or payload.base_lumber_efficiency
    local hero_wood_bonus_pct = 0
    if payload.source == "hero" then
        hero_wood_bonus_pct = rogue_effect_state.numeric(payload.player_id,
            "builder_hero_wood_bonus_pct")
    elseif payload.source == "lumberjack" then
        local peaceful = rogue_effect_state.numeric(payload.player_id,
            "builder_peaceful_wood_per_hit")
        if peaceful > 0 and not wall_is_under_attack(payload.player_id) then
            base_efficiency = (tonumber(base_efficiency) or 0)
                + peaceful
        end
        if payload.attacker and payload.attacker.survival_super_lumberjack then
            payload.critical_chance_pct = (tonumber(payload.critical_chance_pct) or 0)
                + rogue_effect_state.numeric(payload.player_id,
                    "builder_super_lumberjack_crit_pct")
        end
    end
    local efficiency = math.max(0, math.floor(
        (tonumber(base_efficiency) or 0) + lumber_efficiency_buff(tree_level)
            * math.max(1, tonumber(payload.fusion_count) or 1)
    ))
    if hero_wood_bonus_pct > 0 then
        efficiency = math.floor(efficiency * (1 + hero_wood_bonus_pct / 100))
    end
    local wood_total_bonus_pct = math.max(
        0, tonumber(payload.wood_total_bonus_pct) or 0
    )
    local next_wood_fraction = nil
    if payload.source == "lumberjack" and wood_total_bonus_pct > 0 then
        local exact = efficiency * (1 + wood_total_bonus_pct / 100)
            + (tonumber(attacker.survival_wood_fraction) or 0)
        efficiency = math.floor(exact + 0.0000001)
        next_wood_fraction = exact - efficiency
    end
    local critical = payload.critical == true
        or payload.source == "lumberjack"
        and RandomFloat(0, 100)
            < math.max(0, tonumber(payload.critical_chance_pct) or 0)
    if critical then efficiency = efficiency * 2 end
    if tonumber(payload.wood_multiplier_chance_pct)
        and RandomFloat(0, 100) < tonumber(payload.wood_multiplier_chance_pct) then
        efficiency = efficiency * 10
    end
    if efficiency <= 0 then return end
    local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
        player_id = payload.player_id,
        team = payload.team,
        wood = efficiency,
        gold = tonumber(payload.gold_per_hit_flat) or 0,
        reason = payload.source == "hero"
            and "hero_tree_hit" or "lumberjack_hit",
    })
    if not result or result.ok ~= true then return end
    if next_wood_fraction ~= nil then
        attacker.survival_wood_fraction = next_wood_fraction
    end
    local tree_damage_pct = math.max(
        0, tonumber(payload.tree_damage_chance_pct) or 0
    )
    if current_tree:GetHealth() > 1 and tree_damage_pct > 0
        and RandomFloat(0, 100) < tree_damage_pct then
        local amount = math.max(1, math.floor(
            current_tree:GetMaxHealth() * tree_damage_pct / 100
        ))
        local health = current_tree:GetHealth()
        if health > 1 then
            current_tree:SetHealth(math.max(1, health - amount))
        end
        if current_tree:GetHealth() <= 1 then
            event_bus.emit(events.TREE_DEPLETED, {
                attacker = attacker,
                target = current_tree,
                player_id = payload.player_id,
            })
            local callback = current_tree.survival_tree_depleted_callback
            if type(callback) == "function" then callback(current_tree) end
        end
    end
    local player = payload.player_id ~= nil
        and PlayerResource:GetPlayer(payload.player_id) or nil
    particle_manager.show_green_number(attacker, efficiency, player)
    local gold_amount = math.max(0, math.floor(
        tonumber(payload.gold_per_hit_flat) or 0
    ))
    if player and gold_amount > 0 then
        CustomGameEventManager:Send_ServerToPlayer(
            player,
            "survival_gold_mine_income_number",
            {
                target_entindex = attacker:entindex(),
                amount = gold_amount,
                critical = 0,
            }
        )
    end
end

local function on_building_created(payload)
    if not payload or payload.building_id ~= "main_city" then return end
    if not valid_entity(payload.unit) then return end
    main_city = payload.unit
    spawn_tree(payload)
end

function M.init()
    current_tree = nil
    main_city = nil
    tree_level = 1
    reserved_grid = nil
    reserve_tree_grid("survival_tree_reserved")
    event_bus.subscribe(events.BUILDING_CREATED, on_building_created)
    event_bus.subscribe(events.TREE_HIT, on_tree_hit)
end

M._level_row_for_test = level_row
M._tree_grid_for_test = tree_grid
M._apply_level_for_test = apply_level
M._upgrade_tree_for_test = function(tree)
    current_tree = tree
    upgrade_tree(tree)
end
M._reset_for_test = function(level, tree)
    tree_level = tonumber(level) or 1
    current_tree = tree
end

M._lumber_efficiency_buff_for_test = lumber_efficiency_buff

return M