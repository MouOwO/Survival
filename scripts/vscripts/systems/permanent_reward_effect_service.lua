local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local armor_balance = require("config/armor_balance")
local map_level_effect_rules = require("config/generated/map_level_effect_rules")

local M = {}
local totals_by_player = {}
local hero_ticks_by_player = {}
local tower_ticks_by_player = {}
local hero_tick_attributes_by_player = {}
local hero_tick_attack_by_player = {}
local tower_tick_attack_by_player = {}
local tower_damage_bonus_by_player = {}
local hero_damage_attack_bonus_by_player = {}
local hero_basic_attack_bonus_by_player = {}
local hero_growth_attributes_by_player = {}
local tower_basic_attack_bonus_by_player = {}
local wall_ticks_by_player = {}
local wall_tick_health_by_player = {}
local wall_tick_armor_by_player = {}
local test_isolated_field_by_player = {}
local refresh_existing_enemy_armor = nil

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[tostring(key)] = tonumber(value) or 0
    end
    return result
end

local function add_values(target, source)
    for key, value in pairs(source or {}) do
        key = tostring(key)
        target[key] = (tonumber(target[key]) or 0) + (tonumber(value) or 0)
    end
    return target
end

-- Map level is stored once as permanent player progression. Its gameplay
-- effects stay data-driven here instead of being copied into every item that
-- grants a level.
local function apply_map_level_effects(target)
    for _, rule in ipairs(map_level_effect_rules.rows or {}) do
        if rule.enabled ~= false and rule.stacking_rule == "add" then
            local source_field_id = tostring(rule.source_field_id or "")
            local target_field_id = tostring(rule.target_field_id or "")
            local level = tonumber(target[source_field_id]) or 0
            local value_per_level = tonumber(rule.value_per_level) or 0
            if source_field_id ~= "" and target_field_id ~= ""
                and level > 0 and value_per_level ~= 0 then
                target[target_field_id] = (tonumber(target[target_field_id]) or 0)
                    + level * value_per_level
            end
        end
    end
    return target
end

local function refresh(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    local profile_service = require("systems/player_profile_service")
    local profile = profile_service.get_profile(player_id)
    local save = profile and profile.save or {}
    local isolated_field = test_isolated_field_by_player[player_id]
    if isolated_field then
        totals_by_player[player_id] = {
            [isolated_field] = tonumber(
                save.gameplay_stats and save.gameplay_stats[isolated_field]
            ) or 0,
        }
    else
        totals_by_player[player_id] = apply_map_level_effects(add_values(
            copy(save.permanent_effects), save.gameplay_stats
        ))
    end
    hero_ticks_by_player[player_id] = hero_ticks_by_player[player_id] or 0
    tower_ticks_by_player[player_id] = tower_ticks_by_player[player_id] or 0
    hero_tick_attributes_by_player[player_id] =
        hero_tick_attributes_by_player[player_id] or 0
    hero_tick_attack_by_player[player_id] =
        hero_tick_attack_by_player[player_id] or 0
    tower_tick_attack_by_player[player_id] =
        tower_tick_attack_by_player[player_id] or 0
    tower_damage_bonus_by_player[player_id] = tower_damage_bonus_by_player[player_id] or 0
    hero_damage_attack_bonus_by_player[player_id] =
        hero_damage_attack_bonus_by_player[player_id] or 0
    hero_basic_attack_bonus_by_player[player_id] =
        hero_basic_attack_bonus_by_player[player_id] or 0
    hero_growth_attributes_by_player[player_id] =
        hero_growth_attributes_by_player[player_id] or 0
    tower_basic_attack_bonus_by_player[player_id] =
        tower_basic_attack_bonus_by_player[player_id] or 0
    wall_ticks_by_player[player_id] = wall_ticks_by_player[player_id] or 0
    wall_tick_health_by_player[player_id] =
        wall_tick_health_by_player[player_id] or 0
    wall_tick_armor_by_player[player_id] =
        wall_tick_armor_by_player[player_id] or 0
    print("[PermanentReward] projection_refreshed player_id=" .. tostring(player_id)
        .. " revision=" .. tostring(profile and profile.revision or 0)
        .. " hero_all_attributes_flat="
        .. tostring(totals_by_player[player_id].hero_all_attributes_flat or 0)
        .. " map_level="
        .. tostring(totals_by_player[player_id].map_level or 0))
    event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
        player_id = player_id,
        totals = copy(totals_by_player[player_id]),
        revision = profile and profile.revision or 0,
    })
    for other_player_id in pairs(totals_by_player) do
        if other_player_id ~= player_id then
            event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
                player_id = other_player_id,
                reason = "shared_gameplay_stats_changed",
            })
        end
    end
    if refresh_existing_enemy_armor then refresh_existing_enemy_armor() end
