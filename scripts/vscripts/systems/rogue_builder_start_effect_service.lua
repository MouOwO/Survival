local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local effect_state = require("systems/rogue_effect_state_service")

local M = {}
local subscriptions = {}
local active_by_player = {}

local function team_for(player_id)
    return PlayerResource:GetTeam(player_id)
end

local function wave_state()
    return event_bus.request(events.WAVE_STATE_GET_REQUEST, {}) or {}
end

local function difficulty_value()
    return tonumber(tostring(wave_state().difficulty_id or ""):match("(%d+)$")) or 1
end

local function add_resource(player_id, values, reason)
    values = values or {}
    local result = event_bus.request(events.RESOURCE_ADD_REQUEST, {
        team = team_for(player_id),
        wood = tonumber(values.wood) or 0,
        gold = tonumber(values.gold) or 0,
        max_population = tonumber(values.max_population) or 0,
        reason = reason,
    })
    return result and result.ok == true, result and result.error
end

local function add_technology(player_id, effects, card_id)
    local result = event_bus.request(events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST, {
        player_id = player_id,
        effects = effects,
        reason = "rogue_reward:" .. tostring(card_id),
    })
    return result and result.ok == true, result and result.error
end

local function remember(instance)
    local player = active_by_player[instance.player_id] or {}
    active_by_player[instance.player_id] = player
    player[instance.card_id] = instance
end

local function schedule_resource(instance, interval, values)
    local task_id = "builder_rogue:" .. instance.effect_instance_id
    instance.builder_task_id = task_id
    scheduler.every(interval, function()
        if active_by_player[instance.player_id]
            and active_by_player[instance.player_id][instance.card_id] == instance then
            add_resource(instance.player_id, values,
                "rogue_reward:" .. instance.card_id)
            return interval
        end
        return false
    end, task_id)
end

local function owner_player_id(unit)
    return require("systems/player_context_service").owner_player_id(unit)
end

local function on_wave_changed(payload)
    local reason = tostring(payload and payload.reason or "")
    if reason ~= "wave_started" and reason ~= "dev_wave_started"
        and reason ~= "early_final_started" then return end
    local wave = math.max(0, math.floor(tonumber(payload.current_wave) or 0))
    if wave <= 0 then return end
    for player_id, cards in pairs(active_by_player) do
        if cards.wealthy_start and cards.wealthy_start.last_paid_wave ~= wave then
            cards.wealthy_start.last_paid_wave = wave
            add_resource(player_id, {
                gold = wave * effect_state.numeric(player_id, "builder_gold_per_wave"),
            }, "rogue_reward:wealthy_start")
        end
    end
end

local function on_entity_killed(payload)
    local victim = payload and payload.victim
    if not victim or victim:IsNull()
        or (victim.survival_is_wave_monster ~= true
            and victim.survival_is_challenge_monster ~= true) then return end
    local player_id = tonumber(payload.player_id) or owner_player_id(payload.attacker)
    if player_id == nil then return end
    local per_wave = effect_state.numeric(player_id, "builder_kill_wood_per_wave")
    if per_wave <= 0 then return end
    local wave = math.max(0, tonumber(wave_state().current_wave) or 0)
    add_resource(player_id, { wood = per_wave * wave },
        "rogue_reward:woodcutting_bounty")
end

local function on_tower_attack_landed(payload)
    local tower = payload and (payload.tower or payload.attacker or payload.unit)
    local player_id = owner_player_id(tower)
    if player_id == nil then return end
    local amount = effect_state.numeric(player_id, "builder_tower_attack_per_hit")
    if amount <= 0 then return end
    local modifier = tower:FindModifierByName("modifier_rogue_sharp_volley_growth")
    if not modifier then
        tower:AddNewModifier(tower, nil, "modifier_rogue_sharp_volley_growth", {
            value = amount,
        })
    elseif modifier.AddGrowth then
        modifier:AddGrowth(amount)
    end
end

local handlers = {}

handlers.wall_recovery = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_wall_health_per_second",
        instance.params.health_per_second)
    effect_state.add_numeric(instance.player_id, "builder_wall_armor_per_interval",
        instance.params.armor_per_interval)
    local health = tonumber(instance.params.health_per_second) or 0
    local armor = tonumber(instance.params.armor_per_interval) or 0
    local armor_interval = math.max(1,
        tonumber(instance.params.armor_interval_seconds) or 60)
    local elapsed = 0
    local task_id = "builder_rogue:" .. instance.effect_instance_id
    instance.builder_task_id = task_id
    scheduler.every(1, function()
        local response = event_bus.request(events.BUILDING_LIST_REQUEST, {
            player_id = instance.player_id,
        }) or {}
        local wall = nil
        for _, building in ipairs(response.buildings or response) do
            if building.building_id == "wall" then wall = building.unit break end
        end
        if wall and not wall:IsNull() and wall:IsAlive() then
            local missing = math.max(0, wall:GetMaxHealth() - wall:GetHealth())
            if missing > 0 then wall:Heal(math.min(health, missing), nil) end
            elapsed = elapsed + 1
            if elapsed >= armor_interval then
                elapsed = 0
                add_technology(instance.player_id, {{
                    effect_type = "wall_armor_flat", value = armor,
                }}, instance.card_id)
            end
        end
        return 1
    end, task_id)
    return true
end

