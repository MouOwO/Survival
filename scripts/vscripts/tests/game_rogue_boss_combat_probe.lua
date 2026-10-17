-- Explicit Workshop-only helpers. Requiring this module does not run a test,
-- register a command, reset player state, grant a card or modify existing units.
-- script require('tests/game_rogue_boss_combat_probe').run_native(0)
local M = {}
local json = require("core/json_encoder")
local owned, serial = {}, 0

local function valid(unit)
    return unit and unit.IsNull and not unit:IsNull()
end

local function get(unit, method, ...)
    if not valid(unit) or type(unit[method]) ~= "function" then return nil end
    local ok, value = pcall(unit[method], unit, ...)
    if not ok then return nil end
    if type(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
        return nil
    end
    if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
        return value
    end
end

local function emit(kind, value)
    print("[ROGUE_BOSS_NATIVE_" .. kind .. "] " .. json.encode(value))
end

-- Read-only engine event observer, attached only to an owned test target.
modifier_rogue_boss_hit_observer = class({})
function modifier_rogue_boss_hit_observer:IsHidden() return true end
function modifier_rogue_boss_hit_observer:IsPurgable() return false end
function modifier_rogue_boss_hit_observer:OnCreated(params)
    if not IsServer() then return end
    self.observed_attacker = tonumber(params.attacker_entindex)
    self.previous_health, self.hits = self:GetParent():GetHealth(), {}
end
function modifier_rogue_boss_hit_observer:DeclareFunctions() return { MODIFIER_EVENT_ON_TAKEDAMAGE } end
function modifier_rogue_boss_hit_observer:OnTakeDamage(params)
    if not IsServer() or params.unit ~= self:GetParent() then return end
    local health = self:GetParent():GetHealth()
    if valid(params.attacker) and params.attacker:entindex() == self.observed_attacker then
        self.hits[#self.hits + 1] = { category = params.damage_category,
            damage_type = params.damage_type, damage = params.damage,
            before_health = self.previous_health, after_health = health,
            health_loss = self.previous_health - health, record = params.record,
            native_attack = params.damage_category == DOTA_DAMAGE_CATEGORY_ATTACK
                or params.damage_category == nil and params.record ~= nil and not valid(params.inflictor),
            ability = valid(params.inflictor) and params.inflictor:GetAbilityName() or nil }
    end
    self.previous_health = health
end

function M.snapshot(unit)
    if not valid(unit) then return { status = "unavailable" } end
    local attacks_per_second = get(unit, "GetAttacksPerSecond", false)
    local seconds_per_attack = get(unit, "GetSecondsPerAttack", false)
    local result = { entindex = unit:entindex(), unit_name = get(unit, "GetUnitName"),
        player_id = unit.survival_player_id, building_id = unit.survival_building_id,
        tower_stage = unit.survival_tower_stage_id, level = unit.survival_level,
        health = get(unit, "GetHealth"), max_health = get(unit, "GetMaxHealth"),
        native_base_min = get(unit, "GetBaseDamageMin"),
        native_base_max = get(unit, "GetBaseDamageMax"),
        native_average_attack = get(unit, "GetAverageTrueAttackDamage", nil),
        native_attack_speed = get(unit, "GetAttackSpeed", false),
        native_attacks_per_second = attacks_per_second,
        native_base_attack_time = get(unit, "GetBaseAttackTime", false),
        native_seconds_per_attack = seconds_per_attack or (attacks_per_second
            and attacks_per_second > 0 and 1 / attacks_per_second or nil),
        native_seconds_per_attack_source = seconds_per_attack and "GetSecondsPerAttack(false)"
            or attacks_per_second and "1 / GetAttacksPerSecond(false)" or "unavailable",
        native_attack_range = get(unit, "Script_GetAttackRange"),
        native_armor = get(unit, "GetPhysicalArmorValue", false),
        logical_armor = unit.survival_effective_war3_armor,
        attack_scale = tonumber(unit.survival_endless_attack_scale) or 1,
        health_scale = tonumber(unit.survival_endless_health_scale) or 1,
        modifiers = {} }
    local ok, modifiers = pcall(unit.FindAllModifiers, unit)
    if ok then
        for _, modifier in ipairs(modifiers or {}) do
            local name_ok, name = pcall(modifier.GetName, modifier)
            if name_ok and tostring(name):find("rogue", 1, true) then
                local item = { name = name }
                for _, callback in ipairs({ "GetModifierBaseDamageOutgoing_Percentage",
                    "GetModifierPreAttack_BonusDamage", "GetModifierAttackSpeedPercentage" }) do
                    if type(modifier[callback]) == "function" then
                        local value_ok, value = pcall(modifier[callback], modifier)
                        if value_ok and type(value) == "number" then item[callback] = value end
                    end
                end
                result.modifiers[#result.modifiers + 1] = item
            end
        end
    end
    return result
end

-- This is observation only. The caller must grant through the production UI or
-- runtime first; a snapshot with no card cannot be counted as a successful card.
function M.capture(player_id)
    assert(IsServer() and IsInToolsMode(), "Workshop server required")
    player_id = tonumber(player_id) or 0
    local bus, events = require("core/event_bus"), require("core/events")
    local state = require("systems/rogue_effect_state_service")
    local result = { player_id = player_id, game_time = GameRules:GetGameTime(),
        runtime = {},
        numeric = {}, towers = {}, workers = {}, enemies = {} }
    for _, instance in ipairs(require("systems/rogue_effect_runtime_service").snapshot(player_id)) do
        result.runtime[#result.runtime + 1] = {
            card_id = instance.card_id, effect_instance_id = instance.effect_instance_id,
            effect_type = instance.effect and instance.effect.effect_type,
            phase_id = instance.phase_id, status = instance.status,
            target_wave_number = instance.target_wave_number,
            target_member_role = instance.target_member_role,
            expires_at = instance.expires_at, snapshot_bonus = instance.snapshot_bonus,
            completed_reason = instance.completed_reason,
        }
    end
    for _, key in ipairs({ "unit_attack_bonus_pct", "tower_hero_attack_projection_pct",
        "hero_lifesteal_pct", "physical_armor_ignore_pct" }) do
        result.numeric[key] = state.numeric(player_id, key)
    end
    result.network_snapshot_pct = state.tower_projection(player_id, "max_tower_count_attack_bonus_pct")
    result.wall_health_flat = state.wall_health_flat(player_id)
    local buildings = bus.request(events.BUILDING_LIST_REQUEST, { player_id = player_id }) or {}
    for _, building in ipairs(buildings.buildings or {}) do
        local snapshot = M.snapshot(building.unit)
        if building.building_id == "wall" then
            result.wall = snapshot
            result.wall_damage_cap_pct = state.wall_damage_cap(building.unit)
        elseif building.building_id == "arrow_tower" then
            result.towers[#result.towers + 1] = snapshot
        end
    end
    for _, worker in ipairs(bus.request(events.WORKER_LIST_REQUEST, { player_id = player_id }) or {}) do
        result.workers[#result.workers + 1] = M.snapshot(worker.unit)
    end
    local hero = bus.request(events.HERO_SUMMON_GET_REQUEST, { player_id = player_id }) or {}
    result.hero = M.snapshot(hero.unit or hero.hero)
    for _, unit in ipairs(Entities:FindAllByClassname("npc_dota_creature") or {}) do
        if valid(unit) and (unit.survival_is_wave_monster or unit.survival_is_challenge_monster
            or unit.survival_is_training_dummy) then
            result.enemies[#result.enemies + 1] = M.snapshot(unit)
        end
    end
    emit("CAPTURE", result)
    return result
end

-- Real attack event and real health difference; no fabricated GetHealth,
-- GetAverageTrueAttackDamage or manually invoked Modifier callbacks are used.
-- Ownership remains with the caller. Never use an existing player's target if
-- losing this health would interfere with their game.
function M.attack_sample(attacker, target, callback, options)
    assert(valid(attacker) and valid(target), "two live native entities required")
    options = options or {}
    local before = { attacker = M.snapshot(attacker), target = M.snapshot(target) }
    local hit_observer
    if options.observe_native_hits == true and target.survival_rogue_native_probe then
        LinkLuaModifier("modifier_rogue_boss_hit_observer", "tests/game_rogue_boss_combat_probe", LUA_MODIFIER_MOTION_NONE)
        hit_observer = target:AddNewModifier(attacker, nil, "modifier_rogue_boss_hit_observer",
            { attacker_entindex = attacker:entindex() })
    end
    local bus, events = require("core/event_bus"), require("core/events")
    local critical, filtered_hits, damage_requests, filter_transactions = nil, {}, {}, {}
    local critical_subscription = bus.subscribe(events.HERO_FINAL_CRITICAL_ATTACK_DAMAGE, function(payload)
        if payload.attacker ~= attacker or payload.target ~= target then return end
        local projection = _G.modifier_weapon_stat_projection
        local is_critical, multiplier = false, nil
        if projection and projection.PeekCriticalAttackRecord then
            is_critical, multiplier = projection.PeekCriticalAttackRecord(attacker, payload.record)
        end
        critical = { event = "HERO_FINAL_CRITICAL_ATTACK_DAMAGE", record = payload.record,
            final_damage = payload.final_damage, native_record_critical = is_critical,
            multiplier = is_critical and multiplier or nil }
    end)
    local tower_subscription = bus.subscribe(events.TOWER_ATTACK_LANDED, function(payload)
        if payload.tower ~= attacker or payload.target ~= target or payload.critical ~= true then return end
        critical = { event = "TOWER_ATTACK_LANDED", native_record_critical = true,
            multiplier = tonumber(payload.critical_multiplier), source = payload.critical_source }
    end)
    local damage_subscription = bus.subscribe(events.COMBAT_DAMAGE_RESOLVED, function(payload)
        if tonumber(payload.attacker_entindex) == attacker:entindex()
            and tonumber(payload.victim_entindex) == target:entindex() then
            filtered_hits[#filtered_hits + 1] = { transaction_id = payload.transaction_id,
                final_damage = payload.final_damage, post_multiplier = payload.post_multiplier }
        end
    end)
    local combat_events = require("combat/combat_events")
    local request_subscription = bus.subscribe(combat_events.DAMAGE_REQUESTED, function(payload)
        if payload.attacker ~= attacker or payload.victim ~= target then return end
        damage_requests[#damage_requests + 1] = { base_damage = payload.base_damage,
            source_kind = payload.source_kind, tags = payload.tags, damage_type = payload.damage_type,
            physical_armor_ignore_pct = payload.physical_armor_ignore_pct, can_crit = payload.can_crit }
    end)
    local filter_subscription = bus.subscribe(combat_events.DAMAGE_FILTERED, function(payload)
        if tonumber(payload.attacker_entindex) == attacker:entindex()
            and tonumber(payload.victim_entindex) == target:entindex() then
            filter_transactions[#filter_transactions + 1] = { transaction_id = payload.transaction_id,
                final_damage = payload.final_damage, engine_damage = payload.engine_damage,
                post_multiplier = payload.post_multiplier }
        end
    end)
    attacker:PerformAttack(target, false, options.process_procs ~= false, true, true, false, false, true)
    serial = serial + 1
    GameRules:GetGameModeEntity():SetContextThink("rogue_boss_native_sample_" .. serial, function()
        bus.unsubscribe(critical_subscription); bus.unsubscribe(tower_subscription); bus.unsubscribe(damage_subscription)
        bus.unsubscribe(request_subscription); bus.unsubscribe(filter_subscription)
        local after = { attacker = M.snapshot(attacker), target = M.snapshot(target) }
        local actual_damage_events = hit_observer and hit_observer.hits or nil
        if hit_observer and hit_observer.Destroy then hit_observer:Destroy() end
        local result = { before = before, after = after,
            target_health_loss = before.target.health and after.target.health
                and before.target.health - after.target.health or nil,
            attacker_health_gain = before.attacker.health and after.attacker.health
                and after.attacker.health - before.attacker.health or nil,
            native_event = true, simulated_engine = false,
            critical_observation = critical, filtered_hits = filtered_hits,
            damage_requests = damage_requests, filter_transactions = filter_transactions,
            actual_damage_events = actual_damage_events }
        emit("ATTACK", result)
        if callback then callback(result) end
        return nil
    end, tonumber(options.delay) or 0.10)
    return { status = "scheduled", before = before }
end

local function spawn(position, team, unit_name)
    local unit = CreateUnitByName(unit_name or "npc_dota_creep_badguys_melee", position, false, nil, nil, team)
    assert(valid(unit), "native creep creation failed")
    owned[unit:entindex()] = unit
    unit.survival_rogue_native_probe = true
    unit:SetBaseMaxHealth(100000)
    unit:SetMaxHealth(100000)
    unit:SetHealth(100000)
    unit:SetBaseDamageMin(100)
    unit:SetBaseDamageMax(100)
    unit:SetPhysicalArmorBaseValue(0)
    unit:SetBaseAttackTime(2)
    unit:SetAcquisitionRange(0)
    if unit.SetIdleAcquire then unit:SetIdleAcquire(false) end
    if unit.SetBaseHealthRegen then unit:SetBaseHealthRegen(0) end
    unit:Stop()
    return unit
end

function M.cleanup()
    for index, unit in pairs(owned) do
        if valid(unit) and unit.survival_rogue_native_probe then UTIL_Remove(unit) end
        owned[index] = nil
    end
end

-- Exercises the native engine boundary common to Boss cards using their exact
-- production Modifier classes. This does not claim to replace formal grant,
-- ownership, phase, route or tooltip validation, which capture/full tests cover.
function M.run_native(player_id, options)
    assert(IsServer() and IsInToolsMode(), "Workshop server required")
    assert(not next(owned), "previous probe active; call cleanup before another run")
    options = options or {}
    local hero = PlayerResource:GetSelectedHeroEntity(tonumber(player_id) or 0)
    local position = options.position or (valid(hero) and hero:GetAbsOrigin() + Vector(0, 320, 0))
    assert(position, "provide a native Vector position or a player hero")
    LinkLuaModifier("modifier_rogue_base_tower_attack", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_tower_growth", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_tower_attack_projection", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_weakening_attack", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_enemy_attack_speed", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_lumberjack_attack_speed", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_training_attack", "modifiers/modifier_rogue_combat_effects", LUA_MODIFIER_MOTION_NONE)
    local attacker, target = spawn(position, DOTA_TEAM_GOODGUYS), spawn(position + Vector(100, 0, 0), DOTA_TEAM_BADGUYS)
    local cases = {
        { id = "native_control", damage = 100 },
        { id = "recruit_training", modifier = "modifier_rogue_base_tower_attack", kv = { value = 100 }, damage = 200 },
        { id = "tower_growth", modifier = "modifier_rogue_tower_growth", kv = { value = 10, stacks = 2 }, damage = 120 },
        { id = "gunpowder_splash", modifier = "modifier_rogue_tower_attack_projection", kv = { value = 30 }, damage = 130 },
        { id = "tower_network", modifier = "modifier_rogue_tower_attack_projection", kv = { value = 50 }, damage = 150 },
        { id = "weakening_orb", modifier = "modifier_rogue_weakening_attack", kv = { value = -50 }, damage = 50 },
        { id = "training_dummy", modifier = "modifier_rogue_training_attack", kv = { value = 100 }, damage = 200 },
        { id = "frozen_wall", modifier = "modifier_rogue_enemy_attack_speed", kv = { value = -15 }, speed_ratio = 0.85, damage = 100 },
        { id = "boss_promise", modifier = "modifier_rogue_lumberjack_attack_speed", kv = { value = 100 }, speed_ratio = 2, damage = 100 },
    }
    local results, index, checks, failures = {}, 0, 0, 0
    local speed_baseline = get(attacker, "GetAttackSpeed", false)
    local function check(result, field, actual, expected, tolerance)
        checks = checks + 1
        local pass = type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 1)
        result.assertions[#result.assertions + 1] = { field = field, actual = actual,
            expected = expected, status = pass and "pass" or "fail" }
        if not pass then failures = failures + 1 end
    end
    local step
    local function finish(error_message)
        M.cleanup()
        local result = { status = error_message and "error" or failures > 0 and "fail" or "pass",
            checks = checks, failures = failures, results = results,
            error = error_message, simulated_engine = false,
            scope = "native production modifiers and actual engine attacks; not formal grant lifecycle" }
        emit("RESULT", result)
        print("ROGUE_BOSS_NATIVE_DONE")
        if options.on_complete then options.on_complete(result) end
    end
    step = function()
        index = index + 1
        if index > #cases then finish(); return end
        for _, case in ipairs(cases) do
            if case.modifier then attacker:RemoveModifierByName(case.modifier) end
        end
        attacker.survival_rogue_dummy_attack_bonus = nil
        local case = cases[index]
        if case.modifier then attacker:AddNewModifier(attacker, nil, case.modifier, case.kv) end
        serial = serial + 1
        GameRules:GetGameModeEntity():SetContextThink("rogue_boss_native_case_" .. serial, function()
            local ok, message = xpcall(function()
                local result = { id = case.id, assertions = {}, native = M.snapshot(attacker) }
                -- Source 2 truncates this integer getter after floating point
                -- multiplication (100 * 1.3 can report 129). Real health loss
                -- below remains the authoritative damage assertion.
                check(result, "native_average_attack", result.native.native_average_attack, case.damage, 1)
                if case.speed_ratio then
                    check(result, "native_attack_speed_ratio", result.native.native_attack_speed
                        and result.native.native_attack_speed / speed_baseline, case.speed_ratio, 0.02)
                end
                M.attack_sample(attacker, target, function(sample)
                    check(result, "actual_health_loss", sample.target_health_loss, case.damage, 1)
                    results[#results + 1] = result
                    emit("CASE", result)
                    local next_ok, next_error = xpcall(step, debug.traceback)
                    if not next_ok then finish(next_error) end
                end)
            end, debug.traceback)
            if not ok then finish(message) end
            return nil
        end, 0.10)
    end
    local ok, message = xpcall(step, debug.traceback)
    if not ok then finish(message) end
    return { status = "scheduled", cases = #cases, attacker = attacker:entindex(), target = target:entindex() }
end

-- The observer records engine attack landings only. It never calls a production
-- attack callback or creates damage, and is attached only to this probe's unit.
modifier_rogue_boss_cadence_probe = class({})
function modifier_rogue_boss_cadence_probe:IsHidden() return true end
function modifier_rogue_boss_cadence_probe:IsPurgable() return false end
function modifier_rogue_boss_cadence_probe:DeclareFunctions()
    return { MODIFIER_EVENT_ON_ATTACK_LANDED }
end
function modifier_rogue_boss_cadence_probe:OnAttackLanded(params)
    if not IsServer() or not params or params.attacker ~= self:GetParent() then return end
    local probe = self:GetParent().survival_rogue_native_cadence
    if not probe or not valid(params.target) or params.target:entindex() ~= probe.target_index then return end
    probe.landings[#probe.landings + 1] = GameRules:GetGameTime()
    if #probe.landings >= probe.required_hits then self:GetParent():Stop() end
end

-- Actual autonomous attacks, respecting native cooldown and animation. BAT is
-- the same 0.4 seconds in all stages; no PerformAttack is used in this probe.
function M.run_cadence(player_id, options)
    assert(IsServer() and IsInToolsMode(), "Workshop server required")
    assert(not next(owned), "previous probe active; call cleanup before another run")
    options = options or {}
    local hero = PlayerResource:GetSelectedHeroEntity(tonumber(player_id) or 0)
    local position = options.position or (valid(hero) and hero:GetAbsOrigin() + Vector(0, 320, 0))
    assert(position, "provide a native Vector position or a player hero")
    LinkLuaModifier("modifier_rogue_enemy_attack_speed", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_lumberjack_attack_speed", "modifiers/modifier_rogue_reward_effects", LUA_MODIFIER_MOTION_NONE)
    LinkLuaModifier("modifier_rogue_boss_cadence_probe", "tests/game_rogue_boss_combat_probe", LUA_MODIFIER_MOTION_NONE)
    local attacker, target = spawn(position, DOTA_TEAM_GOODGUYS), spawn(position + Vector(60, 0, 0), DOTA_TEAM_BADGUYS)
    attacker:SetBaseAttackTime(0.4)
    attacker:AddNewModifier(attacker, nil, "modifier_rogue_boss_cadence_probe", {})
    local cases = {
        { id = "cadence_control", speed_ratio = 1 },
        { id = "frozen_wall", modifier = "modifier_rogue_enemy_attack_speed", value = -15, speed_ratio = 0.85 },
        { id = "boss_promise", modifier = "modifier_rogue_lumberjack_attack_speed", value = 100, speed_ratio = 2 },
    }
    local index, results, failures, baseline_mean, finished = 0, {}, 0, nil, false
    local function finish(error_message)
        if finished then return end
        finished = true
        M.cleanup()
        local result = { status = error_message and "error" or failures > 0 and "fail" or "pass",
            failures = failures, results = results, error = error_message,
            simulated_engine = false, measurement = "ON_ATTACK_LANDED engine timestamps",
            attack_delivery = "native ATTACK_TARGET order; normal cooldown and animation" }
        emit("CADENCE_RESULT", result)
        print("ROGUE_BOSS_NATIVE_CADENCE_DONE")
        if options.on_complete then options.on_complete(result) end
    end
    local step
    step = function()
        index = index + 1
        if index > #cases then finish(); return end
        attacker:Stop()
        attacker:RemoveModifierByName("modifier_rogue_enemy_attack_speed")
        attacker:RemoveModifierByName("modifier_rogue_lumberjack_attack_speed")
        local case = cases[index]
        if case.modifier then attacker:AddNewModifier(attacker, nil, case.modifier, { value = case.value }) end
        local probe = { target_index = target:entindex(), required_hits = 6, landings = {} }
        attacker.survival_rogue_native_cadence = probe
        serial = serial + 1
        local begun, started_at, native_snapshot = false, nil, nil
        GameRules:GetGameModeEntity():SetContextThink("rogue_boss_cadence_" .. serial, function()
            if finished then return nil end
            local again = 0.03
            local ok, message = xpcall(function()
                if not valid(attacker) or not valid(target) then error("cadence fixture removed") end
                if not begun then
                    begun, started_at, native_snapshot = true, GameRules:GetGameTime(), M.snapshot(attacker)
                    ExecuteOrderFromTable({ UnitIndex = attacker:entindex(), OrderType = DOTA_UNIT_ORDER_ATTACK_TARGET,
                        TargetIndex = target:entindex(), Queue = false })
                    return
                end
                if #probe.landings < probe.required_hits and GameRules:GetGameTime() - started_at < 8 then return end
                attacker:Stop()
                local intervals, total = {}, 0
                for hit = 2, #probe.landings do
                    local interval = probe.landings[hit] - probe.landings[hit - 1]
                    intervals[#intervals + 1], total = interval, total + interval
                end
                local mean = #intervals > 0 and total / #intervals or nil
                if index == 1 then baseline_mean = mean end
                local expected = baseline_mean and baseline_mean / case.speed_ratio or nil
                local tolerance = expected and math.max(0.04, expected * 0.12) or 0.04
                local pass = #probe.landings >= probe.required_hits and mean and expected
                    and math.abs(mean - expected) <= tolerance or false
                if not pass then failures = failures + 1 end
                local result = { id = case.id, status = pass and "pass" or "fail",
                    native = native_snapshot, required_hits = probe.required_hits,
                    actual_hits = #probe.landings, landings = probe.landings, intervals = intervals,
                    mean_interval = mean, expected_interval = expected, tolerance_seconds = tolerance,
                    actual_speed_ratio = mean and baseline_mean and baseline_mean / mean or nil,
                    expected_speed_ratio = case.speed_ratio }
                results[#results + 1] = result
                emit("CADENCE_CASE", result)
                again = nil
                step()
            end, debug.traceback)
            if not ok then finish(message); return nil end
            return again
        end, 0.10)
    end
    local ok, message = xpcall(step, debug.traceback)
    if not ok then finish(message) end
    return { status = "scheduled", stages = #cases, expected_duration_seconds = 7 }
end

local card_reports, card_sequence = {}, 0
local function local_gate(player_id, options)
    if not IsServer() or not IsInToolsMode() then return false, "single_player_Tools_server_required" end
    if not options or options.local_test ~= true then return false, "local_test_option_required" end
    local players = 0
    for id = 0, 63 do
        if PlayerResource:IsValidPlayerID(id) and PlayerResource:GetPlayer(id) then players = players + 1 end
    end
    if players ~= 1 or not PlayerResource:GetPlayer(player_id) then return false, "single_player_required" end
    return true
end

local function native_entity(value)
    if type(value) == "number" then return EntIndexToHScript(value) end
    return value
end

local function live_context(player_id, context)
    local result = {}
    for key, value in pairs(context or {}) do result[key] = native_entity(value) end
    local bus, events = require("core/event_bus"), require("core/events")
    local buildings = bus.request(events.BUILDING_LIST_REQUEST, { player_id = player_id }) or {}
    for _, building in ipairs(buildings.buildings or buildings) do
        if valid(building.unit) then
            local key = building.building_id == "arrow_tower" and "tower"
                or building.building_id == "wall" and "wall" or nil
            if key and not result[key] then result[key] = building.unit end
        end
    end
    local hero = bus.request(events.HERO_SUMMON_GET_REQUEST, { player_id = player_id }) or {}
    result.hero = result.hero or hero.unit or hero.hero
    for _, worker in ipairs(bus.request(events.WORKER_LIST_REQUEST, { player_id = player_id }) or {}) do
        if worker.worker_type ~= "repairer" and not result.worker then result.worker = worker.unit end
    end
    return result
end

-- Formal production debug offer followed by the same SELECT request as the UI.
-- A previous grant is reused only with explicit reuse_existing=true; the report
-- retains the original instance/grant IDs instead of pretending it was new.
function M.select_card(card_id, player_id, options)
    player_id = tonumber(player_id) or 0
    local allowed, error_code = local_gate(player_id, options)
    if not allowed then return { ok = false, error = error_code } end
    local runtime = require("systems/rogue_effect_runtime_service")
    local selected
    for _, instance in ipairs(runtime.snapshot(player_id)) do
        if instance.card_id == card_id and options.reuse_existing == true then
            local newer = tonumber(tostring(instance.effect_instance_id):match("(%d+)$")) or 0
            local previous = selected and tonumber(tostring(selected.effect_instance_id):match("(%d+)$")) or -1
            if not selected or instance.status == "active" and selected.status ~= "active"
                or instance.status == selected.status and newer > previous then selected = instance end
        end
    end
    if selected then
        return { ok = true, reused_existing = true, grant_id = selected.grant_id,
            effect_instance_id = selected.effect_instance_id, phase_id = selected.phase_id,
            status = selected.status, created_at = selected.created_at, expires_at = selected.expires_at,
            completed_reason = selected.completed_reason }
    end
    local cards = require("config/generated/rogue_reward_cards")
    local card = cards.by_id[card_id]
    if not card or card.enabled == false or card.type ~= "boss" and options.allow_builder ~= true then
        return { ok = false, error = "enabled_Boss_card_required" }
    end
    local ids = { card_id }
    for _, row in ipairs(cards.rows) do
        if row.enabled ~= false and row.type == card.type and row.card_id ~= card_id and #ids < 3 then
            ids[#ids + 1] = row.card_id
        end
    end
    local offer = require("systems/rogue_reward_service").debug_offer(player_id, ids)
    if not offer or not offer.ok then return offer or { ok = false, error = "debug_offer_unavailable" } end
    local bus, events = require("core/event_bus"), require("core/events")
    local result, why = bus.request(events.ROGUE_REWARD_SELECT_REQUEST,
        { player_id = player_id, card_id = card_id, token = offer.token, reward_type = card.type })
    result = result or { ok = false, error = why or "formal_selection_unavailable" }
    result.via, result.offer_token = "debug_offer_then_ROGUE_REWARD_SELECT", offer.token
    return result
end

function M.card_result(id) return card_reports[id] end

-- Read-only expectation for the native getter, distinct from attack delivery.
-- Actual Dota fusion samples show DAMAGEOUT/BASEDMGOUT projected on base damage
-- before PREATTACK_BONUS is added: the +800 flat delta is exactly +800 even
-- while the tower's native outgoing profile reports +5%.
function M.native_average_expected(base, base_pct, outgoing_pct, pre_attack_flat)
    return base * (1 + base_pct / 100) * (1 + outgoing_pct / 100) + pre_attack_flat
end

function M.native_frequency_expected(frequency, prior_total_ias, current_total_ias)
    return frequency * (100 + current_total_ias) / (100 + prior_total_ias)
end

local function attack_parts(unit)
    local pct, flat, outgoing = 0, 0, 0
    local profile = {}
    local ok, modifiers = pcall(unit.FindAllModifiers, unit)
    if ok then
        for _, modifier in ipairs(modifiers or {}) do
            for _, entry in ipairs({ { "GetModifierBaseDamageOutgoing_Percentage", "pct" },
                { "GetModifierPreAttack_BonusDamage", "flat" },
                { "GetModifierDamageOutgoing_Percentage", "outgoing" } }) do
                if type(modifier[entry[1]]) == "function" then
                    local value_ok, value = pcall(modifier[entry[1]], modifier)
                    if value_ok and tonumber(value) then
                        if entry[2] == "pct" then pct = pct + value
                        elseif entry[2] == "flat" then flat = flat + value
                        else
                            outgoing = outgoing + value
                            profile[#profile + 1] = { modifier = modifier:GetName(), percentage = value }
                        end
                    end
                end
            end
        end
    end
    local average = get(unit, "GetAverageTrueAttackDamage", nil)
    return { percentage = pct, flat = flat, average = average,
        outgoing_percentage = outgoing, outgoing_profile = profile,
        effective_base = average and (average - flat) / math.max(0.01, 1 + pct / 100) }
end

local function float32_attack_tolerance(value)
    -- Attack damage is represented as engine float32, even when Lua returns an
    -- integer. Two ULPs plus integer conversion cover high-stage getters.
    value = math.abs(tonumber(value) or 0)
    return value > 0 and math.max(2, 2 ^ (math.floor(math.log(value) / math.log(2)) - 23) * 2 + 2) or 2
end

-- Mutating local-test card consumer. Production ownership, buildings and hero
-- association are retained. Fixtures are real new entities, never fake getters.
-- Grants stay in this isolated match; callers should use reuse_existing on a
-- later observation and a fresh match when independently testing one-shot cards.
function M.run_card(card_id, player_id, context, options)
    player_id, options = tonumber(player_id) or 0, options or {}
    card_sequence = card_sequence + 1
    local report = { id = "boss_combat_card:" .. card_sequence, card_id = card_id,
        player_id = player_id, status = "running", assertions = {}, samples = {},
        started_at = GameRules:GetGameTime(), validation = "formal_selection_and_real_engine_consumer" }
    card_reports[report.id] = report
    local allowed, gate_error = local_gate(player_id, options)
    if not allowed then report.status, report.error = "blocked", gate_error; emit("CARD_RESULT", report); return report end
    if next(owned) then report.status, report.error = "blocked", "other_native_probe_running"; emit("CARD_RESULT", report); return report end
    local bus, events = require("core/event_bus"), require("core/events")
    local ctx, restores, subscriptions = live_context(player_id, context), {}, {}
    local function check(name, actual, expected, tolerance)
        local available = type(actual) == "number" and type(expected) == "number"
        report.assertions[#report.assertions + 1] = { name = name, actual = actual, expected = expected,
            status = not available and "unavailable" or math.abs(actual - expected) <= (tolerance or 1) and "pass" or "fail" }
    end
    local function finish(error_code)
        if report.finished_at then return end
        for _, subscription in ipairs(subscriptions) do bus.unsubscribe(subscription) end
        for _, restore in ipairs(restores) do pcall(restore) end
        M.cleanup()
        local fail, pass, unavailable = false, false, false
        for _, assertion in ipairs(report.assertions) do
            fail, pass, unavailable = fail or assertion.status == "fail", pass or assertion.status == "pass", unavailable or assertion.status == "unavailable"
        end
        report.status = error_code and "blocked" or fail and "fail" or unavailable and "partial"
            or pass and "consumer_pass" or "needs_action"
        report.error, report.finished_at = error_code, GameRules:GetGameTime()
        emit("CARD_RESULT", report)
        print("ROGUE_BOSS_CARD_DONE " .. report.id)
        if options.on_complete then pcall(options.on_complete, report) end
    end
    local function after(delay, callback)
        serial = serial + 1
        GameRules:GetGameModeEntity():SetContextThink("rogue_boss_card_" .. serial, function()
            local ok, why = xpcall(callback, debug.traceback)
            if not ok then finish(why) end
            return nil
        end, delay or 0.10)
    end
    local function fixture(actor, wave)
        local origin = valid(actor) and actor:GetAbsOrigin() or PlayerResource:GetSelectedHeroEntity(player_id):GetAbsOrigin()
        local target = spawn(origin + Vector(60, 0, 0), DOTA_TEAM_BADGUYS,
            wave and "npc_survival_wave_monster" or nil)
        if wave then target.survival_is_wave_monster = true end
        target.survival_player_id = player_id
        return target
    end
    local function select()
        report.selection = M.select_card(card_id, player_id, options)
        if not report.selection or not report.selection.ok then
            finish(report.selection and report.selection.error or "selection_failed"); return false
        end
        return true
    end
    local function sample(actor, target, callback)
        M.attack_sample(actor, target, function(value)
            report.samples[#report.samples + 1] = value
            local ok, why = xpcall(function() callback(value) end, debug.traceback)
            if not ok then finish(why) end
        end, { process_procs = options.process_procs ~= false,
            observe_native_hits = actor.survival_ultimate_tower == true })
    end
    local function actual_attack(actor, prefix)
        local expected = get(actor, "GetAverageTrueAttackDamage", nil)
        local logical = (expected or 0) * math.max(1, tonumber(actor.survival_endless_attack_scale) or 1)
        local target = fixture(actor, false)
        target.survival_endless_health_scale = math.max(1, math.ceil(logical / 1000))
        local skill_multiplier, skill_id = 1, nil
        for _, skill in pairs(require("systems/tower_skill_runtime").get(actor) or {}) do
            if tostring(skill.skill_id or ""):match("^multi_attack_") then
                skill_multiplier = require("systems/tower_multi_damage").multiplier(skill, target)
                skill_id = skill.skill_id
                break
            elseif tostring(skill.skill_id or ""):match("^anti_air_missile_") then
                skill_multiplier, skill_id = 1.9, skill.skill_id
            end
        end
        report.native_attack_skill = { skill_id = skill_id, multiplier = skill_multiplier,
            source = "actual_tower_skill_runtime_and_production_target_damage_rule" }
        if actor.survival_ultimate_tower then
            skill_multiplier = 1
            report.native_attack_skill = { multiplier = 1,
                source = "actual_native_average_already_contains_native_outgoing_profile" }
        end
        sample(actor, target, function(value)
            local dealt = (value.target_health_loss or 0) * target.survival_endless_health_scale
            local extra_pct = (tonumber(actor.survival_research_final_damage_pct) or 0)
                + (tonumber(actor.survival_seven_sins_final_damage_pct) or 0)
                + (tonumber(actor.survival_gameplay_final_damage_pct) or 0)
            local minimum = logical * (1 + extra_pct / 100) * skill_multiplier
            if value.critical_observation then
                minimum = value.critical_observation.multiplier and minimum * value.critical_observation.multiplier or nil
            end
            if actor.survival_ultimate_tower then
                -- Native outgoing depends on the current attack target (the
                -- actual multi-arrow profile is5% without a target,89% on this
                -- ground target). Observe the getter after the real hit so a
                -- preceding Stop cannot make a ground attack look too large.
                local hit_average = value.after and value.after.attacker
                    and value.after.attacker.native_average_attack
                if type(hit_average) == "number" then
                    logical = hit_average * math.max(1, tonumber(actor.survival_endless_attack_scale) or 1)
                    minimum = logical * (1 + extra_pct / 100)
                    if value.critical_observation then
                        minimum = value.critical_observation.multiplier and minimum * value.critical_observation.multiplier or nil
                    end
                    report.native_primary_expected_from_post_attack_getter = minimum
                end
                local primary
                for _, hit in ipairs(value.actual_damage_events or {}) do
                    if hit.native_attack then primary = hit; break end
                end
                check(prefix .. "_native_primary_present", primary and 1 or 0, 1, 0)
                dealt = primary and primary.health_loss * target.survival_endless_health_scale or nil
                local filtered = value.filter_transactions and value.filter_transactions[1]
                if filtered then
                    check(prefix .. "_native_filter_matches_attack", filtered.final_damage, minimum,
                        math.max(float32_attack_tolerance(minimum), logical * 0.01))
                    minimum = filtered.final_damage
                end
            end
            check(prefix .. "_actual_logical_damage", dealt, minimum,
                math.max(target.survival_endless_health_scale * 2, logical * 0.01))
            finish()
        end)
    end
    local ok, why = xpcall(function()
        if card_id == "corrosive_shield" then
            local enemy = valid(ctx.enemy) and ctx.enemy or fixture(ctx.hero, true)
            local armor_balance = require("config/armor_balance")
            if enemy ~= ctx.enemy then
                enemy.survival_war3_armor, enemy.survival_effective_war3_armor = 100, 100
                enemy.survival_armor_mapping_version = armor_balance.CUSTOM_WAR3_MAPPING_VERSION
                enemy.survival_war3_armor_target = true
                enemy:SetBaseDamageMin(10); enemy:SetBaseDamageMax(10)
            end
            local original_armor = tonumber(enemy.survival_effective_war3_armor)
                or tonumber(enemy.survival_war3_armor)
                or armor_balance.to_war3_for_mapping(enemy:GetPhysicalArmorValue(false), enemy.survival_armor_mapping_version)
            local original_native_armor = enemy:GetPhysicalArmorValue(false)
            report.original_logical_armor, report.original_native_armor = original_armor, original_native_armor
            local ally = spawn(enemy:GetAbsOrigin() + Vector(60, 0, 0), DOTA_TEAM_GOODGUYS)
            ally.survival_player_id = player_id
            if not select() then return end
            check("production_corrosion_modifier", enemy:HasModifier("modifier_rogue_corrosive_shield_attack") and 1 or 0, 1, 0)
            local hit = 0
            local next_hit
            next_hit = function()
                hit = hit + 1
                local receiver = hit == 4 and valid(ctx.hero) and ctx.hero or ally
                local old_health = receiver:GetHealth()
                sample(enemy, receiver, function(value)
                    check("real_attack_" .. hit .. "_logical_armor", enemy.survival_effective_war3_armor, original_armor - hit, 0.001)
                    if enemy.survival_armor_mapping_version == armor_balance.CUSTOM_WAR3_MAPPING_VERSION then
                        check("real_attack_" .. hit .. "_native_custom_armor", enemy:GetPhysicalArmorValue(false), original_native_armor, 0.01)
                    end
                    if receiver == ctx.hero and receiver:IsAlive() then
                        require("core/hero_health_guard").allow_healing(receiver); receiver:SetHealth(old_health)
                        report.hero_target_checked = true
                    end
                    if hit < 4 then next_hit() else finish() end
                end)
            end
            next_hit()
        elseif card_id == "kick_when_down" then
            local target = fixture(ctx.hero, true)
            local actor = spawn(target:GetAbsOrigin() + Vector(60, 0, 0), DOTA_TEAM_GOODGUYS)
            actor.survival_player_id = player_id
            if not select() then return end
            local function hit()
                local health = target:GetHealth()
                ApplyDamage({ attacker = actor, victim = target, damage = 1000, damage_type = DAMAGE_TYPE_PURE })
                return health - target:GetHealth()
            end
            local baseline = hit()
            LinkLuaModifier("modifier_tower_frost_slow", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
            LinkLuaModifier("modifier_tower_blizzard_slow", "modifiers/modifier_tower_attack_effects", LUA_MODIFIER_MOTION_NONE)
            target:AddNewModifier(actor, nil, "modifier_tower_frost_slow", { slow_pct = 25 })
            local frost = hit(); check("actual_frost_damage_ratio", frost, baseline * 1.5, 1)
            target:RemoveModifierByName("modifier_tower_frost_slow")
            target:AddNewModifier(actor, nil, "modifier_tower_blizzard_slow", { slow_pct = 25 })
            local blizzard = hit(); check("actual_blizzard_damage_ratio", blizzard, baseline * 1.5, 1)
            report.actual_damage = { baseline = baseline, frost = frost, blizzard = blizzard }
            finish()
        elseif card_id == "frozen_wall" then
            local enemy = valid(ctx.enemy) and ctx.enemy or fixture(ctx.hero, true)
            local previous = M.snapshot(enemy)
            if not select() then return end
            if report.selection.reused_existing and not enemy:HasModifier("modifier_rogue_enemy_attack_speed") then
                finish("reused_frozen_wall_requires_actual_projected_wave_enemy"); return
            end
            after(0.10, function()
                local now = M.snapshot(enemy)
                check("actual_wave_enemy_has_production_slow", enemy:HasModifier("modifier_rogue_enemy_attack_speed") and 1 or 0, 1, 0)
                if not report.selection.reused_existing then
                    check("actual_enemy_attack_speed_ratio", now.native_attack_speed,
                        previous.native_attack_speed and previous.native_attack_speed * 0.85, 0.02)
                else
                    local modifier = enemy:FindModifierByName("modifier_rogue_enemy_attack_speed")
                    check("actual_existing_enemy_slow_percentage", modifier:GetModifierAttackSpeedPercentage(), -15, 0.001)
                end
                report.before, report.after = previous, now
                finish()
            end)
        elseif card_id == "recruit_training" or card_id == "gunpowder_splash" then
            if not valid(ctx.tower) then finish("actual_registered_tower_required"); return end
            local building = bus.request(events.BUILDING_QUERY_REQUEST, { entindex = ctx.tower:entindex() }) or {}
            if card_id == "recruit_training" and not tostring(building.record_id
                or ctx.tower.survival_tower_record_id or ""):match("^arrow_tower_lv0[1-4]$") then
                finish("actual_LV1_to_LV4_base_tower_required"); return
            end
            if card_id == "gunpowder_splash" and ctx.tower.survival_tower_stage_id ~= "piercing_ballista" then
                finish("actual_piercing_ballista_route_tower_required"); return
            end
            local prior = attack_parts(ctx.tower)
            if not select() then return end
            local increment = report.selection.reused_existing and 0 or card_id == "recruit_training" and 100 or 30
            local current = attack_parts(ctx.tower)
            check("actual_tower_native_percentage_delta", current.percentage - prior.percentage, increment, 0.001)
            check("actual_tower_native_average", current.average,
                prior.average + (prior.effective_base or 0) * increment / 100 + current.flat - prior.flat, 2)
            report.tower = M.snapshot(ctx.tower)
            actual_attack(ctx.tower, card_id)
        elseif card_id == "tower_growth" then
            if not valid(ctx.tower) then finish("actual_registered_upgradable_tower_required"); return end
            if not select() then return end
            local previous = ctx.tower:FindModifierByName("modifier_rogue_tower_growth")
            local original_stacks = previous and previous:GetStackCount() or 0
            subscriptions[#subscriptions + 1] = bus.subscribe(events.BUILDING_CHANGED, function(payload)
                if report.finished_at or payload.unit ~= ctx.tower
                    or not tostring(payload.reason or ""):match("^tower_upgraded_") then return end
                bus.after_dispatch(report.id .. ":growth", function()
                    if report.finished_at then return end
                    local modifier = ctx.tower:FindModifierByName("modifier_rogue_tower_growth")
                    check("real_completed_upgrade_stack", modifier and modifier:GetStackCount(), original_stacks + 1, 0)
                    check("real_completed_upgrade_percentage", modifier and modifier:GetModifierBaseDamageOutgoing_Percentage(),
                        (original_stacks + 1) * 10, 0.001)
                    report.completed_upgrade_reason, report.tower = payload.reason, M.snapshot(ctx.tower)
                    actual_attack(ctx.tower, "real_upgraded_tower")
                end)
            end)
            report.upgrade, report.upgrade_error = bus.request(events.BUILDING_UPGRADE_REQUEST,
                { player_id = player_id, building = ctx.tower, upgrade_mode = "one",
                    system_free_upgrade = true, silent_notification = true })
            if not report.upgrade or not report.upgrade.ok then
                finish(report.upgrade and report.upgrade.error or report.upgrade_error or "actual_tower_upgrade_failed"); return
            end
            after((tonumber(report.upgrade.duration) or 0) + 10, function()
                if not report.finished_at then finish("actual_upgrade_completed_event_timeout") end
            end)
        elseif card_id == "weakening_orb" then
            if not select() then return end
            local instance
            for _, candidate in ipairs(require("systems/rogue_effect_runtime_service").snapshot(player_id)) do
                if candidate.card_id == card_id and candidate.status == "active"
                    and (not report.selection.grant_id or candidate.grant_id == report.selection.grant_id)
                    and (not instance or (tonumber(tostring(candidate.effect_instance_id):match("(%d+)$")) or 0)
                        > (tonumber(tostring(instance.effect_instance_id):match("(%d+)$")) or 0)) then instance = candidate end
            end
            if not instance or not instance.target_wave_number then finish("active_future_special_wave_target_required"); return end
            report.locked_wave, report.locked_role = instance.target_wave_number, instance.target_member_role
            subscriptions[#subscriptions + 1] = bus.subscribe(events.MONSTER_SPAWNED, function(payload)
                if report.finished_at or payload.monster_source ~= "wave" or payload.player_id ~= player_id
                    or tonumber(payload.wave_number) ~= instance.target_wave_number
                    or payload.member_role ~= instance.target_member_role or not valid(payload.unit) then return end
                bus.after_dispatch(report.id .. ":weakening", function()
                    if report.finished_at then return end
                    local enemy = payload.unit
                    local modifier = enemy:FindModifierByName("modifier_rogue_weakening_attack")
                    check("real_next_special_spawn_has_weakening", modifier and modifier:GetModifierBaseDamageOutgoing_Percentage(), -50, 0.001)
                    local native_expected = (enemy:GetBaseDamageMin() + enemy:GetBaseDamageMax()) * 0.25
                    check("real_special_native_attack_halved", get(enemy, "GetAverageTrueAttackDamage", nil), native_expected, 1)
                    check("real_spawn_consumes_once", instance.status == "completed" and instance.completed_reason == "counter_consumed" and 1 or 0, 1, 0)
                    report.matched_enemy = M.snapshot(enemy)
                    local ally = spawn(enemy:GetAbsOrigin() + Vector(60, 0, 0), DOTA_TEAM_GOODGUYS)
                    ally.survival_player_id = player_id
                    local logical = native_expected * math.max(1, tonumber(enemy.survival_endless_attack_scale) or 1)
                    ally.survival_endless_health_scale = math.max(1, math.ceil(logical / 1000))
                    sample(enemy, ally, function(value)
                        check("real_special_attack_actual_halved_damage", (value.target_health_loss or 0) * ally.survival_endless_health_scale,
                            logical, ally.survival_endless_health_scale * 2)
                        finish()
                    end)
                end)
            end)
            if options.spawn_locked_wave == true then
                report.real_wave_spawn_started, report.real_wave_spawn_error = require("systems/wave_system")
                    .debug_spawn_wave_for_players(instance.target_wave_number, { player_id })
                if not report.real_wave_spawn_started then finish(report.real_wave_spawn_error or "production_wave_spawn_failed"); return end
            end
            after(tonumber(options.timeout) or 120, function()
                if not report.finished_at then finish("waiting_for_actual_next_special_wave_spawn_timeout") end
            end)
        elseif card_id == "tower_network" then
            if not valid(ctx.tower) then finish("actual_registered_tower_required"); return end
            local prior = attack_parts(ctx.tower)
            local previous = require("systems/rogue_effect_state_service").tower_projection(player_id, "max_tower_count_attack_bonus_pct")
            local roster = bus.request(events.BUILDING_LIST_REQUEST, { player_id = player_id }) or {}
            local count = 0
            local routes = require("config/tower_route_config")
            for _, building in ipairs(roster.buildings or roster) do
                local route = { level = tonumber(building.level), tower_class = building.tower_class
                    or building.unit and building.unit.survival_tower_class }
                if building.building_id == "arrow_tower" and route.level and route.tower_class
                    and routes.current(route) and not routes.row_at_level(route, route.level + 1) then count = count + 1 end
            end
            if not select() then return end
            local value = require("systems/rogue_effect_state_service").tower_projection(player_id, "max_tower_count_attack_bonus_pct")
            local expected = report.selection.reused_existing and previous or math.min(count * 5, 50)
            check("actual_final_route_snapshot", value, expected, 0.001)
            local current = attack_parts(ctx.tower)
            check("actual_network_native_percentage", current.percentage - prior.percentage, value - previous, 0.001)
            report.full_route_towers, report.snapshot_pct = count, value
            if value == 0 then report.remaining_boundary = "nonzero_network_requires_actual_final_route_tower" end
            actual_attack(ctx.tower, "network_tower")
        elseif card_id == "boss_promise" then
            if not valid(ctx.worker) then finish("actual_registered_lumberjack_required"); return end
            local previous = M.snapshot(ctx.worker)
            if not select() then return end
            after(0.10, function()
                local now = M.snapshot(ctx.worker)
                local completed = report.selection.reused_existing and report.selection.status == "completed"
                local expected = completed and 0 or 100
                check("actual_worker_speed_modifier", ctx.worker:HasModifier("modifier_rogue_lumberjack_attack_speed") and 1 or 0,
                    completed and 0 or 1, 0)
                if not report.selection.reused_existing then
                    check("actual_worker_native_attack_speed_double", now.native_attacks_per_second,
                        previous.native_attacks_per_second and previous.native_attacks_per_second * 2, 0.05)
                end
                local modifier = ctx.worker:FindModifierByName("modifier_rogue_lumberjack_attack_speed")
                check("actual_worker_production_percentage", modifier and modifier:GetModifierAttackSpeedPercentage() or 0, expected, 0.001)
                if completed then
                    check("actual_original_deadline_elapsed", GameRules:GetGameTime() >= (report.selection.expires_at or math.huge) and 1 or 0, 1, 0)
                    check("actual_runtime_timer_completion", report.selection.completed_reason == "timer_elapsed" and 1 or 0, 1, 0)
                    report.elapsed_game_seconds = GameRules:GetGameTime() - (report.selection.created_at or GameRules:GetGameTime())
                end
                report.before, report.after = previous, now
                report.remaining_boundary = completed and "late_worker_replay_during_original_window"
                    or "120_second_original_deadline_and_late_worker_replay"
                actual_attack(ctx.worker, "promise_worker")
            end)
        elseif card_id == "bloodthirst_potion" then
            if not valid(ctx.hero) or not ctx.hero:IsRealHero() then finish("actual_real_linked_hero_required"); return end
            if not select() then return end
            local state = require("systems/rogue_effect_state_service")
            local pct = state.numeric(player_id, "hero_lifesteal_pct")
            check("current_real_lifesteal_phase_value", (pct == 100 or pct == 20) and 1 or 0, 1, 0)
            check("real_hero_has_lifesteal_consumer", ctx.hero:HasModifier("modifier_rogue_combat_bonus") and 1 or 0, 1, 0)
            local saved_health = ctx.hero:GetHealth()
            restores[#restores + 1] = function()
                if valid(ctx.hero) and ctx.hero:IsAlive() then
                    require("core/hero_health_guard").allow_healing(ctx.hero)
                    ctx.hero:SetHealth(math.min(saved_health, ctx.hero:GetMaxHealth()))
                end
            end
            ctx.hero:Stop()
            require("core/hero_health_guard").allow_healing(ctx.hero)
            ctx.hero:SetHealth(math.max(1, math.floor(ctx.hero:GetMaxHealth() * 0.2)))
            local target = fixture(ctx.hero, false)
            local logical = (get(ctx.hero, "GetAverageTrueAttackDamage", nil) or 0)
                * math.max(1, tonumber(ctx.hero.survival_endless_attack_scale) or 1)
            target.survival_gameplay_damage_reduction_pct = 90
            target.survival_endless_health_scale = math.max(1, math.ceil(logical * 0.1 / 1000))
            sample(ctx.hero, target, function(value)
                local hero_scale = math.max(1, tonumber(ctx.hero.survival_endless_health_scale) or 1)
                local amount = (value.target_health_loss or 0) * target.survival_endless_health_scale / hero_scale * pct / 100
                local gap = value.before.attacker.max_health - value.before.attacker.health
                local expected = math.min(gap, amount)
                local max_shift = math.abs((value.after.attacker.max_health or 0) - value.before.attacker.max_health)
                local tolerance = math.max(2, target.survival_endless_health_scale / hero_scale * 2, max_shift * 2)
                check("actual_native_attack_lifesteal", value.attacker_health_gain, expected, tolerance)
                report.actual_lifesteal_pct, report.expected_native_healing = pct, expected
                report.remaining_boundary = pct > 20 and "60_second_real_timer_transition_then_repeat_with_reuse_existing" or nil
                if expected <= tolerance * 2 then report.remaining_boundary = "healing_delta_too_small_for_health_quantization" end
                finish()
            end)
        elseif card_id == "training_dummy" then
            if not valid(ctx.hero) then finish("actual_linked_hero_required"); return end
            if not select() then return end
            local dummy
            for _, unit in ipairs(Entities:FindAllByClassname("npc_dota_creature") or {}) do
                if valid(unit) and unit.survival_is_training_dummy and unit.survival_player_id == player_id then dummy = unit; break end
            end
            if not valid(dummy) then finish("production_training_dummy_placement_unavailable"); return end
            report.dummy = M.snapshot(dummy)
            local original = tonumber(ctx.hero.survival_rogue_dummy_attack_bonus) or 0
            sample(ctx.hero, dummy, function()
                check("actual_dummy_first_attack_gain", (tonumber(ctx.hero.survival_rogue_dummy_attack_bonus) or 0) - original, 100, 0.001)
                sample(ctx.hero, dummy, function()
                    check("actual_dummy_second_attack_gain", (tonumber(ctx.hero.survival_rogue_dummy_attack_bonus) or 0) - original, 200, 0.001)
                    local modifier = ctx.hero:FindModifierByName("modifier_rogue_training_attack")
                    check("actual_dummy_native_projection", modifier and modifier:GetModifierPreAttack_BonusDamage(),
                        (original + 200) / math.max(1, tonumber(ctx.hero.survival_endless_attack_scale) or 1), 0.001)
                    report.remaining_boundary = "30_second_production_placement_retirement"
                    finish()
                end)
            end)
        elseif card_id == "high_morale" then
            if not valid(ctx.hero) or not valid(ctx.tower) then finish("actual_linked_hero_and_tower_required"); return end
            local prior_hero, prior_tower = attack_parts(ctx.hero), attack_parts(ctx.tower)
            local prior_ultimate = valid(ctx.ultimate) and attack_parts(ctx.ultimate) or nil
            if not select() then return end
            local increment = report.selection.reused_existing and 0 or 30
            for _, item in ipairs({ { ctx.hero, prior_hero, "hero" }, { ctx.tower, prior_tower, "tower" } }) do
                local current = attack_parts(item[1])
                local modifier = item[1]:FindModifierByName("modifier_rogue_combat_bonus")
                check(item[3] .. "_production_morale_modifier", modifier and modifier:GetModifierBaseDamageOutgoing_Percentage(),
                    require("systems/rogue_effect_state_service").numeric(player_id, "unit_attack_bonus_pct"), 0.001)
                check(item[3] .. "_native_percentage_delta", current.percentage - item[2].percentage, increment, 0.001)
                check(item[3] .. "_native_mean_after", current.average,
                    item[2].average + (item[2].effective_base or 0) * increment / 100
                        + (current.flat - item[2].flat), 2)
            end
            if prior_ultimate then
                local current = attack_parts(ctx.ultimate)
                check("ultimate_native_percentage_delta", current.percentage - prior_ultimate.percentage, increment, 0.001)
                report.ultimate = M.snapshot(ctx.ultimate)
            end
            report.hero, report.tower = M.snapshot(ctx.hero), M.snapshot(ctx.tower)
            actual_attack(ctx.hero, "hero_morale")
        elseif card_id == "in_step" then
            if not valid(ctx.hero) or not valid(ctx.tower) then finish("actual_linked_hero_and_tower_required"); return end
            if not select() then return end
            local state = require("systems/rogue_effect_state_service")
            local pct = state.numeric(player_id, "tower_hero_attack_projection_pct")
            local native_hero = get(ctx.hero, "GetAverageTrueAttackDamage", ctx.hero)
            local expected = (native_hero or 0) * math.max(1, tonumber(ctx.hero.survival_endless_attack_scale) or 1)
                * pct / 100 / math.max(1, tonumber(ctx.tower.survival_endless_attack_scale) or 1)
            local modifier = ctx.tower:FindModifierByName("modifier_rogue_combat_bonus")
            check("linked_hero_native_flat_projection", modifier and modifier:GetModifierPreAttack_BonusDamage(), expected, 0.001)
            check("linked_hero_present_in_production_service",
                native_entity((bus.request(events.HERO_SUMMON_GET_REQUEST, { player_id = player_id }) or {}).unit) == ctx.hero and 1 or 0, 1, 0)
            if valid(ctx.ultimate) then
                local baseline = ctx.ultimate.survival_ultimate_rogue_baseline or {}
                local desired = ((native_hero or 0) * math.max(1, tonumber(ctx.hero.survival_endless_attack_scale) or 1)
                    * pct / 100 - (tonumber(baseline.hero_attack_projection) or 0)
                    + (tonumber(ctx.ultimate.survival_ultimate_technology_attack_flat) or 0)
                    - (tonumber(baseline.technology_attack_flat) or 0))
                    / math.max(1, tonumber(ctx.ultimate.survival_endless_attack_scale) or 1)
                local ultimate_modifier = ctx.ultimate:FindModifierByName("modifier_rogue_ultimate_tower_effects")
                check("ultimate_linked_hero_projection", ultimate_modifier and ultimate_modifier:GetModifierPreAttack_BonusDamage(), desired, 0.001)
            end
            report.hero, report.tower = M.snapshot(ctx.hero), M.snapshot(ctx.tower)
            actual_attack(ctx.tower, "tower_hero_projection")
        elseif card_id == "iron_fist_policy" then
            local actor = valid(ctx.ultimate) and ctx.ultimate or ctx.tower or ctx.hero
            if not valid(actor) then finish("actual_tower_or_hero_required"); return end
            local target = fixture(actor, false)
            target.survival_war3_armor, target.survival_effective_war3_armor = 100, 100
            target.survival_armor_mapping_version = require("config/armor_balance").CUSTOM_WAR3_MAPPING_VERSION
            target.survival_war3_armor_target = true
            local logical = (get(actor, "GetAverageTrueAttackDamage", nil) or 0)
                * math.max(1, tonumber(actor.survival_endless_attack_scale) or 1)
            target.survival_endless_health_scale = math.max(1, math.ceil(logical / 1000))
            if not select() then return end
            local pct = require("systems/rogue_effect_state_service").numeric(player_id, "physical_armor_ignore_pct")
            sample(actor, target, function(value)
                local actual = (value.target_health_loss or 0) * target.survival_endless_health_scale
                local expected = logical * require("config/armor_balance").war3_physical_damage_multiplier(100, pct)
                local bonus = (tonumber(actor.survival_research_final_damage_pct) or 0)
                    + (tonumber(actor.survival_seven_sins_final_damage_pct) or 0)
                    + (tonumber(actor.survival_gameplay_final_damage_pct) or 0)
                if value.critical_observation then
                    expected = value.critical_observation.multiplier and expected * value.critical_observation.multiplier or nil
                end
                check("actual_physical_attack_armor_piercing", actual, expected and expected * (1 + bonus / 100),
                    math.max(target.survival_endless_health_scale * 2, logical * 0.01))
                finish()
            end)
        elseif card_id == "feast" then
            if not valid(ctx.wall) then finish("actual_registered_wall_required"); return end
            local before_health, before_max = ctx.wall:GetHealth(), ctx.wall:GetMaxHealth()
            if not select() then return end
            if report.selection.reused_existing then finish("one_shot_feast_needs_fresh_grant"); return end
            check("actual_wall_maximum_double", ctx.wall:GetMaxHealth(), before_max * 2, 1)
            check("actual_wall_current_double", ctx.wall:GetHealth(), before_health * 2, 1)
            report.wall = M.snapshot(ctx.wall)
            finish()
        elseif card_id == "ion_shield" then
            if not valid(ctx.wall) then finish("actual_registered_wall_required"); return end
            local actor = fixture(ctx.wall, false)
            if not select() then return end
            local health = ctx.wall:GetHealth()
            restores[#restores + 1] = function() if valid(ctx.wall) and ctx.wall:IsAlive() then ctx.wall:SetHealth(health) end end
            local scale = math.max(1, tonumber(ctx.wall.survival_endless_health_scale) or 1)
            local maximum = ctx.wall:GetMaxHealth()
            if health <= maximum * 0.2 + 1 then finish("wall_needs_more_than_20_percent_health"); return end
            ApplyDamage({ attacker = actor, victim = ctx.wall, damage = maximum * scale * 100,
                damage_type = DAMAGE_TYPE_PURE })
            check("actual_wall_damage_20_percent_cap", health - ctx.wall:GetHealth(), maximum * 0.2, 1)
            finish()
        elseif card_id == "fortifications" then
            local actor = valid(ctx.ultimate) and ctx.ultimate or ctx.tower
            if not valid(actor) then finish("actual_registered_tower_required"); return end
            local before = M.snapshot(actor)
            local previous = require("systems/technology_stat_manager").get(player_id).final.tower.attack_speed_bonus_pct or 0
            if not select() then return end
            local current = require("systems/technology_stat_manager").get(player_id).final.tower.attack_speed_bonus_pct or 0
            local increment = report.selection.reused_existing and 0 or 6
            check("production_technology_speed_increment", current - previous, increment, 0.001)
            after(0.2, function()
                local now = M.snapshot(actor)
                local expected = before.native_attacks_per_second
                    and M.native_frequency_expected(before.native_attacks_per_second, previous, current)
                report.frequency_projection = {prior_total_technology_ias_pct = previous,
                    current_total_technology_ias_pct = current, expected_native_frequency = expected,
                    formula = "native_before * (100 + current_total_IAS) / (100 + prior_total_IAS)"}
                check("actual_native_tower_frequency", now.native_attacks_per_second,
                    expected, 0.03)
                report.before, report.after = before, now
                actual_attack(actor, "fortified_tower")
            end)
        else
            finish("card_consumer_not_implemented_here")
        end
    end, debug.traceback)
    if not ok then finish(why) end
    return report
end

-- Real fusion only. Never creates a fusion or supplies its identity/baseline.
-- The optional grants and reversible debug attack use normal production requests.
function M.run_ultimate(context, options)
    options = options or {}
    local player_id = tonumber(options.player_id or context and context.player_id) or 0
    local allowed, gate_error = local_gate(player_id, options)
    serial = serial + 1
    local report = { id = "boss_ultimate:" .. serial, status = "running", player_id = player_id,
        validation = "actual_fusion_baseline_formal_grants_native_getters_and_damage", assertions = {},
        started_at = GameRules:GetGameTime(), cards = { "long_range_volley", "sharp_volley", "high_morale", "tower_network", "in_step" } }
    card_reports[report.id] = report
    local bus, events = require("core/event_bus"), require("core/events")
    local ctx = live_context(player_id, context)
    local unit, hero, restore_hero = ctx.ultimate, ctx.hero, nil
    local function check(name, actual, expected, tolerance)
        local available = type(actual) == "number" and type(expected) == "number"
        report.assertions[#report.assertions + 1] = { name = name, actual = actual, expected = expected,
            status = not available and "unavailable" or math.abs(actual - expected) <= (tolerance or 1) and "pass" or "fail" }
    end
    local function finish(error_code)
        if report.finished_at then return end
        if restore_hero then pcall(restore_hero); restore_hero = nil end
        M.cleanup()
        local fail, unavailable = false, false
        for _, assertion in ipairs(report.assertions) do
            fail = fail or assertion.status == "fail"
            unavailable = unavailable or assertion.status == "unavailable"
        end
        report.status = error_code and "blocked" or fail and "fail" or unavailable and "partial" or "consumer_pass"
        report.error, report.finished_at = error_code, GameRules:GetGameTime()
        emit("ULTIMATE_RESULT", report); print("ROGUE_BOSS_ULTIMATE_DONE " .. report.id)
        if options.on_complete then pcall(options.on_complete, report) end
    end
    if not allowed then finish(gate_error); return report end
    if next(owned) then finish("other_native_probe_running"); return report end
    if not valid(unit) or unit.survival_ultimate_tower ~= true then finish("actual_production_fusion_entity_required"); return report end
    if tonumber(unit.survival_player_id) ~= player_id then finish("actual_fusion_owner_mismatch"); return report end
    if not unit.survival_ultimate_rogue_baseline then finish("actual_production_fusion_baseline_required"); return report end
    local function after(delay, callback)
        serial = serial + 1
        GameRules:GetGameModeEntity():SetContextThink("rogue_ultimate_probe_" .. serial, function()
            if report.finished_at then return nil end
            local ok, why = xpcall(callback, debug.traceback)
            if not ok then finish(why) end
            return nil
        end, delay)
    end
    local state = require("systems/rogue_effect_state_service")
    local function technology()
        local value = require("systems/technology_stat_manager").get(player_id).final.tower
        return { attack_flat = tonumber(value.attack_flat) or 0,
            attack_range_bonus = tonumber(value.attack_range_bonus) or 0,
            attack_speed_bonus_pct = tonumber(value.attack_speed_bonus_pct) or 0 }
    end
    local function verify_projection(label)
        local baseline = unit.survival_ultimate_rogue_baseline
        local modifier = unit:FindModifierByName("modifier_rogue_ultimate_tower_effects")
        local current_pct = state.numeric(player_id, "unit_attack_bonus_pct")
            + state.tower_projection(player_id, "max_tower_count_attack_bonus_pct")
        local hero_projection = valid(hero) and (get(hero, "GetAverageTrueAttackDamage", nil) or 0)
            * math.max(1, tonumber(hero.survival_endless_attack_scale) or 1)
            * state.numeric(player_id, "tower_hero_attack_projection_pct") / 100 or 0
        check(label .. "_unbaked_percentage_only", modifier and modifier:GetModifierBaseDamageOutgoing_Percentage(),
            current_pct - (tonumber(baseline.attack_bonus_pct) or 0), 0.001)
        check(label .. "_unbaked_hero_and_technology_flat_only", modifier and modifier:GetModifierPreAttack_BonusDamage(),
            (hero_projection - (tonumber(baseline.hero_attack_projection) or 0)
                + technology().attack_flat - (tonumber(baseline.technology_attack_flat) or 0))
                / math.max(1, tonumber(unit.survival_endless_attack_scale) or 1), 0.001)
        local parts = attack_parts(unit)
        local base = ((get(unit, "GetBaseDamageMin") or 0) + (get(unit, "GetBaseDamageMax") or 0)) / 2
        check(label .. "_native_average_consistent_with_baseline", parts.average,
            M.native_average_expected(base, parts.percentage, parts.outgoing_percentage, parts.flat),
            float32_attack_tolerance(parts.average))
        report[label .. "_native_parts"] = parts
        return parts, hero_projection
    end
    local function select(card_id)
        local grant_options = { local_test = true, allow_builder = true, reuse_existing = options.reuse_existing ~= false }
        local result = M.select_card(card_id, player_id, grant_options)
        report[card_id .. "_selection"] = result
        if not result or not result.ok then finish(result and result.error or "formal_selection_failed"); return nil end
        return result
    end
    local function sample_attack()
        unit:Stop()
        local expected_native = get(unit, "GetAverageTrueAttackDamage", nil)
        local attack_scale = math.max(1, tonumber(unit.survival_endless_attack_scale) or 1)
        local logical = (expected_native or 0) * attack_scale
        local target = spawn(unit:GetAbsOrigin() + Vector(60, 0, 0), DOTA_TEAM_BADGUYS)
        target.survival_endless_health_scale = math.max(1, math.ceil(logical / 1000))
        report.actual_skills = {}
        for _, skill in pairs(require("systems/tower_skill_runtime").get(unit) or {}) do
            report.actual_skills[#report.actual_skills + 1] = skill.skill_id
        end
        local bonus = (tonumber(unit.survival_research_final_damage_pct) or 0)
            + (tonumber(unit.survival_seven_sins_final_damage_pct) or 0)
            + (tonumber(unit.survival_gameplay_final_damage_pct) or 0)
        M.attack_sample(unit, target, function(value)
            report.actual_attack = value
            -- GetAverageTrueAttackDamage already includes the native outgoing
            -- profile. Script multi-arrow secondary delivery is a separate hit.
            local expected = logical * (1 + bonus / 100)
            if value.critical_observation and value.critical_observation.multiplier then
                expected = expected * value.critical_observation.multiplier
            end
            local primary
            for _, hit in ipairs(value.actual_damage_events or {}) do
                if hit.native_attack then primary = hit; break end
            end
            check("actual_native_primary_attack_exists", primary and 1 or 0, 1, 0)
            local filtered = value.filter_transactions and value.filter_transactions[1]
            report.primary_filter_transaction = filtered
            if filtered then
                check("actual_native_primary_filter_matches_attack", filtered.final_damage, expected,
                    math.max(float32_attack_tolerance(expected), expected * 0.01))
            end
            check("actual_native_primary_logical_health_loss", primary and primary.health_loss * target.survival_endless_health_scale,
                filtered and filtered.final_damage or expected,
                math.max(target.survival_endless_health_scale * 2, expected * 0.01))
            report.observed_total_logical_health_loss = (value.target_health_loss or 0) * target.survival_endless_health_scale
            report.after = M.snapshot(unit)
            finish()
        end, { process_procs = options.process_procs ~= false, observe_native_hits = true, delay = 0.20 })
    end
    local function dynamic_hero()
        if options.dynamic_hero == false or not valid(hero) then sample_attack(); return end
        local pct = state.numeric(player_id, "tower_hero_attack_projection_pct")
        if pct == 0 then report.remaining_boundary = "no_actual_in_step_card_for_dynamic_hero_projection"; sample_attack(); return end
        hero:Stop()
        local previous_stats = bus.request(events.HERO_COMBAT_STATS_GET_REQUEST, { player_id = player_id }) or {}
        local previous_debug = previous_stats.snapshot and tonumber(previous_stats.snapshot.debug_attack_override) or 0
        local prior_flat = unit:FindModifierByName("modifier_rogue_ultimate_tower_effects"):GetModifierPreAttack_BonusDamage()
        local prior_projection = (get(hero, "GetAverageTrueAttackDamage", nil) or 0)
            * math.max(1, tonumber(hero.survival_endless_attack_scale) or 1) * pct / 100
        restore_hero = function()
            bus.request(events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST, previous_debug and previous_debug > 0
                and { player_id = player_id, attack = previous_debug } or { player_id = player_id, reset = true })
        end
        report.hero_update = bus.request(events.HERO_COMBAT_STATS_DEBUG_ATTACK_REQUEST,
            { player_id = player_id, attack_delta = tonumber(options.hero_attack_delta) or 1000 })
        if not report.hero_update or not report.hero_update.ok then finish("actual_debug_attack_request_failed"); return end
        after(0.15, function()
            local _, current_projection = verify_projection("dynamic")
            local current_flat = unit:FindModifierByName("modifier_rogue_ultimate_tower_effects"):GetModifierPreAttack_BonusDamage()
            check("actual_hero_projection_changed", math.abs(current_projection - prior_projection) > 1 and 1 or 0, 1, 0)
            check("actual_ultimate_dynamic_flat_delta", current_flat - prior_flat,
                (current_projection - prior_projection) / math.max(1, tonumber(unit.survival_endless_attack_scale) or 1), 0.001)
            report.hero_after = M.snapshot(hero)
            sample_attack()
        end)
    end
    local function sharp()
        local previous_native, prior_technology = M.snapshot(unit), technology()
        local grant = options.grant_sharp_card ~= false and select("sharp_volley") or { reused_existing = true }
        if not grant or report.finished_at then return end
        after(0.15, function()
            local current_native, current_technology = M.snapshot(unit), technology()
            local increment = grant.reused_existing and 0 or 20
            check("formal_sharp_technology_speed_increment", current_technology.attack_speed_bonus_pct - prior_technology.attack_speed_bonus_pct, increment, 0.001)
            check("actual_ultimate_native_frequency_increment", current_native.native_attacks_per_second,
                previous_native.native_attacks_per_second and previous_native.native_attacks_per_second
                    * (100 + current_technology.attack_speed_bonus_pct) / (100 + prior_technology.attack_speed_bonus_pct), 0.03)
            report.sharp_before, report.sharp_after = previous_native, current_native
            verify_projection("post_sharp")
            dynamic_hero()
        end)
    end
    local ok, why = xpcall(function()
        unit:Stop()
        report.baseline = { attack_bonus_pct = unit.survival_ultimate_rogue_baseline.attack_bonus_pct,
            hero_attack_projection = unit.survival_ultimate_rogue_baseline.hero_attack_projection,
            technology_attack_flat = unit.survival_ultimate_rogue_baseline.technology_attack_flat }
        report.before = M.snapshot(unit)
        report.current_rogue_values = { morale_pct = state.numeric(player_id, "unit_attack_bonus_pct"),
            network_pct = state.tower_projection(player_id, "max_tower_count_attack_bonus_pct"),
            hero_projection_pct = state.numeric(player_id, "tower_hero_attack_projection_pct") }
        local prior_parts = verify_projection("inherited")
        local prior_technology = technology()
        local grant = options.grant_range_card ~= false and select("long_range_volley") or { reused_existing = true }
        if not grant or report.finished_at then return end
        after(0.15, function()
            local current_native, current_technology = M.snapshot(unit), technology()
            local increment = grant.reused_existing and 0 or 800
            check("formal_range_technology_attack_increment", current_technology.attack_flat - prior_technology.attack_flat, increment, 0.001)
            check("formal_range_technology_range_increment", current_technology.attack_range_bonus - prior_technology.attack_range_bonus,
                grant.reused_existing and 0 or 500, 0.001)
            check("actual_ultimate_native_range_increment", current_native.native_attack_range - report.before.native_attack_range,
                grant.reused_existing and 0 or 500, 0.01)
            local current_parts = attack_parts(unit)
            check("actual_ultimate_native_attack_800_increment", current_parts.average - prior_parts.average,
                current_parts.flat - prior_parts.flat,
                float32_attack_tolerance(current_parts.average))
            report.range_after = current_native
            verify_projection("post_range")
            sharp()
        end)
    end, debug.traceback)
    if not ok then finish(why) end
    return report
end

return M