end

local function valid_entity(unit)
    if not unit then return false end
    if type(unit.IsNull) ~= "function" then return true end
    local ok, null = pcall(unit.IsNull, unit)
    return ok and not null
end

local function player_unit(player_id)
    local result = event_bus.request(events.HERO_SUMMON_GET_REQUEST, {
        player_id = player_id,
    })
    return result and (result.hero or result.unit)
end

local function apply_hero_tick(player_id)
    local attribute_amount = M.value(player_id, "hero_attributes_per_second")
    local attack_amount = M.value(player_id, "hero_attack_per_second")
    if attribute_amount <= 0 and attack_amount <= 0 then return end
    local hero = player_unit(player_id)
    if not valid_entity(hero) or (hero.IsAlive and not hero:IsAlive()) then return end
    hero_ticks_by_player[player_id] = (hero_ticks_by_player[player_id] or 0) + 1
    hero_tick_attributes_by_player[player_id] =
        (hero_tick_attributes_by_player[player_id] or 0)
            + math.max(0, attribute_amount)
    hero_tick_attack_by_player[player_id] =
        (hero_tick_attack_by_player[player_id] or 0)
            + math.max(0, attack_amount)
    event_bus.emit(events.HERO_PROGRESSION_CHANGED, {
        player_id = player_id,
        reason = "star_blessing_attributes_per_second",
        amount = attribute_amount,
        attack_amount = attack_amount,
        tick = hero_ticks_by_player[player_id],
    })
end

local function apply_tower_tick(player_id)
    local amount = M.value(player_id, "tower_attack_per_second")
    if amount <= 0 then return end
    tower_ticks_by_player[player_id] = (tower_ticks_by_player[player_id] or 0) + 1
    tower_tick_attack_by_player[player_id] =
        (tower_tick_attack_by_player[player_id] or 0) + amount
    event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
        player_id = player_id,
        reason = "star_blessing_tower_attack_per_second",
        amount = amount,
        tick = tower_ticks_by_player[player_id],
    })
end

local function heal_unit(unit, amount)
    if amount <= 0 or not valid_entity(unit) then return false end
    if unit.IsAlive and not unit:IsAlive() then return false end
    if type(unit.GetHealth) ~= "function"
        or type(unit.GetMaxHealth) ~= "function"
        or type(unit.SetHealth) ~= "function" then
        return false
    end
    local ok_health, health = pcall(unit.GetHealth, unit)
    local ok_max, maximum = pcall(unit.GetMaxHealth, unit)
    if not ok_health or not ok_max then return false end
    health = tonumber(health) or 0
    maximum = tonumber(maximum) or 0
    if maximum <= 0 or health >= maximum then return false end
    pcall(unit.SetHealth, unit, math.min(maximum, health + amount))
    return true
end

local function apply_health_regen_tick(player_id)
    local hero_amount = math.max(0,
        M.value(player_id, "health_regen_per_second")
            + M.value(player_id, "hero_health_regen_per_second"))
    if hero_amount > 0 then
        heal_unit(player_unit(player_id), hero_amount)
    end
    local tower_amount = math.max(0,
        M.value(player_id, "health_regen_per_second")
            + M.value(player_id, "tower_health_regen_per_second"))
    if tower_amount <= 0 or not Entities
        or type(Entities.FindAllByClassname) ~= "function" then return end
    for _, class_name in ipairs({ "npc_dota_creature", "npc_dota_building" }) do
        for _, unit in ipairs(Entities:FindAllByClassname(class_name) or {}) do
            if valid_entity(unit)
                and tonumber(unit.survival_player_id) == tonumber(player_id)
                and tostring(unit.survival_building_id or "") == "arrow_tower" then
                heal_unit(unit, tower_amount)
            end
        end
    end