handlers.wealthy_start = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_gold_per_wave",
        instance.params.gold_per_wave)
    return true
end

handlers.sharp_volley = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_tower_attack_per_hit",
        instance.params.attack_per_hit)
    return add_technology(instance.player_id, {{
        effect_type = "tower_attack_speed_bonus_pct",
        value = instance.params.attack_speed_pct,
    }}, instance.card_id)
end

handlers.lumberjack_assault = function(instance)
    return add_technology(instance.player_id, {{
        effect_type = "lumberjack_attack_speed_pct",
        value = instance.params.attack_speed_pct,
    }}, instance.card_id)
end

handlers.fortified_defense = function(instance)
    effect_state.add_wall_health_flat(instance.player_id, instance.params.health_flat)
    effect_state.add_numeric(instance.player_id, "builder_wall_damage_reduction_pct",
        instance.params.damage_reduction_pct)
    return add_technology(instance.player_id, {{
        effect_type = "wall_armor_flat", value = instance.params.armor_flat,
    }}, instance.card_id)
end

handlers.infrastructure_maniac_start = function(instance)
    return effect_state.add_effect(instance.player_id, "builder_main_city_wood_refund")
end

handlers.precision_lumber = function(instance)
    return add_technology(instance.player_id, {{
        effect_type = "lumberjack_wood_per_hit", value = instance.params.wood_per_hit,
    }}, instance.card_id)
end

handlers.peaceful_labor = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_peaceful_wood_per_hit",
        instance.params.wood_per_hit)
    return true
end

handlers.woodcutting_bounty = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_kill_wood_per_wave",
        instance.params.wood_per_wave)
    return true
end

handlers.instant_wood = function(instance)
    return add_resource(instance.player_id, {
        wood = difficulty_value() * (tonumber(instance.params.wood_per_difficulty) or 100),
    }, "rogue_reward:" .. instance.card_id)
end

handlers.gold_mining_secret = function(instance)
    return add_technology(instance.player_id, {{
        effect_type = "gold_mine_income_pct", value = instance.params.income_bonus_pct,
    }}, instance.card_id)
end

handlers.hero_descent = function(instance)
    return effect_state.add_numeric(instance.player_id, "builder_free_hero_altar", 1)
end

handlers.population_expansion = function(instance)
    return add_resource(instance.player_id, {
        max_population = instance.params.max_population,
    }, "rogue_reward:" .. instance.card_id)
end

handlers.natures_gift = function(instance)
    schedule_resource(instance, 1, { wood = instance.params.wood_per_second })
    return true
end

handlers.emergency_reinforcement = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_wall_low_health_threshold_pct",
        instance.params.health_threshold_pct)
    effect_state.add_numeric(instance.player_id, "builder_wall_low_health_reduction_pct",
        instance.params.damage_reduction_pct)
    return true
end

handlers.wind_strategy = function(instance)
    return add_technology(instance.player_id, {
        { effect_type = "hero_attack_speed_pct", value = instance.params.attack_speed_pct },
        { effect_type = "hero_attack_interval_flat", value = instance.params.attack_interval_flat },
    }, instance.card_id)
end

handlers.allround_tempering = function(instance)
    return add_technology(instance.player_id, {
        { effect_type = "hero_attack_speed_pct", value = instance.params.attack_speed_pct },
        { effect_type = "hero_all_attributes_flat", value = instance.params.all_attributes_flat },
    }, instance.card_id)
end

handlers.heavy_hand = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_super_lumberjack_crit_pct",
        instance.params.critical_chance_pct)
    return true
end

handlers.first_to_strike = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_hero_wood_bonus_pct",
        instance.params.wood_bonus_pct)
    return true
end

handlers.endless_rebirth = function(instance)
    effect_state.add_numeric(instance.player_id, "builder_rebirth_boss_damage_pct",
        instance.params.damage_bonus_pct)
    return true
end

handlers.long_range_volley = function(instance)
    return add_technology(instance.player_id, {
        { effect_type = "tower_attack_range_flat", value = instance.params.attack_range_flat },
        { effect_type = "tower_attack_flat", value = instance.params.attack_flat },
    }, instance.card_id)
end

function M.apply(instance)
    if instance.reward_type and instance.reward_type ~= "builder_start" then
        return false, "builder_reward_type_invalid"
    end
    local handler = handlers[instance.card_id]
    if not handler then return false, "builder_card_handler_missing" end
    local ok, error_code = handler(instance)
    if ok and instance.effect.execution_mode ~= "instant_transaction" then
        remember(instance)
    end
    return ok, error_code
end

function M.remove(instance)
    if instance.builder_task_id then scheduler.cancel(instance.builder_task_id) end
    local player = active_by_player[instance.player_id]
    if player and player[instance.card_id] == instance then player[instance.card_id] = nil end
end

function M.init()
    for _, subscription in ipairs(subscriptions) do event_bus.unsubscribe(subscription) end
    subscriptions = {}
    active_by_player = {}
    subscriptions[#subscriptions + 1] = event_bus.subscribe(events.WAVE_CHANGED,
        on_wave_changed)
    subscriptions[#subscriptions + 1] = event_bus.subscribe(events.ENGINE_ENTITY_KILLED,
        on_entity_killed)
    subscriptions[#subscriptions + 1] = event_bus.subscribe(events.TOWER_ATTACK_LANDED,
        on_tower_attack_landed)
end

return M