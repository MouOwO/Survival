-- Tools-only action/real-timer checks. No production init/reset and no fake
-- resource responses. Native forced attacks and formal upgrade requests use
-- existing game entities. Caller owns the isolated test world and card state.
local M, reports, cancellers = {}, {}, {}
local bus, events = require("core/event_bus"), require("core/events")
local probe = require("tests/game_rogue_builder_probe")
local runtime = require("systems/rogue_effect_runtime_service")
local effect_state = require("systems/rogue_effect_state_service")
local cards = require("config/generated/rogue_reward_cards")
local sequence = 0

local function valid(unit) return unit and not unit:IsNull() and unit:IsAlive() end
local function entity(value)
    if type(value) == "number" then return EntIndexToHScript(value) end
    return value
end
local function owner(unit)
    return tonumber(unit and unit.survival_player_id)
        or unit and unit.GetPlayerOwnerID and tonumber(unit:GetPlayerOwnerID())
end
local function request(event, payload)
    local ok, result, why = pcall(bus.request, event, payload or {})
    return ok and result or nil, ok and why or tostring(result)
end
local function wallet(pid)
    local value = request(events.RESOURCE_GET_REQUEST, {player_id = pid}) or {}
    return value.snapshot or value
end
local function add_check(report, label, actual, expected, tolerance)
    local available = type(actual) == "number" and type(expected) == "number"
    report.assertions[#report.assertions + 1] = {name = label, actual = actual,
        expected = expected, status = not available and "unavailable" or
            math.abs(actual - expected) <= (tolerance or 0.001) and "pass" or "fail"}
end
local function context_for(value)
    if type(value) == "number" or type(value) == "userdata"
        or type(value) == "table" and value.entindex then
        local unit = entity(value)
        if not valid(unit) then return {} end
        local key = unit.survival_building_id == "gold_mine" and "mine"
            or unit.survival_building_id == "main_city" and "city"
            or unit.survival_building_id == "wall" and "wall"
            or unit.IsRealHero and unit:IsRealHero() and "hero" or "worker"
        return {[key] = unit}
    end
    local result = {}
    for key, item in pairs(value or {}) do result[key] = entity(item) end
    return result
end