end

local function on_damage(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or not payload.owner_hero
        or payload.attacker ~= payload.owner_hero then return end
    local attack_growth = M.value(player_id, "hero_damage_attack_growth")
    local attribute_growth = M.value(player_id, "hero_attributes_per_damage")
    if attack_growth > 0 then
        hero_damage_attack_bonus_by_player[player_id] =
            (hero_damage_attack_bonus_by_player[player_id] or 0) + attack_growth
    end
    if attribute_growth > 0 then
        hero_growth_attributes_by_player[player_id] =
            (hero_growth_attributes_by_player[player_id] or 0) + attribute_growth
    end
    local wood = M.value(player_id, "hero_damage_wood_flat")
    wood = wood * (1 + M.value(player_id, "hero_damage_wood_bonus_pct") / 100)
    local gold = M.value(player_id, "hero_damage_gold_flat")
    if wood ~= 0 or gold ~= 0 then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            player_id = player_id,
            wood = wood,
            gold = gold,
            reason = "gameplay_stats_hero_damage_resource",
        })
    end
    if attack_growth > 0 or attribute_growth > 0 then
        event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
            player_id = player_id,
            reason = "gameplay_stats_hero_damage_growth",
        })
    end
end

local function shared_value(effect_key)
    local total = 0
    for _, values in pairs(totals_by_player) do
        total = total + (tonumber(values[effect_key]) or 0)
    end
    return total
end

local function apply_enemy_initial_armor(unit, confirmed_monster)
    if not valid_entity(unit) or not (confirmed_monster == true
        or unit.survival_is_wave_monster == true
        or unit.survival_is_challenge_monster == true) then return end
    local reduction = math.max(0, shared_value("enemy_initial_armor_reduction"))
    local previous_armor = nil
    local next_armor = nil
    if tonumber(unit.survival_war3_armor) ~= nil then
        previous_armor = tonumber(unit.survival_effective_war3_armor)
            or tonumber(unit.survival_war3_armor) or 0
        unit.survival_gameplay_base_war3_armor =
            tonumber(unit.survival_gameplay_base_war3_armor)
                or tonumber(unit.survival_war3_armor) or 0
        local value = unit.survival_gameplay_base_war3_armor - reduction
        unit.survival_war3_armor = value
        unit.survival_effective_war3_armor = armor_balance.effective_war3_armor(
            value,
            unit.survival_war3_armor_reduction,
            unit.survival_minimum_war3_armor,
            unit.survival_poison_cloud_armor_reduction_pct
        )
        unit.survival_armor = value
        next_armor = unit.survival_effective_war3_armor
    elseif unit.GetPhysicalArmorBaseValue and unit.SetPhysicalArmorBaseValue then
        unit.survival_gameplay_base_armor =
            tonumber(unit.survival_gameplay_base_armor)
                or tonumber(unit:GetPhysicalArmorBaseValue()) or 0
        previous_armor = tonumber(unit:GetPhysicalArmorBaseValue()) or 0
        next_armor = unit.survival_gameplay_base_armor - reduction
        unit:SetPhysicalArmorBaseValue(next_armor)
    end
    if previous_armor ~= nil and next_armor ~= nil
        and math.abs(previous_armor - next_armor) > 0.0001
        and type(unit.entindex) == "function" then
        event_bus.emit(events.UNIT_COMBAT_STATS_CHANGED, {
            entindex = unit:entindex(),
            unit = unit,
            reason = "enemy_initial_armor_reduction",
            armor = next_armor,
        })
    end
end

refresh_existing_enemy_armor = function()
    if not Entities or type(Entities.FindAllByClassname) ~= "function" then return end
    for _, class_name in ipairs({ "npc_dota_creature", "npc_dota_building" }) do
        for _, unit in ipairs(Entities:FindAllByClassname(class_name) or {}) do
            local enemy = false
            if unit and type(unit.GetTeamNumber) == "function" then
                local ok, team = pcall(unit.GetTeamNumber, unit)
                enemy = ok and team == (rawget(_G, "DOTA_TEAM_BADGUYS") or 3)
            end
            apply_enemy_initial_armor(unit, enemy)
        end
    end
