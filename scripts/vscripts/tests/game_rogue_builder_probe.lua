-- Tools-only native before/after helper. It does not reset the game, initialize
-- production services or intercept damage/resource handlers. Run one card in a
-- clean test state; an already active card is reported as skipped, not passed.
local M = {}
local bus = require("core/event_bus")
local events = require("core/events")
local runtime = require("systems/rogue_effect_runtime_service")
local cards = require("config/generated/rogue_reward_cards")
local sequence = 0

local function native(unit, method, ...)
    if not unit or unit:IsNull() or not unit[method] then return nil end
    local ok, result = pcall(unit[method], unit, ...)
    return ok and tonumber(result) or nil
end

local function request(name, player_id)
    local ok, value = pcall(bus.request, name, {player_id = player_id})
    return ok and value or nil
end

function M.snapshot(unit, player_id)
    if type(unit) == "number" then unit = EntIndexToHScript(unit) end
    local result = {time = GameRules:GetGameTime(), player_id = player_id,
        resources = request(events.RESOURCE_GET_REQUEST, player_id),
        hero = request(events.HERO_COMBAT_STATS_GET_REQUEST, player_id)}
    if not unit or unit:IsNull() then result.entity_available = false; return result end
    result.entity_available = true
    result.entindex, result.unit_name = unit:entindex(), unit:GetUnitName()
    local aps = native(unit, "GetAttacksPerSecond", false)
    local interval = native(unit, "GetSecondsPerAttack", false)
    local interval_source = interval and "native_seconds_per_attack" or nil
    if not interval and aps and aps > 0 then
        interval, interval_source = 1 / aps, "native_attacks_per_second"
    end
    result.native = {
        attack_min = native(unit, "GetBaseDamageMin"),
        attack_max = native(unit, "GetBaseDamageMax"),
        attack = native(unit, "GetAverageTrueAttackDamage", nil),
        range = native(unit, "GetAttackRange") or native(unit, "Script_GetAttackRange"),
        bat = native(unit, "GetBaseAttackTime", false) or native(unit, "GetBaseAttackTime"),
        attack_speed = native(unit, "GetAttackSpeed", false),
        attack_interval = interval, attack_interval_source = interval_source,
        attacks_per_second = aps,
        health = native(unit, "GetHealth"), max_health = native(unit, "GetMaxHealth"),
        armor = native(unit, "GetPhysicalArmorValue", false),
    }
    result.attack_scale = tonumber(unit.survival_endless_attack_scale) or 1
    local technology = require("systems/technology_stat_manager").get(player_id).final or {}
    local permanent_result = request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, player_id) or {}
    local permanent = permanent_result.totals or {}
    result.tower_attack_multiplier = 1 + ((tonumber((technology.tower or {}).attack_bonus_pct) or 0)
        + (tonumber(permanent.tower_attack_bonus_pct) or 0)) / 100
    result.effective_war3_armor = tonumber(unit.survival_effective_war3_armor)
    result.building_id, result.hero_id = unit.survival_building_id, unit.survival_hero_id
    result.worker_type = unit.survival_worker_type
    result.worker_ai = nil
    local ai = unit:FindModifierByName("modifier_lumberjack_ai")
    if ai then result.worker_ai = {efficiency = ai.lumber_efficiency,
        technology_efficiency = ai.technology_lumber_efficiency,
        base_efficiency = ai.base_lumber_efficiency, fusion_count = ai.fusion_count,
        critical_chance = ai.technology_crit_chance, tree_entindex = ai.tree_entindex} end
    return result
end

local function check(report, name, actual, expected, tolerance)
    local available = type(actual) == "number" and type(expected) == "number"
    report.assertions[#report.assertions + 1] = {name = name,
        actual = actual, expected = expected, status = not available and "unavailable"
            or math.abs(actual - expected) <= (tolerance or 0.001) and "pass" or "fail"}
end