-- Runs native contact synchronously, restoring its optional observer/RNG even
-- on failure. RESOURCE_ADD_REQUEST still uses the original production handler.
local function harvest(actor, tree, pid, rng_value)
    local result = {kind = "native_PerformAttack", resources = {}, hits = {}}
    local old_request, old_random = bus.request, RandomFloat
    local observation = bus.subscribe(events.TREE_HIT, function(payload)
        if payload and payload.attacker == actor and payload.target == tree then
            result.hits[#result.hits + 1] = payload
        end
    end)
    local wrapper = function(event, payload)
        local value, why = old_request(event, payload)
        if event == events.RESOURCE_ADD_REQUEST and tonumber(payload.player_id) == pid
            and (payload.reason == "lumberjack_hit" or payload.reason == "hero_tree_hit") then
            result.resources[#result.resources + 1] = {wood = payload.wood,
                gold = payload.gold, reason = payload.reason, ok = value and value.ok == true}
        end
        return value, why
    end
    bus.request = wrapper
    if rng_value ~= nil then RandomFloat = function() return tonumber(rng_value) end end
    local ok, why = pcall(function()
        assert(actor.PerformAttack, "native_PerformAttack_unavailable")
        actor:PerformAttack(tree, false, true, true, true, false, false, true)
    end)
    if bus.request == wrapper then bus.request = old_request
    else result.observer_restore_error = "request_wrapper_changed_during_capture" end
    if rng_value ~= nil then RandomFloat = old_random end
    bus.unsubscribe(observation)
    result.ok, result.error = ok, not ok and tostring(why) or nil
    result.wood = 0
    for _, transaction in ipairs(result.resources) do
        if transaction.ok then result.wood = result.wood + (tonumber(transaction.wood) or 0) end
    end
    -- Do not serialize unit handles from the real event payload.
    local compact = {}
    for _, hit in ipairs(result.hits) do compact[#compact + 1] = {
        source = hit.source, base_lumber_efficiency = hit.base_lumber_efficiency,
        fusion_count = hit.fusion_count, critical_chance_pct = hit.critical_chance_pct,
    } end
    result.hits = compact
    return result
end

local function pure_hit(actor, target, amount, allow_lethal)
    local result = {kind = "native_ApplyDamage_pure", input_damage = amount,
        actor_entindex = actor:entindex(), target_entindex = target:entindex(),
        before_health = target:GetHealth()}
    local ok, value = pcall(ApplyDamage, {attacker = actor, victim = target,
        damage = amount, damage_type = DAMAGE_TYPE_PURE,
        damage_flags = allow_lethal and 0 or (tonumber(DOTA_DAMAGE_FLAG_NON_LETHAL) or 0)})
    result.ok, result.error = ok, not ok and tostring(value) or nil
    result.native_return, result.after_health = ok and tonumber(value) or nil, target:GetHealth()
    result.native_health_loss = result.before_health - result.after_health
    return result
end

function M.result(id) return reports[tostring(id)] end
function M.cancel(id)
    local callback = cancellers[tostring(id)]
    if callback then callback("cancelled_by_test_runner"); return true end
    return false
end

function M.run(card_id, pid, context, options)
    options, pid = options or {}, tonumber(pid) or 0
    sequence = sequence + 1
    local report = {id = "builder_consumer:" .. sequence, card_id = card_id,
        player_id = pid, assertions = {}, resource_events = {}, status = "running",
        started_at = GameRules:GetGameTime(), validation = "live_production_consumer"}
    reports[report.id] = report
    if not IsInToolsMode or not IsInToolsMode() then
        report.status, report.error = "blocked", "requires_tools_mode"; return report
    end
    local card = cards.by_id[card_id]
    if not card or not card.enabled or card.type ~= "builder_start" then
        report.status, report.error = "blocked", "enabled_builder_card_required"; return report
    end
    local ctx, subscriptions, cleanup_hooks = context_for(context), {}, {}
    local function finish(error_code)
        if report.finished then return end
        report.finished, report.finished_at = true, GameRules:GetGameTime()
        cancellers[report.id] = nil
        for _, token in ipairs(subscriptions) do bus.unsubscribe(token) end
        for _, cleanup in ipairs(cleanup_hooks) do
            local ok, why = pcall(cleanup)
            if not ok then
                report.cleanup_errors = report.cleanup_errors or {}
                report.cleanup_errors[#report.cleanup_errors + 1] = tostring(why)
                error_code = error_code or "test_control_restore_failed"
            end
        end
        local failed, passed = false, false
        for _, a in ipairs(report.assertions) do
            failed = failed or a.status == "fail"; passed = passed or a.status == "pass"
        end
        report.status = error_code and "blocked" or failed and "fail"
            or passed and "consumer_pass" or "needs_action"
        report.error = error_code
        report.after_resources = wallet(pid)
        if options.on_complete then pcall(options.on_complete, report) end
    end
    cancellers[report.id] = finish
    report.cancel = nil
    local owned = false
    for _, instance in ipairs(runtime.snapshot(pid)) do
        if instance.card_id == card_id then owned = true end
    end
    report.previously_granted = owned
    report.before_resources = wallet(pid)
    local last_resources = report.before_resources
    subscriptions[#subscriptions + 1] = bus.subscribe(events.RESOURCE_CHANGED, function(payload)
        if tonumber(payload and payload.player_id) ~= pid or report.finished then return end
        local entry = {time = GameRules:GetGameTime(), reason = payload.reason,
            wood_delta = tonumber(payload.wood) and tonumber(last_resources.wood)
                and payload.wood - last_resources.wood,
            gold_delta = tonumber(payload.gold) and tonumber(last_resources.gold)
                and payload.gold - last_resources.gold,
            max_population_delta = tonumber(payload.max_population) and tonumber(last_resources.max_population)
                and payload.max_population - last_resources.max_population}
        last_resources = payload
        if entry.reason == "rogue_reward:" .. tostring(card_id) then
            local wave = request(events.WAVE_STATE_GET_REQUEST, {player_id = pid}) or {}
            entry.current_wave = tonumber(wave.current_wave)
        end
        if #report.resource_events < 256 or entry.reason == "rogue_reward:" .. tostring(card_id) then
            report.resource_events[#report.resource_events + 1] = entry
        end
    end)
    if not owned then
        report.selection = probe.grant(card_id, pid, options)
        if not report.selection or not report.selection.ok then
            finish(report.selection and report.selection.error or "selection_failed"); return report
        end
    else report.selection = {ok = true, via = "already_granted_no_duplicate_selection"} end

    if card_id == "fortified_defense" or card_id == "emergency_reinforcement"
        or card_id == "endless_rebirth" then
        local is_rebirth = card_id == "endless_rebirth"
        local target = is_rebirth and (ctx.boss or ctx.target) or ctx.wall
        local actor = is_rebirth and ctx.hero or (ctx.attacker or ctx.enemy or ctx.hero)
        if not valid(actor) or not valid(target) or not target.SetHealth or not ApplyDamage then
            finish("actual_damage_actor_and_target_required"); return report
        end
        if is_rebirth then
            if owner(actor) ~= pid or not actor.IsRealHero or not actor:IsRealHero()
                or not tostring(target.survival_encounter_id or ""):match("^encounter_rebirth_") then
                finish("actual_owned_real_hero_and_rebirth_encounter_required"); return report
            end
        elseif owner(target) ~= pid or target.survival_building_id ~= "wall" then
            finish("actual_owned_wall_required"); return report
        end
        if actor.GetTeamNumber and target.GetTeamNumber
            and actor:GetTeamNumber() == target:GetTeamNumber() then
            finish("damage_actor_and_target_must_be_enemies"); return report
        end
        local key = is_rebirth and "builder_rebirth_boss_damage_pct"
            or card_id == "fortified_defense" and "builder_wall_damage_reduction_pct"
            or "builder_wall_low_health_reduction_pct"
        local contribution = effect_state.numeric(pid, key)
        if contribution <= 0 then finish("card_projection_unavailable_for_control"); return report end
        local original_health, max_health = target:GetHealth(), target:GetMaxHealth()
        local health_scale = tonumber(target.survival_endless_health_scale) or 1
        local native_amount = math.max(1, math.min(100, max_health * 0.05))
        local logical_amount = tonumber(options.damage) or native_amount * health_scale
        local function restore()
            effect_state.set_numeric(pid, key, contribution)
            if valid(target) then target:SetHealth(math.min(original_health, target:GetMaxHealth())) end
        end
        cleanup_hooks[#cleanup_hooks + 1] = restore
        local low = card_id == "emergency_reinforcement"
        local prepared_health = low and math.max(1, math.floor(max_health * 0.30))
            or math.max(1, math.floor(max_health * 0.75))
        local ok, why = pcall(function()
            target:SetHealth(prepared_health)
            effect_state.set_numeric(pid, key, 0)
            report.without = pure_hit(actor, target, logical_amount)
            effect_state.set_numeric(pid, key, contribution)
            target:SetHealth(prepared_health)
            report.with_card = pure_hit(actor, target, logical_amount)
            local expected
            if is_rebirth then expected = (report.without.native_health_loss or 0) * (1 + contribution / 100)
            else
                local other = math.max(0, tonumber(target.survival_gameplay_damage_reduction_pct) or 0)
                    + (low and effect_state.numeric(pid, "builder_wall_damage_reduction_pct") or 0)
                local block = math.max(0, tonumber(target.survival_gameplay_damage_block) or 0) / health_scale
                if other >= 100 then error("other_wall_reductions_saturated") end
                expected = math.max(0, ((report.without.native_health_loss or 0) + block)
                    / (1 - other / 100) * (1 - (other + contribution) / 100) - block)
                report.other_reduction_pct, report.native_flat_block = other, block
            end
            report.logical_damage, report.expected_damage = logical_amount, expected
            report.target_health_fraction = prepared_health / max_health
            if not report.without.ok or not report.with_card.ok then
                error(report.without.error or report.with_card.error)
            end
            if not report.without.native_health_loss or report.without.native_health_loss <= 0 then
                error("native_damage_control_was_blocked")
            end
            if report.without.native_health_loss >= prepared_health - 1 then
                error("native_control_hit_reached_nonlethal_health_limit")
            end
            local cap = not is_rebirth and effect_state.wall_damage_cap(target)
            if cap and cap > 0 and report.without.native_health_loss
                >= max_health * cap / 100 / health_scale - 0.01 then
                error("existing_wall_damage_cap_masked_control")
            end
            -- This engine's ApplyDamage return can retain the pre-filter input.
            -- Actual native HP loss is the damage consumer evidence.
            report.damage_observation = "native_health_loss_after_actual_ApplyDamage"
            add_check(report, "actual native HP loss consumes selected card", report.with_card.native_health_loss,
                expected, 1.01)
            if low then
                target:SetHealth(math.max(1, math.ceil(max_health * 0.31)))
                report.above_threshold = pure_hit(actor, target, logical_amount)
                add_check(report, "native damage excludes emergency above 30 percent",
                    report.above_threshold.native_health_loss, report.without.native_health_loss, 1.01)
            end
        end)
        report.remaining = {"native forced pure damage verified; ordinary attack animation and encounter fight are separate"}
        report.control_restored = true
        finish(not ok and tostring(why) or nil); return report
    end

    local harvest_cards = {precision_lumber = true, peaceful_labor = true,
        first_to_strike = true, heavy_hand = true}
    if harvest_cards[card_id] then
        local actor = card_id == "first_to_strike" and ctx.hero or ctx.worker
        local ai = valid(actor) and actor:FindModifierByName("modifier_lumberjack_ai") or nil
        local tree = ctx.tree or ai and entity(tonumber(ai.tree_entindex))
        if not valid(actor) or not valid(tree) or tree:GetUnitName() ~= "enemy_tree" then
            finish("real_actor_and_registered_tree_required"); return report
        end
        if owner(actor) ~= pid then
            finish("actor_owner_mismatch"); return report
        end
        if card_id == "heavy_hand" and not actor.survival_super_lumberjack then
            finish("heavy_hand_requires_fused_worker"); return report
        end
        report.actor_entindex, report.tree_entindex = actor:entindex(), tree:entindex()
        local key = card_id == "peaceful_labor" and "builder_peaceful_wood_per_hit"
            or card_id == "first_to_strike" and "builder_hero_wood_bonus_pct"
            or card_id == "heavy_hand" and "builder_super_lumberjack_crit_pct"
        local amount = key and effect_state.numeric(pid, key)
        local previous_efficiency = ai and tonumber(ai.technology_lumber_efficiency)
        local fusion_count = ai and math.max(1, tonumber(ai.fusion_count) or 1) or 1
        if card_id == "heavy_hand" and (tonumber(ai and ai.technology_crit_chance) or 0) >= 100 then
            finish("baseline_critical_chance_saturated"); return report
        end
        local restore
        if card_id == "precision_lumber" and ai and previous_efficiency then
            ai:SetTechnologyLumberEfficiency(math.max(0, previous_efficiency - fusion_count))
            restore = function() ai:SetTechnologyLumberEfficiency(previous_efficiency) end
        elseif key and amount and amount > 0 then
            effect_state.set_numeric(pid, key, 0)
            restore = function() effect_state.set_numeric(pid, key, amount) end
        end
        if not restore then finish("card_projection_unavailable_for_control"); return report end
        local roll = card_id == "heavy_hand" and
            math.min(99.99, (tonumber(ai and ai.technology_crit_chance) or 0) + amount / 2) or 100
        local initial_fraction = actor.survival_wood_fraction
        local initial_tree_level = tonumber(tree.survival_tree_level or tree.survival_level)
        local ok, why = pcall(function() report.without = harvest(actor, tree, pid, roll) end)
        restore()
        -- A control strike must not shift the fractional carry of the selected
        -- strike. Leave the second strike's real carry in place afterwards.
        actor.survival_wood_fraction = initial_fraction
        report.control_restored = true
        if not ok then finish(tostring(why)); return report end
        report.with_card = harvest(actor, tree, pid, roll)
        report.fraction_control = {before = initial_fraction, after = actor.survival_wood_fraction}
        if initial_tree_level ~= tonumber(tree.survival_tree_level or tree.survival_level) then
            finish("tree_level_changed_between_native_control_strikes"); return report
        end
        if not report.without.ok or not report.with_card.ok then
            finish(report.without.error or report.with_card.error); return report
        end
        if #report.without.hits ~= 1 or #report.with_card.hits ~= 1
            or #report.without.resources ~= 1 or #report.with_card.resources ~= 1 then
            finish("native_contact_did_not_produce_exactly_one_attributed_tree_payout"); return report
        end
        if card_id == "precision_lumber" then
            add_check(report, "real native harvest wood delta", report.with_card.wood - report.without.wood,
                fusion_count * (1 + (tonumber(ai and ai.wood_total_bonus_pct) or 0) / 100
                    + (tonumber(ai and ai.permanent_harvest_bonus_pct) or 0) / 100), 0.99999)
        elseif card_id == "peaceful_labor" then
            add_check(report, "real peaceful native harvest delta", report.with_card.wood - report.without.wood,
                amount * (1 + (tonumber(ai and ai.wood_total_bonus_pct) or 0) / 100
                    + (tonumber(ai and ai.permanent_harvest_bonus_pct) or 0) / 100), 0.99999)
        elseif card_id == "first_to_strike" then
            add_check(report, "hero native tree harvest doubles", report.with_card.wood, report.without.wood * 2)
        else
            add_check(report, "heavy hand native critical payout", report.with_card.wood,
                math.floor(report.without.wood * (2 + (tonumber(ai.critical_yield_bonus_pct) or 0) / 100)))
            report.remaining = {"probability distribution needs statistical sampling; control used a boundary RNG"}
        end
        finish(); return report
    end

    local target_samples = math.max(1, tonumber(options.samples) or 3)
    local deadline = tonumber(options.timeout_seconds) or 18
    local city, mine, wall = ctx.city, ctx.mine, ctx.wall
    if card_id == "infrastructure_maniac_start" then
        if not valid(city) or city.survival_building_id ~= "main_city" then
            finish("actual_main_city_required"); return report
        end
        report.quote = request(events.BUILDING_UPGRADE_QUOTE_REQUEST, {
            player_id = pid, building = city, upgrade_mode = "one"})
        report.upgrade = request(events.BUILDING_UPGRADE_REQUEST, {
            player_id = pid, building = city, upgrade_mode = "one", silent_notification = true})
        if not report.upgrade or not report.upgrade.ok then
            finish(report.upgrade and report.upgrade.error or "upgrade_failed"); return report
        end
        report.after_spend = wallet(pid)
        report.paid_wood = tonumber(report.before_resources.wood) and tonumber(report.after_spend.wood)
            and report.before_resources.wood - report.after_spend.wood
        for _, entry in ipairs(report.resource_events) do
            if entry.reason == "upgrade_city" and entry.wood_delta then
                report.spending_event, report.paid_wood = entry, -entry.wood_delta
                break
            end
        end
        deadline = math.max(deadline, (tonumber(report.upgrade.duration) or 0) + 5)
        report.remaining = {"successful upgrade persists; normal cancel/refund path was not replaced"}
    elseif card_id == "gold_mining_secret" then
        if not valid(mine) or mine.survival_building_id ~= "gold_mine" then
            finish("actual_gold_mine_required"); return report
        end
        local list = request(events.BUILDING_LIST_REQUEST, {player_id = pid, building_id = "gold_mine", handles_only = true}) or {}
        local count = 0
        for _, row in ipairs(list.buildings or list) do if valid(row.unit) and row.building_id == "gold_mine" then count = count + 1 end end
        if count == 0 then finish("mine_registry_unavailable_for_attribution"); return report end
        if count > 1 then finish("multiple_mines_make_wallet_event_attribution_ambiguous"); return report end
        target_samples = math.max(10, tonumber(options.samples) or 10)
        local config = require("config/gold_mine_config")
        deadline = tonumber(options.timeout_seconds) or (target_samples + 3) * config.production_interval + 3
        report.mine_entindex = mine:entindex()
    elseif card_id == "wall_recovery" then
        if not valid(wall) or wall.survival_building_id ~= "wall" or owner(wall) ~= pid then
            finish("actual_owned_wall_required"); return report
        end
        report.wall_entindex, report.heal_events, report.armor_events = wall:entindex(), {}, {}
        local old_heal, initial_health = wall.Heal, wall:GetHealth()
        if options.prepare_wall_health == true then
            wall:SetHealth(math.max(1, math.floor(wall:GetMaxHealth() * 0.50)))
            cleanup_hooks[#cleanup_hooks + 1] = function()
                if valid(wall) then wall:SetHealth(math.min(initial_health, wall:GetMaxHealth())) end
            end
        elseif wall:GetMaxHealth() - wall:GetHealth() < target_samples * 20 then
            finish("wall_must_have_missing_health_or_prepare_wall_health_true"); return report
        end
        local wrapper = function(self, amount, caster)
            local caller = debug and debug.getinfo and debug.getinfo(2, "S") or {}
            local before = self:GetHealth()
            local result = old_heal(self, amount, caster)
            if tostring(caller.short_src or caller.source or ""):find("rogue_builder_start_effect_service", 1, true) then
                report.heal_events[#report.heal_events + 1] = {time = GameRules:GetGameTime(),
                    requested = amount, native_health_delta = self:GetHealth() - before,
                    missing_before = self:GetMaxHealth() - before}
            end
            return result
        end
        local installed, install_error = pcall(function() wall.Heal = wrapper end)
        if not installed then finish("native_heal_observation_unavailable:" .. tostring(install_error)); return report end
        cleanup_hooks[#cleanup_hooks + 1] = function()
            if wall.Heal ~= wrapper then error("wall_heal_observer_replaced") end
            wall.Heal = old_heal
        end
        local technology = require("systems/technology_stat_manager")
        local last_armor = tonumber((technology.get(pid).final.wall or {}).technology_armor_bonus) or 0
        report.other_wall_armor_delta = 0
        report.before_wall_snapshot = probe.snapshot(wall, pid)
        subscriptions[#subscriptions + 1] = bus.subscribe(events.TECHNOLOGY_STATS_CHANGED, function(payload)
            if tonumber(payload and payload.player_id) ~= pid or report.finished then return end
            local current = tonumber((((payload.snapshot or {}).final or {}).wall or {}).technology_armor_bonus)
            if current == nil then return end
            if payload.reason == "rogue_reward:wall_recovery" then
                report.armor_events[#report.armor_events + 1] = {time = GameRules:GetGameTime(),
                    technology_armor_delta = current - last_armor,
                    effective_war3_armor_at_emit = tonumber(wall.survival_effective_war3_armor)}
            else
                report.other_wall_armor_delta = report.other_wall_armor_delta + (current - last_armor) * 3
            end
            last_armor = current
        end)
        if options.require_armor_tick == true then deadline = tonumber(options.timeout_seconds) or 70 end
    elseif card_id == "wealthy_start" then
        report.wave_events = {}
        subscriptions[#subscriptions + 1] = bus.subscribe(events.WAVE_CHANGED, function(payload)
            local reason = tostring(payload and payload.reason or "")
            if reason == "wave_started" or reason == "dev_wave_started" or reason == "early_final_started" then
                report.wave_events[#report.wave_events + 1] = {time = GameRules:GetGameTime(),
                    reason = reason, current_wave = tonumber(payload.current_wave)}
            end
        end)
        target_samples = math.max(1, tonumber(options.samples) or 1)
        report.remaining = {"requires a real subsequent wave start; helper does not fabricate WAVE_CHANGED"}
    elseif card_id == "woodcutting_bounty" then
        report.kill_events = {}
        local victim, actor = ctx.victim or ctx.target, ctx.attacker or ctx.hero or ctx.worker
        if victim and (not valid(victim) or not
            (victim.survival_is_wave_monster == true or victim.survival_is_challenge_monster == true)) then
            finish("actual_wave_or_challenge_victim_required"); return report
        end
        subscriptions[#subscriptions + 1] = bus.subscribe(events.ENGINE_ENTITY_KILLED, function(payload)
            if not payload or victim and payload.victim ~= victim then return end
            local killed = payload.victim
            if not killed or killed:IsNull() or not (killed.survival_is_wave_monster == true
                or killed.survival_is_challenge_monster == true) then return end
            local actor_pid = tonumber(payload.player_id) or owner(payload.attacker)
            if actor_pid ~= pid then return end
            local wave = request(events.WAVE_STATE_GET_REQUEST, {player_id = pid}) or {}
            report.kill_events[#report.kill_events + 1] = {time = GameRules:GetGameTime(),
                victim_entindex = killed:entindex(), current_wave = tonumber(wave.current_wave)}
        end)
        target_samples = math.max(1, tonumber(options.samples) or 1)
        if options.kill_victim == true then
            if not valid(actor) or owner(actor) ~= pid or not valid(victim)
                or actor:GetTeamNumber() == victim:GetTeamNumber() then
                finish("actual_owned_killer_and_enemy_victim_required"); return report
            end
            local wave = request(events.WAVE_STATE_GET_REQUEST, {player_id = pid}) or {}
            if (tonumber(wave.current_wave) or 0) <= 0 then
                finish("positive_current_wave_required_for_bounty"); return report
            end
            report.native_kill = pure_hit(actor, victim,
                math.max(victim:GetHealth(), victim:GetMaxHealth()) * 100
                    * (tonumber(victim.survival_endless_health_scale) or 1), true)
            if not report.native_kill.ok then finish(report.native_kill.error); return report end
        end
        report.remaining = {"requires a real wave/challenge death; native kill is opt-in and permanently removes the supplied enemy"}
    elseif card_id ~= "natures_gift" then
        finish("consumer_action_not_implemented_use_native_probe"); return report
    end

    local mode, end_at = GameRules:GetGameModeEntity(), GameRules:GetGameTime() + deadline
    mode:SetContextThink("BuilderRogueConsumer_" .. sequence, function()
        if report.finished then return nil end
        local relevant = {}
        for _, entry in ipairs(report.resource_events) do
            if entry.reason == "rogue_reward:" .. card_id
                or card_id == "gold_mining_secret" and
                    (entry.reason == "gold_mine_income" or entry.reason == "gold_mine_critical_income") then
                relevant[#relevant + 1] = entry
            end
        end
        if card_id == "wall_recovery" and #report.heal_events >= target_samples
            and (options.require_armor_tick ~= true or #report.armor_events > 0) then
            for i = 1, target_samples do
                local heal = report.heal_events[i]
                add_check(report, "actual wall recovery native heal " .. i, heal.native_health_delta,
                    math.min(20, heal.missing_before), 1.001)
            end
            report.after_wall_snapshot = probe.snapshot(wall, pid)
            if #report.armor_events > 0 then
                add_check(report, "actual 60-second technology War3 armor contribution",
                    report.armor_events[1].technology_armor_delta * 3, 1)
                add_check(report, "actual 60-second wall effective War3 armor delta",
                    report.after_wall_snapshot.effective_war3_armor
                        and report.before_wall_snapshot.effective_war3_armor
                        and report.after_wall_snapshot.effective_war3_armor
                            - report.before_wall_snapshot.effective_war3_armor
                            - report.other_wall_armor_delta, 1)
            end
            if options.require_armor_tick ~= true then report.remaining = {"60-second armor tick not awaited"} end
            finish(); return nil
        elseif card_id == "wealthy_start" and #relevant >= target_samples
            and #report.wave_events >= target_samples then
            for i = 1, target_samples do
                add_check(report, "actual wave-start wallet gold " .. i, relevant[i].gold_delta,
                    30 * report.wave_events[i].current_wave)
            end
            finish(); return nil
        elseif card_id == "woodcutting_bounty" and #relevant >= target_samples
            and #report.kill_events >= target_samples then
            for i = 1, target_samples do
                add_check(report, "actual monster-kill wallet wood " .. i, relevant[i].wood_delta,
                    5 * (relevant[i].current_wave or report.kill_events[i].current_wave))
            end
            finish(); return nil
        elseif card_id == "infrastructure_maniac_start" and #relevant > 0 then
            report.refund = relevant[1]
            add_check(report, "actual completed main-city wood refund", report.refund.wood_delta, report.paid_wood)
            add_check(report, "no gold refund", report.refund.gold_delta, 0)
            finish(); return nil
        elseif card_id == "natures_gift" and #relevant >= target_samples then
            for i = 1, target_samples do add_check(report, "actual one-second wood tick " .. i, relevant[i].wood_delta, 3) end
            finish(); return nil
        elseif card_id == "gold_mining_secret" and #relevant >= target_samples then
            local config = require("config/gold_mine_config")
            local technology = require("systems/technology_stat_manager").get(pid).final.gold_mine or {}
            local profile = request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, {player_id = pid}) or {}
            local permanent = profile.totals or {}
            local research = request(events.TECHNOLOGY_STATE_GET_REQUEST, {player_id = pid}) or {}
            local level = tonumber(mine.survival_level) or tonumber(options.mine_level) or 1
            local percent = (tonumber(technology.income_bonus_pct) or 0)
                + (tonumber(permanent.gold_mine_efficiency_pct) or 0)
                + (tonumber(permanent.gold_mine_yield_bonus_pct) or 0)
            local expected, actual = 0, 0
            for i = 1, target_samples do
                local base = config.income_amount(level, (research.levels or {}).gold_mine_efficiency or 0,
                    relevant[i].reason == "gold_mine_critical_income")
                expected = expected + math.max(0, (base + (tonumber(permanent.gold_mine_yield_flat) or 0))
                    * (1 + percent / 100) + (tonumber(permanent.gold_mine_final_output_flat) or 0))
                    * (tonumber(mine.survival_commerce_mine_slots) or 1)
                actual = actual + (tonumber(relevant[i].gold_delta) or 0)
            end
            report.income_samples, report.expected_exact, report.actual_paid = relevant, expected, actual
            add_check(report, "actual gold production including fractional carry", actual, expected, 1.00001)
            report.remaining = {"current configured bonus consumed; ten samples allow an unknown initial fractional carry"}
            finish(); return nil
        end
        if GameRules:GetGameTime() >= end_at then finish("real_consumer_timeout"); return nil end
        return 0.05
    end, 0.05)
    return report
end

return M