end

local function apply_wall_tick(player_id)
    local health = M.value(player_id, "wall_health_per_second")
    local armor = M.value(player_id, "wall_armor_per_second")
    if health <= 0 and armor <= 0 then return end
    wall_ticks_by_player[player_id] = (wall_ticks_by_player[player_id] or 0) + 1
    wall_tick_health_by_player[player_id] =
        (wall_tick_health_by_player[player_id] or 0) + math.max(0, health)
    wall_tick_armor_by_player[player_id] =
        (wall_tick_armor_by_player[player_id] or 0) + math.max(0, armor)
    event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
        player_id = player_id,
        reason = "gameplay_stats_wall_growth_per_second",
        tick = wall_ticks_by_player[player_id],
    })
end

local function on_hero_attack(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or payload.is_multishot_secondary == true then return end
    local attack_growth = M.value(player_id, "hero_basic_attack_growth")
    local attribute_growth = M.value(player_id, "hero_attribute_growth")
    attribute_growth = attribute_growth * (1
        + M.value(player_id, "hero_attack_attribute_efficiency_pct") / 100)
    if attack_growth > 0 then
        hero_basic_attack_bonus_by_player[player_id] =
            (hero_basic_attack_bonus_by_player[player_id] or 0) + attack_growth
    end
    if attribute_growth > 0 then
        hero_growth_attributes_by_player[player_id] =
            (hero_growth_attributes_by_player[player_id] or 0) + attribute_growth
    end
    local wood = M.value(player_id, "hero_attack_wood_flat")
    local gold = M.value(player_id, "hero_attack_gold_flat")
    if wood ~= 0 or gold ~= 0 then
        event_bus.request(events.RESOURCE_ADD_REQUEST, {
            player_id = player_id,
            wood = wood,
            gold = gold,
            reason = "gameplay_stats_hero_attack_resource",
        })
    end
    if attack_growth > 0 or attribute_growth > 0 then
        event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
            player_id = player_id,
            reason = "gameplay_stats_hero_attack_growth",
        })
    end
end

local function on_tower_attack(payload)
    local tower = payload and payload.tower
    local player_id = tower and tonumber(tower.survival_player_id)
    if player_id == nil then return end
    local damage_growth = M.value(player_id, "tower_damage_attack_growth")
    local attack_growth = M.value(player_id, "tower_basic_attack_growth")
    if damage_growth > 0 then
        tower_damage_bonus_by_player[player_id] =
            (tower_damage_bonus_by_player[player_id] or 0) + damage_growth
    end
    if attack_growth > 0 then
        tower_basic_attack_bonus_by_player[player_id] =
            (tower_basic_attack_bonus_by_player[player_id] or 0) + attack_growth
    end
    local reduction = armor_balance.from_war3_linear(
        M.value(player_id, "tower_attack_armor_reduction")
            + M.value(player_id, "global_attack_armor_reduction")
    )
    local target = payload.target
    if reduction > 0 and target and not target:IsNull() then
        target:AddNewModifier(tower, nil, "modifier_research_armor_reduction", {
            armor_reduction_per_attack = reduction,
        })
    end
    if damage_growth > 0 or attack_growth > 0 then
        event_bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
            player_id = player_id,
            reason = "gameplay_stats_tower_attack_growth",
        })
    end
end