local function account(snapshot)
    local value = snapshot and snapshot.resources
    return value and (value.snapshot or value) or {}
end

function M.grant(card_id, player_id, options)
    options = options or {}
    sequence = sequence + 1
    if options.via_selection ~= true then
        return runtime.grant(player_id, card_id,
            "native_builder_probe:" .. tostring(GameRules:GetGameTime()) .. ":" .. sequence,
            "builder_start")
    end
    local candidates = {card_id}
    for _, card in ipairs(cards.rows or {}) do
        if card.enabled ~= false and card.type == "builder_start" and card.card_id ~= card_id
            and #candidates < 3 then candidates[#candidates + 1] = card.card_id end
    end
    local observations = {}
    local token = bus.subscribe(events.ROGUE_REWARD_CHANGED, function(payload)
        if tonumber(payload and payload.player_id) ~= player_id then return end
        local snapshot = payload.snapshot or {}
        local history = {}
        for _, row in ipairs(snapshot.history or {}) do
            history[#history + 1] = {card_id = row.card_id, grant_id = row.grant_id,
                reward_type = row.reward_type}
        end
        observations[#observations + 1] = {reason = snapshot.reason,
            active = snapshot.active, token = snapshot.token, history = history,
            builder_talent = snapshot.builder_talent}
    end)
    local ok, result = pcall(function()
        local offer = require("systems/rogue_reward_service").debug_offer(player_id, candidates)
        if not offer or not offer.ok then return offer or {ok = false, error = "debug_offer_failed"} end
        local selected, error_code = bus.request(events.ROGUE_REWARD_SELECT_REQUEST, {
            player_id = player_id, token = offer.token, card_id = card_id,
            reward_type = "builder_start",
        })
        selected = selected or {ok = false, error = error_code or "selection_handler_unavailable"}
        selected.offer = offer
        return selected
    end)
    bus.unsubscribe(token)
    if not ok then return {ok = false, error = tostring(result), via = "real_selection"} end
    result.via, result.ui_updates, result.offered_ids = "real_selection", observations, candidates
    return result
end