local function get(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    local totals = copy(totals_by_player[player_id])
    local isolated_field = test_isolated_field_by_player[player_id]
    if not isolated_field then
        totals.team_hero_wall_armor_bonus = shared_value(
            "team_hero_wall_armor_bonus"
        )
        totals.enemy_initial_armor_reduction = shared_value(
            "enemy_initial_armor_reduction"
        )
    end
    totals.hero_all_attributes_flat = (totals.hero_all_attributes_flat or 0)
        + (totals.hero_initial_attributes or 0)
        + (hero_tick_attributes_by_player[player_id] or 0)
        + (hero_growth_attributes_by_player[player_id] or 0)
    totals.hero_attack_flat = (totals.hero_attack_flat or 0)
        + (totals.hero_initial_attack or 0)
        + (hero_damage_attack_bonus_by_player[player_id] or 0)
        + (hero_basic_attack_bonus_by_player[player_id] or 0)
        + (hero_tick_attack_by_player[player_id] or 0)
    totals.tower_attack_flat = (totals.tower_attack_flat or 0)
        + (tower_tick_attack_by_player[player_id] or 0)
        + (tower_damage_bonus_by_player[player_id] or 0)
        + (tower_basic_attack_bonus_by_player[player_id] or 0)
    totals.wall_health_growth_flat = wall_tick_health_by_player[player_id] or 0
    totals.wall_armor_growth_flat = wall_tick_armor_by_player[player_id] or 0
    return {
        ok = true,
        totals = totals,
        test_isolation = isolated_field ~= nil,
        isolated_field_id = isolated_field,
    }
end

function M.value(player_id, effect_key)
    return tonumber((totals_by_player[tonumber(player_id)] or {})[effect_key]) or 0
end

function M.set_test_isolation(player_id, field_id, defer_refresh)
    player_id = tonumber(player_id)
    field_id = tostring(field_id or "")
    if player_id == nil or player_id < 0 or field_id == "" then
        return false, "test_isolation_invalid"
    end
    test_isolated_field_by_player[player_id] = field_id
    hero_ticks_by_player[player_id] = 0
    tower_ticks_by_player[player_id] = 0
    hero_tick_attributes_by_player[player_id] = 0
    hero_tick_attack_by_player[player_id] = 0
    tower_tick_attack_by_player[player_id] = 0
    tower_damage_bonus_by_player[player_id] = 0
    hero_damage_attack_bonus_by_player[player_id] = 0
    hero_basic_attack_bonus_by_player[player_id] = 0
    hero_growth_attributes_by_player[player_id] = 0
    tower_basic_attack_bonus_by_player[player_id] = 0
    wall_ticks_by_player[player_id] = 0
    wall_tick_health_by_player[player_id] = 0
    wall_tick_armor_by_player[player_id] = 0
    if defer_refresh ~= true then
        refresh({ player_id = player_id, reason = "gameplay_stats_test_isolation" })
    end
    return true
end

function M.clear_test_isolation(player_id, defer_refresh)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 then
        return false, "test_isolation_invalid"
    end
    test_isolated_field_by_player[player_id] = nil
    if defer_refresh ~= true then
        refresh({ player_id = player_id, reason = "gameplay_stats_test_reset" })
    end
    return true
end

function M.init()
    totals_by_player = {}
    hero_ticks_by_player = {}
    tower_ticks_by_player = {}
    hero_tick_attributes_by_player = {}
    hero_tick_attack_by_player = {}
    tower_tick_attack_by_player = {}
    tower_damage_bonus_by_player = {}
    hero_damage_attack_bonus_by_player = {}
    hero_basic_attack_bonus_by_player = {}
    hero_growth_attributes_by_player = {}
    tower_basic_attack_bonus_by_player = {}
    wall_ticks_by_player = {}
    wall_tick_health_by_player = {}
    wall_tick_armor_by_player = {}
    test_isolated_field_by_player = {}
    event_bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, get)
    event_bus.subscribe(events.PLAYER_PROFILE_CHANGED, refresh)
    event_bus.subscribe(events.COMBAT_DAMAGE_RESOLVED, on_damage)
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_hero_attack)
    event_bus.subscribe(events.TOWER_ATTACK_LANDED, on_tower_attack)
    event_bus.subscribe(events.MONSTER_SPAWNED, function(payload)
        apply_enemy_initial_armor(
            payload and (payload.unit or payload.monster),
            true
        )
    end)
    scheduler.every(1, function()
        for player_id in pairs(totals_by_player) do
            apply_hero_tick(player_id)
            apply_tower_tick(player_id)
            apply_wall_tick(player_id)
            apply_health_regen_tick(player_id)
        end
        return true
    end, "star_blessing_effect_ticks")
end

return M