-- Grants intentionally remain in the test world because aggregate technology
-- projections have no supported inverse. The caller must use a clean world or
-- a distinct test player for independent cards and record that test isolation.
function M.run(card_id, player_id, entindex, options)
    options = options or {}
    player_id = tonumber(player_id) or 0
    local card = cards.by_id[tostring(card_id)]
    local report = {card_id = card_id, player_id = player_id,
        validation = "dota_native_getters", assertions = {}, resource_events = {},
        status = "running"}
    if not IsInToolsMode or not IsInToolsMode() then
        report.status, report.error = "blocked", "requires_tools_mode"; return report
    end
    if not card or card.enabled == false or card.type ~= "builder_start" then
        report.status, report.error = "blocked", "enabled_builder_card_required"; return report
    end
    for _, instance in ipairs(runtime.snapshot(player_id)) do
        if instance.card_id == card_id then
            report.status, report.error = "skipped", "card_already_granted"; return report
        end
    end
    local unit = entindex and EntIndexToHScript(tonumber(entindex)) or nil
    report.before = M.snapshot(unit, player_id)
    local resource_subscription = bus.subscribe(events.RESOURCE_CHANGED, function(payload)
        if tonumber(payload and payload.player_id) == player_id
            and tostring(payload.reason or "") == "rogue_reward:" .. tostring(card_id) then
            report.resource_events[#report.resource_events + 1] = {
                time = GameRules:GetGameTime(), reason = payload.reason,
                wood = payload.wood, gold = payload.gold,
                max_population = payload.max_population, population = payload.population,
            }
        end
    end)
    report.grant = M.grant(card_id, player_id, options)
    if not report.grant.ok then
        bus.unsubscribe(resource_subscription)
        report.status, report.error = "fail", report.grant.error; return report
    end
    report.after = M.snapshot(unit, player_id)
    local b, a = report.before.native or {}, report.after.native or {}
    if card_id == "long_range_volley" and unit
        and unit.survival_building_id == "arrow_tower" then
        check(report, "native range delta", a.range and b.range and a.range - b.range, 500)
        check(report, "native base attack logical delta including existing percentage bonuses", a.attack_min and b.attack_min
            and (a.attack_min - b.attack_min) * report.after.attack_scale,
            800 * report.after.tower_attack_multiplier, math.max(1, report.after.attack_scale))
    elseif card_id == "fortified_defense" and unit
        and unit.survival_building_id == "wall" then
        check(report, "native maximum health delta", a.max_health and b.max_health
            and a.max_health - b.max_health, 5000)
        check(report, "current health ratio preserved", a.health and a.max_health
            and a.health / a.max_health, b.health and b.max_health and b.health / b.max_health,
            0.002)
        check(report, "effective War3 armor delta", report.after.effective_war3_armor
            and report.before.effective_war3_armor and report.after.effective_war3_armor
                - report.before.effective_war3_armor, 5)
        report.remaining = {"measure real incoming damage ratio 0.90; physical armor separately"}
    elseif card_id == "instant_wood" then
        local wave = request(events.WAVE_STATE_GET_REQUEST, player_id) or {}
        local difficulty = tonumber(tostring(wave.difficulty_id or ""):match("(%d+)$")) or 1
        check(report, "wallet wood delta", (account(report.after).wood or 0)
            - (account(report.before).wood or 0), 100 * difficulty)
    elseif card_id == "population_expansion" then
        check(report, "wallet population cap delta", (account(report.after).max_population or 0)
            - (account(report.before).max_population or 0), 5)
    elseif card_id == "lumberjack_assault" or card_id == "sharp_volley"
        or card_id == "wind_strategy" or card_id == "allround_tempering" then
        if a.attack_interval and b.attack_interval then
            report.assertions[#report.assertions + 1] = {name = "native attack interval decreases",
                actual = a.attack_interval, before = b.attack_interval,
                status = a.attack_interval < b.attack_interval and "pass" or "fail"}
        else
            report.assertions[#report.assertions + 1] = {name = "native attack interval decreases",
                status = "unavailable"}
        end
        report.remaining = {"compare observed attack timestamps with native getters; ensure uncapped IAS"}
    elseif card_id == "precision_lumber" then
        local before_ai, after_ai = report.before.worker_ai, report.after.worker_ai
        check(report, "live worker AI efficiency delta", before_ai and after_ai
            and tonumber(before_ai.technology_efficiency) and tonumber(after_ai.technology_efficiency)
            and after_ai.technology_efficiency - before_ai.technology_efficiency,
            after_ai and tonumber(after_ai.fusion_count) or 1)
        report.remaining = {"real tree-hit resource payout ordinary +1; fused +fusion_count"}
    else
        report.remaining = {"requires card-specific action or timed consumer; grant alone is not a pass"}
    end
    local failed, passed = false, false
    for _, assertion in ipairs(report.assertions) do
        failed = failed or assertion.status == "fail"
        passed = passed or assertion.status == "pass"
    end
    report.status = failed and "fail" or passed and "native_partial_pass" or "needs_action"
    if options.after_seconds and tonumber(options.after_seconds) > 0 then
        GameRules:GetGameModeEntity():SetContextThink("BuilderRogueProbe_" .. sequence,
            function()
                report.after_wait = M.snapshot(unit, player_id)
                bus.unsubscribe(resource_subscription)
                if options.on_complete then options.on_complete(report) end
                return nil
            end, tonumber(options.after_seconds))
    else
        bus.unsubscribe(resource_subscription)
    end
    return report
end

function M.run_consumers(card_id, player_id, context, options)
    return require("tests/game_rogue_builder_consumers").run(card_id, player_id, context, options)
end

return M
