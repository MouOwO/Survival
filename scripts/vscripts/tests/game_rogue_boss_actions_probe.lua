-- Opt-in real-engine probe. Never loaded by addon init. Use only in a local
-- single-player Tools/cheat test match; no archive/payment/network APIs used.
-- Read-only: script require("tests/game_rogue_boss_actions_probe").observe(0)
-- Mutating:  script require("tests/game_rogue_boss_actions_probe").select(0,"fiscal_subsidy",{local_test=true})
local bus = require("core/event_bus")
local events = require("core/events")
local cards = require("config/generated/rogue_reward_cards")
local runtime = require("systems/rogue_effect_runtime_service")
local effect_state = require("systems/rogue_effect_state_service")
local scheduler = require("core/scheduler")
local json = require("core/json_encoder")
local M = {}
local state = _G.SurvivalRogueBossActionsProbeState or {}
_G.SurvivalRogueBossActionsProbeState = state
state.last_selections = state.last_selections or {}
state.infrastructure_watches = state.infrastructure_watches or {}
state.bounty_trials = state.bounty_trials or {}
state.upgrade_trials = state.upgrade_trials or {}
state.last_published = state.last_published or {}
local last_selections, infrastructure_watches, bounty_trials = state.last_selections,
    state.infrastructure_watches, state.bounty_trials
local IDS = {"divine_wish", "command_change", "infrastructure_maniac",
    "radiant_sapling", "fiscal_subsidy", "nuclear_bomb", "bounty_order",
    "construction_order", "internship_certificate", "infrastructure_outsourcing"}
local supported = {}; for _, id in ipairs(IDS) do supported[id] = true end
local function valid(value) return value and not value:IsNull() end
local function encode(value)
    return json.encode(value)
end
local function publish(value)
    if value and value.kind then state.last_published[value.kind] = value end
    print("ROGUE_BOSS_ACTIONS_PROBE " .. encode(value))
    return value
end
local function list(player_id)
    local result = bus.request(events.BUILDING_LIST_REQUEST, {player_id = player_id}) or {}
    return result.buildings or result
end
local function builder(player_id)
    local result = bus.request(events.BUILDER_GET_REQUEST, {player_id = player_id}) or {}
    return result.builder or result.unit
end
local function gate(player_id, options)
    if not IsServer or not IsServer() then return false, "server_only" end
    if not options or options.local_test ~= true then return false, "local_test_option_required" end
    local tools = IsInToolsMode and IsInToolsMode() or false
    local cheats = GameRules.IsCheatMode and GameRules:IsCheatMode() or false
    if not tools and not cheats then return false, "local_tools_or_cheat_match_required" end
    local players = 0
    for id = 0, 63 do
        if PlayerResource:IsValidPlayerID(id) and PlayerResource:GetPlayer(id) then players = players + 1 end
    end
    if players > 1 then return false, "single_player_test_match_required" end
    if player_id == nil or not PlayerResource:GetPlayer(player_id) then return false, "player_missing" end
    return true
end
local function inventory(unit)
    local result = {}
    if not valid(unit) then return result end
    for slot = 0, 15 do
        local item = unit:GetItemInSlot(slot)
        if valid(item) then result[#result + 1] = {slot = slot, item_name = item:GetAbilityName(),
            entindex = item:entindex(), charges = item:GetCurrentCharges()} end
    end
    return result
end
local function selected_state(player_id)
    local state = CustomNetTables:GetTableValue("survival_rogue_reward", tostring(player_id)) or {}
    local history = {}
    for _, item in pairs(state.history or {}) do
        history[#history + 1] = {card_id = item.card_id, parent_card_id = item.parent_card_id, grant_id = item.grant_id}
    end
    return {active = state.active, token = state.token, rerolls_remaining = state.rerolls_remaining, history = history}
end
local function effect_rows(player_id)
    local result = {}
    for _, instance in ipairs(runtime.snapshot(player_id)) do
        result[#result + 1] = {card_id = instance.card_id, effect_id = instance.effect.effect_id,
            effect_instance_id = instance.effect_instance_id, grant_id = instance.grant_id,
            effect_type = instance.effect.effect_type, execution_mode = instance.effect.execution_mode,
            status = instance.status, counter_remaining = instance.counter_remaining,
            created_at = instance.created_at, completed_reason = instance.completed_reason,
            upgrade_remaining = instance.upgrade_remaining,
            upgrade_target_entindex = instance.upgrade_target_entindex}
    end
    return result
end
local function technology_snapshot(player_id)
    local result = bus.request(events.TECHNOLOGY_STATS_GET_REQUEST, {player_id = player_id})
    return result and (result.snapshot or result) or nil
end
function M.observe(player_id, silent)
    player_id = tonumber(player_id) or 0
    local rows = {}
    for _, building in ipairs(list(player_id)) do
        rows[#rows + 1] = {entindex = building.entindex, building_id = building.building_id,
            level = building.level, alive = valid(building.unit) and building.unit:IsAlive(),
            upgrading = valid(building.unit) and building.unit.survival_upgrade_in_progress == true}
    end
    -- Include every card: random wish children may be combat cards outside
    -- this probe's ten explicit action-card selection entries.
    local effects = effect_rows(player_id)
    local team = PlayerResource:GetTeam(player_id)
    local result = {kind = "observe", player_id = player_id,
        game_time = GameRules:GetGameTime(),
        wallet = bus.request(events.RESOURCE_GET_REQUEST, {player_id = player_id}),
        buildings = rows, inventory = inventory(builder(player_id)), effects = effects,
        repairer_junior = bus.request(events.WORKER_TRAINING_GET_REQUEST,
            {player_id = player_id, team = team, training_type = "repairer", training_id = "train_repairer_01"}),
        repairer_senior = bus.request(events.WORKER_TRAINING_GET_REQUEST,
            {player_id = player_id, team = team, training_type = "repairer", training_id = "train_repairer_02"}),
        next_boss_rerolls = effect_state.numeric(player_id, "next_rogue_reroll_count:boss"),
        bounty_remaining = effect_state.numeric(player_id, "building_challenge_reward_doubles"),
        technology = technology_snapshot(player_id),
        reward = selected_state(player_id),
    }
    if silent then return result end
    return publish(result)
end
function M.select(player_id, card_id, options)
    player_id = tonumber(player_id) or 0
    local allowed, err = gate(player_id, options)
    if not allowed then return publish({kind = "select", card_id = card_id, ok = false, error = err}) end
    if not supported[card_id] then return publish({kind = "select", ok = false, error = "not_boss_action_card"}) end
    local card = cards.by_id[card_id]
    if not card or card.enabled == false then return publish({kind = "select", ok = false, error = "disabled_or_missing"}) end
    -- Wish may immediately cause random upgrades and persistent per-match
    -- modifiers. It must be a separate explicitly enabled run after preparing
    -- every prerequisite; no RNG/config override is used here.
    if card_id == "divine_wish" and options.allow_random_children ~= true then
        return publish({kind = "select", card_id = card_id, ok = false, error = "random_children_option_required"})
    end
    local before = M.observe(player_id, true)
    local offer_ids = {card_id}
    for _, row in ipairs(cards.rows) do
        if row.enabled ~= false and row.type == "boss" and row.card_id ~= card_id and #offer_ids < 3 then
            offer_ids[#offer_ids + 1] = row.card_id
        end
    end
    local offer = require("systems/rogue_reward_service").debug_offer(player_id, offer_ids)
    if not offer or not offer.ok then return publish({kind = "select", card_id = card_id, ok = false,
        error = offer and offer.error or "offer_failed"}) end
    local result = bus.request(events.ROGUE_REWARD_SELECT_REQUEST, {player_id = player_id,
        card_id = card_id, token = offer.token, reward_type = "boss"}) or {ok = false, error = "selection_handler_missing"}
    local after = M.observe(player_id, true)
    local verification = {kind = "select", card_id = card_id, ok = result.ok == true,
        grant_id = result.grant_id,
        error = result.error, before = before, after = after, checked = {}}
    if result.ok then
        local checks = verification.checked
        if card_id == "fiscal_subsidy" then
            checks.gold_delta = after.wallet.gold - before.wallet.gold
            checks.matches = checks.gold_delta == 10000
        elseif card_id == "radiant_sapling" then
            checks.wood_delta = after.wallet.wood - before.wallet.wood
            checks.expected = math.floor(before.wallet.wood * 0.20)
            checks.matches = checks.wood_delta == checks.expected
        elseif card_id == "infrastructure_outsourcing" then
            local wave = bus.request(events.WAVE_STATE_GET_REQUEST, {}) or {}
            local difficulty = tonumber(tostring(wave.difficulty_id):match("(%d+)$")) or 0
            checks.gold_delta = after.wallet.gold - before.wallet.gold
            checks.expected = #before.buildings * difficulty * 100
            checks.matches = checks.gold_delta == checks.expected
        elseif card_id == "internship_certificate" then
            checks.junior_delta = (tonumber(after.repairer_junior and after.repairer_junior.max_count) or 0)
                - (tonumber(before.repairer_junior and before.repairer_junior.max_count) or 0)
            checks.matches = checks.junior_delta == 2
        elseif card_id == "bounty_order" then
            checks.counter_delta = after.bounty_remaining - before.bounty_remaining
            checks.matches = checks.counter_delta == 5
        elseif card_id == "command_change" then
            checks.reroll_credit_delta = after.next_boss_rerolls - before.next_boss_rerolls
            checks.matches = checks.reroll_credit_delta == 1
        elseif card_id == "nuclear_bomb" or card_id == "construction_order" then
            local name = card_id == "nuclear_bomb" and "item_survival_rogue_nuclear_bomb" or "item_survival_rogue_building_upgrade"
            local old, new = 0, 0
            for _, item in ipairs(before.inventory) do if item.item_name == name then old = old + 1 end end
            for _, item in ipairs(after.inventory) do if item.item_name == name then new = new + 1 end end
            checks.item_delta = new - old; checks.matches = checks.item_delta == 1
        end
    end
    last_selections[player_id] = last_selections[player_id] or {}
    last_selections[player_id][card_id] = verification
    return publish(verification)
end
local function find_item(player_id, item_name)
    local unit = builder(player_id)
    if not valid(unit) then return nil, nil end
    for slot = 0, 15 do
        local item = unit:GetItemInSlot(slot)
        if valid(item) and item:GetAbilityName() == item_name then return item, unit end
    end
end
function M.use_upgrade(player_id, target_entindex, options)
    player_id = tonumber(player_id) or 0
    local allowed, err = gate(player_id, options)
    if not allowed then return publish({kind = "upgrade_order", ok = false, error = err}) end
    local item, caster = find_item(player_id, "item_survival_rogue_building_upgrade")
    local target = EntIndexToHScript(tonumber(target_entindex) or -1)
    if not valid(item) or not valid(target) then return publish({kind = "upgrade_order", ok = false, error = "item_or_target_missing"}) end
    local filter = item:CastFilterResultTarget(target)
    if filter ~= UF_SUCCESS then return publish({kind = "upgrade_order", ok = false, error = item:GetCustomCastErrorTarget()}) end
    local before = M.observe(player_id, true)
    local query = bus.request(events.BUILDING_QUERY_REQUEST, {entindex = target:entindex()}) or {}
    local trial = {kind = "upgrade_item_settlement", player_id = player_id,
        target_entindex = target:entindex(), item_entindex = item:entindex(),
        baseline_level = tonumber(query.level) or tonumber(target.__building_level)
            or tonumber(target.survival_level),
        item_name = item:GetAbilityName(), baseline_charges = item:GetCurrentCharges(),
        started_at = GameRules:GetGameTime(), before = before,
        boundary = "native_item_target_order_then_real_building_upgrade_consumer"}
    state.upgrade_trials[player_id] = trial
    ExecuteOrderFromTable({UnitIndex = caster:entindex(), OrderType = DOTA_UNIT_ORDER_CAST_TARGET,
        AbilityIndex = item:entindex(), TargetIndex = target:entindex(), PlayerID = player_id, Queue = false})
    scheduler.every(0.25, function()
        local current = bus.request(events.BUILDING_QUERY_REQUEST, {entindex = trial.target_entindex}) or {}
        trial.current_level = tonumber(current.level) or tonumber(target.__building_level)
            or tonumber(target.survival_level)
        local found
        for _, row in ipairs(inventory(caster)) do if row.entindex == trial.item_entindex then found = row end end
        trial.item_removed = found == nil
        trial.charge_consumed = found and found.charges == trial.baseline_charges - 1 or trial.item_removed
        if trial.baseline_level and trial.current_level == trial.baseline_level + 1 and trial.charge_consumed then
            trial.finished = true; trial.ok = true; trial.after = M.observe(player_id, true)
            trial.gold_delta = trial.after.wallet.gold - trial.before.wallet.gold
            trial.wood_delta = trial.after.wallet.wood - trial.before.wallet.wood
            trial.ok = trial.gold_delta >= 0 and trial.wood_delta >= 0
            publish(trial); return false
        end
        if GameRules:GetGameTime() - trial.started_at > (tonumber(options.timeout_seconds) or 30) then
            trial.finished = true; trial.ok = false; trial.error = "native_item_upgrade_timeout"
            trial.after = M.observe(player_id, true); publish(trial); return false
        end
        return true
    end, "rogue_boss_actions_upgrade_item_probe:" .. tostring(player_id))
    return publish({kind = "upgrade_order", ok = true, target_entindex = target:entindex(), item_entindex = item:entindex()})
end
function M.use_nuclear(player_id, options)
    player_id = tonumber(player_id) or 0
    local allowed, err = gate(player_id, options)
    if not allowed then return publish({kind = "nuclear_order", ok = false, error = err}) end
    local item, caster = find_item(player_id, "item_survival_rogue_nuclear_bomb")
    if not valid(item) then return publish({kind = "nuclear_order", ok = false, error = "item_missing"}) end
    local targets = {}
    for _, unit in ipairs(Entities:FindAllByClassname("npc_dota_creature") or {}) do
        if valid(unit) and unit:IsAlive() and unit:GetTeamNumber() == DOTA_TEAM_BADGUYS
            and (unit.survival_is_wave_monster or unit.survival_is_challenge_monster) then
            if unit.survival_rogue_probe ~= true then
                return publish({kind = "nuclear_order", ok = false, error = "non_probe_monsters_present"})
            end
            targets[#targets + 1] = {entindex = unit:entindex(), boss = unit.survival_is_boss == true}
        end
    end
    ExecuteOrderFromTable({UnitIndex = caster:entindex(), OrderType = DOTA_UNIT_ORDER_CAST_NO_TARGET,
        AbilityIndex = item:entindex(), PlayerID = player_id, Queue = false})
    scheduler.after(math.max(0.25, #targets * 0.05 + 0.15), function()
        for _, target in ipairs(targets) do
            local unit = EntIndexToHScript(target.entindex)
            target.alive = valid(unit) and unit:IsAlive()
        end
        publish({kind = "nuclear_settlement", targets = targets, inventory = inventory(caster)})
        return false
    end)
    return publish({kind = "nuclear_order", ok = true, targets = targets})
end

-- Production offer requests inside a real engine session. No fake tokens,
-- manual credit write or card-list/RNG replacement is used. This intentionally
-- leaves an exhausted natural offer open, so the root harness can close the UI
-- or replace it with the next ordinary debug selection.
function M.command_change_trial(player_id, options)
    player_id = tonumber(player_id) or 0
    local allowed, err = gate(player_id, options)
    if not allowed then return publish({kind = "command_change_trial", ok = false, error = err}) end
    local credit = effect_state.numeric(player_id, "next_rogue_reroll_count:boss")
    local before = selected_state(player_id)
    if credit < 1 then return publish({kind = "command_change_trial", ok = false, error = "command_credit_missing"}) end
    if tonumber(before.active) == 1 then return publish({kind = "command_change_trial", ok = false, error = "existing_visible_offer"}) end
    local opened = bus.request(events.ROGUE_REWARD_OPEN_REQUEST,
        {player_id = player_id, reward_type = "boss", source = "rogue_native_selftest"})
    local first = selected_state(player_id)
    local default = tonumber((require("config/generated/rogue_reward_rules").by_id.default_rogue_reward or {}).free_reroll_count) or 1
    local expected = default + credit
    local report = {kind = "command_change_trial", boundary = "production_open_and_reroll_requests_in_real_engine",
        ok = opened and opened.ok == true, credit_before = credit, default_rerolls = default,
        expected_rerolls = expected, first_page = first, rounds = {}}
    report.credit_after_open = effect_state.numeric(player_id, "next_rogue_reroll_count:boss")
    report.ok = report.ok and opened.queued ~= true and tonumber(first.rerolls_remaining) == expected
        and report.credit_after_open == 0
    for index = 1, expected do
        local current = selected_state(player_id)
        local result = bus.request(events.ROGUE_REWARD_REROLL_REQUEST,
            {player_id = player_id, reward_type = "boss", token = current.token})
        local after = selected_state(player_id)
        local round = {index = index, ok = result and result.ok == true,
            remaining = tonumber(after.rerolls_remaining),
            expected_remaining = expected - index,
            credit = effect_state.numeric(player_id, "next_rogue_reroll_count:boss")}
        round.matches = round.ok and round.remaining == round.expected_remaining and round.credit == 0
        report.rounds[#report.rounds + 1] = round
        report.ok = report.ok and round.matches
        if not round.ok then report.error = result and result.error or "reroll_failed" break end
    end
    local final = selected_state(player_id)
    local extra = bus.request(events.ROGUE_REWARD_REROLL_REQUEST,
        {player_id = player_id, reward_type = "boss", token = final.token})
    report.extra_reroll_rejected = not extra or extra.ok ~= true
    report.extra_reroll_error = extra and extra.error
    report.credit_final = effect_state.numeric(player_id, "next_rogue_reroll_count:boss")
    report.ok = report.ok and report.extra_reroll_rejected and report.credit_final == 0
    return publish(report)
end

local function current_infrastructure(player_id)
    local chosen
    for _, instance in ipairs(runtime.snapshot(player_id)) do
        if instance.card_id == "infrastructure_maniac" and (not chosen
            or (tonumber(instance.created_at) or 0) >= (tonumber(chosen.created_at) or 0)) then chosen = instance end
    end
    return chosen
end
local function level_map(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do result[tostring(row.entindex)] = tonumber(row.level) or 0 end
    return result
end
function M.infrastructure_watch(player_id, options)
    player_id = tonumber(player_id) or 0
    local allowed, err = gate(player_id, options)
    if not allowed then return publish({kind = "infrastructure_watch", ok = false, error = err}) end
    local instance = current_infrastructure(player_id)
    if not instance then return publish({kind = "infrastructure_watch", ok = false, error = "card_instance_missing"}) end
    local previous = infrastructure_watches[player_id]
    if previous and not previous.finished then return publish({kind = "infrastructure_watch", ok = false, error = "watch_already_running"}) end
    local selection = last_selections[player_id] and last_selections[player_id].infrastructure_maniac
    local before = selection and selection.before or M.observe(player_id, true)
    local baseline = level_map(before.buildings)
    local watch = {kind = "infrastructure_settlement", player_id = player_id,
        boundary = "real_native_building_upgrade_queue_and_completion_events",
        grant_id = instance.grant_id, started_at = GameRules:GetGameTime(),
        timeout_seconds = tonumber(options.timeout_seconds) or 90,
        before = before, events = {}, ticks = {}}
    infrastructure_watches[player_id] = watch
    local subscription
    local function finish(reason)
        if watch.finished then return end
        watch.finished = true; watch.reason = reason
        bus.unsubscribe(subscription)
        watch.after = M.observe(player_id, true)
        watch.status = instance.status; watch.completed_reason = instance.completed_reason
        watch.remaining = instance.upgrade_remaining
        watch.upgraded_levels = 0
        for _, row in ipairs(watch.after.buildings) do
            local old = baseline[tostring(row.entindex)]
            if old then watch.upgraded_levels = watch.upgraded_levels + math.max(0, (tonumber(row.level) or 0) - old) end
        end
        local expected = math.max(0, tonumber(instance.params.count) or 3)
        watch.expected_upgrades = expected
        watch.completed_event_count = #watch.events
        watch.gold_delta = (tonumber(watch.after.wallet and watch.after.wallet.gold) or 0)
            - (tonumber(before.wallet and before.wallet.gold) or 0)
        watch.wood_delta = (tonumber(watch.after.wallet and watch.after.wallet.wood) or 0)
            - (tonumber(before.wallet and before.wallet.wood) or 0)
        watch.no_resource_spend_observed = watch.gold_delta >= 0 and watch.wood_delta >= 0
        watch.ok = instance.status == "completed" and (instance.completed_reason == "upgrades_completed"
            and watch.upgraded_levels == expected or instance.completed_reason == "upgrade_candidates_exhausted"
                and watch.upgraded_levels <= expected)
            and watch.no_resource_spend_observed
        if instance.completed_reason == "upgrade_candidates_exhausted" then
            local quotes = {}
            for _, row in ipairs(list(player_id)) do
                local kind = row.building_id == "gold_mine" and events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST
                    or events.BUILDING_UPGRADE_QUOTE_REQUEST
                local quote = bus.request(kind, {player_id = player_id, building = row.unit,
                    entindex = row.entindex, upgrade_mode = "one", reason = "rogue_native_selftest"})
                quotes[#quotes + 1] = {entindex = row.entindex, building_id = row.building_id,
                    ok = quote and quote.ok == true, error = quote and quote.error}
                if quote and quote.ok == true then watch.ok = false end
            end
            watch.exhaustion_quotes = quotes
        end
        publish(watch)
    end
    subscription = bus.subscribe(events.BUILDING_CHANGED, function(payload)
        if tonumber(payload.player_id) ~= player_id or not tostring(payload.reason or ""):find("upgraded", 1, true) then return end
        watch.events[#watch.events + 1] = {entindex = payload.entindex,
            building_id = payload.building_id, level = payload.level, reason = payload.reason,
            at = GameRules:GetGameTime()}
    end)
    scheduler.every(0.25, function()
        local now = GameRules:GetGameTime()
        local previous_tick = watch.ticks[#watch.ticks]
        if not previous_tick or previous_tick.remaining ~= instance.upgrade_remaining
            or previous_tick.target_entindex ~= instance.upgrade_target_entindex then
            watch.ticks[#watch.ticks + 1] = {at = now, remaining = instance.upgrade_remaining,
                target_entindex = instance.upgrade_target_entindex, status = instance.status}
        end
        if instance.status == "completed" then finish("settled") return false end
        if now - watch.started_at >= watch.timeout_seconds then finish("timeout") return false end
        return true
    end, "rogue_boss_actions_infrastructure_probe:" .. tostring(player_id))
    return publish({kind = "infrastructure_watch", ok = true, started_at = watch.started_at,
        grant_id = instance.grant_id, remaining = instance.upgrade_remaining,
        baseline_from_pre_selection = selection ~= nil, timeout_seconds = watch.timeout_seconds})
end

local function same_effects(first, second)
    if #(first.effects or {}) ~= #(second.effects or {}) then return false end
    for index, effect in ipairs(first.effects or {}) do
        local other = second.effects[index]
        if not other or effect.effect_type ~= other.effect_type or tonumber(effect.value) ~= tonumber(other.value) then return false end
    end
    return tonumber((first.resources or {}).gold or 0) == tonumber((second.resources or {}).gold or 0)
        and tonumber((first.resources or {}).wood or 0) == tonumber((second.resources or {}).wood or 0)
end
-- Prefer a genuinely registered challenge building. If allow_fixture_building
-- is explicit, construct a temporary native building and inject only its
-- BUILDING_CREATED/DESTROYED registration boundary. The challenge summons,
-- native Kill callbacks, reward services and quota consumption stay real.
function M.bounty_trial(player_id, options)
    player_id = tonumber(player_id) or 0
    local allowed, err = gate(player_id, options)
    if not allowed then return publish({kind = "bounty_trial", ok = false, error = err}) end
    if bounty_trials[player_id] and not bounty_trials[player_id].finished then
        return publish({kind = "bounty_trial", ok = false, error = "trial_already_running"})
    end
    local counter = effect_state.numeric(player_id, "building_challenge_reward_doubles")
    if counter ~= 5 then return publish({kind = "bounty_trial", ok = false,
        error = "requires_exactly_five_bounty_credits", actual = counter}) end
    local challenge_building, fixture, fixture_definition = nil, false, nil
    for _, row in ipairs(list(player_id)) do
        if row.building_id == "building_challenge" and valid(row.unit) and row.unit:IsAlive() then challenge_building = row.unit break end
    end
    if not challenge_building and options.allow_fixture_building == true then
        local owner = builder(player_id)
        if not valid(owner) then return publish({kind = "bounty_trial", ok = false, error = "builder_missing"}) end
        challenge_building = CreateUnitByName("building_challenge", owner:GetAbsOrigin() + Vector(640, 0, 0),
            false, owner, owner, PlayerResource:GetTeam(player_id))
        if valid(challenge_building) then
            fixture = true
            fixture_definition = require("config/buildings_config").building_challenge
            challenge_building.survival_building_id = "building_challenge"
            challenge_building.survival_player_id = player_id
            challenge_building.survival_rogue_probe = true
            challenge_building.survival_level = 1
            challenge_building.__building_level = 1
            challenge_building.survival_route_level = 1
            challenge_building.survival_population_occupied = 0
            challenge_building.survival_display_name = fixture_definition.display_name
            -- Match building_system.public_state's complete event contract.
            -- Other subscribers besides the challenge service consume these
            -- fields, so a reduced registration packet is not sufficient.
            bus.emit(events.BUILDING_CREATED, {building_id = "building_challenge", unit = challenge_building,
                entindex = challenge_building:entindex(), player_id = player_id, team = PlayerResource:GetTeam(player_id),
                definition = fixture_definition, level = 1, absolute_level = 1, route_level = 1,
                population_occupied = 0, display_name = fixture_definition.display_name,
                base_health = challenge_building:GetMaxHealth(),
                runtime_armor = challenge_building:GetPhysicalArmorBaseValue(),
                tower_class_counts = {}, fusion_participated = 0,
                reason = "rogue_native_selftest_fixture_registration"})
        end
    end
    if not valid(challenge_building) then return publish({kind = "bounty_trial", ok = false,
        error = "challenge_building_missing", remaining_verification = "create_registered_challenge_building_or_allow_explicit_fixture"}) end
    local definitions = require("config/generated/building_challenge_definitions")
    local trial = {kind = "bounty_settlement", player_id = player_id,
        boundary = fixture and "injected_native_building_registration_then_real_challenge_spawn_native_death_and_reward_consumers"
            or "registered_real_building_challenge_spawn_native_death_and_reward_consumers",
        fixture_building_registration = fixture, building_entindex = challenge_building:entindex(),
        counter_before = counter, rounds = {}, rewards = {}, ok = true,
        before = M.observe(player_id, true), pending = {}}
    bounty_trials[player_id] = trial
    local reward_subscription, death_subscription, native_listener, current_round
    local function finish(reason, error_code)
        if trial.finished then return end
        trial.finished = true; trial.reason = reason; trial.error = error_code
        if error_code then trial.ok = false end
        bus.unsubscribe(reward_subscription)
        bus.unsubscribe(death_subscription)
        if native_listener and StopListeningToGameEvent then StopListeningToGameEvent(native_listener) end
        scheduler.cancel("rogue_boss_actions_bounty_round:" .. tostring(player_id))
        trial.counter_final = effect_state.numeric(player_id, "building_challenge_reward_doubles")
        trial.after = M.observe(player_id, true)
        trial.ok = trial.ok and #trial.rounds == 6 and trial.counter_final == 0
        if fixture and valid(challenge_building) then
            bus.emit(events.BUILDING_DESTROYED, {building_id = "building_challenge", unit = challenge_building,
                entindex = challenge_building:entindex(), player_id = player_id,
                team = challenge_building:GetTeamNumber(), definition = fixture_definition,
                level = 1, absolute_level = 1, route_level = 1,
                population_occupied = 0, display_name = fixture_definition.display_name,
                base_health = challenge_building:GetMaxHealth(),
                runtime_armor = challenge_building:GetPhysicalArmorBaseValue(),
                tower_class_counts = {}, fusion_participated = 0,
                reason = "rogue_native_selftest_fixture_cleanup"})
            UTIL_Remove(challenge_building)
        end
        publish(trial)
        if type(options.on_complete) == "function" then
            trial.on_complete_called = true
            local callback_ok, callback_error = pcall(options.on_complete, trial)
            if not callback_ok then
                trial.on_complete_error = tostring(callback_error)
                publish({kind = "bounty_probe_callback_error", player_id = player_id,
                    error = trial.on_complete_error})
            end
        end
    end
    reward_subscription = bus.subscribe(events.MONSTER_REWARD_GRANTED, function(payload)
        if not current_round or tonumber(payload.player_id) ~= player_id then return end
        local root = "building_challenge:" .. current_round.challenge_id
        if payload.encounter_id ~= root and payload.encounter_id ~= root .. ":reward_copy" then return end
        local record = {encounter_id = payload.encounter_id, reward_profile_id = payload.reward_profile_id,
            ok = payload.ok == true, effects = payload.effects, resources = payload.resources,
            error = payload.challenge_result and payload.challenge_result.error
                or payload.progression_result and payload.progression_result.error
                or payload.resource_result and payload.resource_result.error}
        current_round.rewards[#current_round.rewards + 1] = record
        trial.rewards[#trial.rewards + 1] = record
    end)
    death_subscription = bus.subscribe(events.ENGINE_ENTITY_KILLED, function(payload)
        if not current_round or tonumber(payload.victim_entindex) ~= current_round.monster_entindex then return end
        current_round.native_death_event = {at = GameRules:GetGameTime(),
            victim_entindex = tonumber(payload.victim_entindex),
            attacker_entindex = valid(payload.attacker) and payload.attacker:entindex() or nil}
    end)
    if ListenToGameEvent then
        native_listener = ListenToGameEvent("entity_killed", function(keys)
            if current_round and tonumber(keys.entindex_killed) == current_round.monster_entindex then
                current_round.direct_native_game_event = {at = GameRules:GetGameTime(),
                    victim_entindex = tonumber(keys.entindex_killed),
                    attacker_entindex = tonumber(keys.entindex_attacker)}
            end
        end, nil)
    end
    local function native_status(unit)
        local result = {exists = valid(unit)}
        if not result.exists then return result end
        for _, method in ipairs({"IsAlive", "GetHealth", "IsInvulnerable", "IsReincarnating"}) do
            if type(unit[method]) == "function" then
                local ok, value = pcall(unit[method], unit)
                if ok then result[method] = value end
            end
        end
        return result
    end
    local function challenge_meta(entindex)
        local service = require("systems/building_challenge_service")
        if not debug or not debug.getupvalue then return nil end
        for index = 1, 80 do
            local name, value = debug.getupvalue(service.init, index)
            if not name then break end
            if name == "monster_meta" then
                local meta = value[entindex]
                return meta and {entindex = meta.entindex, player_id = meta.player_id,
                    status = meta.status, started_at = meta.started_at, lifecycle_id = meta.lifecycle_id,
                    challenge_id = meta.challenge_id} or {present = false}
            end
        end
    end
    local function wall_status()
        for _, row in ipairs(list(player_id)) do
            if row.building_id == "wall" and valid(row.unit) then
                return {entindex = row.entindex, health = row.unit:GetHealth(), maximum = row.unit:GetMaxHealth()}
            end
        end
    end
    local run_round
    run_round = function(index)
        if index > 6 then finish("six_native_death_settlements_completed") return end
        local definition = options.all_categories == true and index <= 5 and definitions.rows[index] or definitions.rows[1]
        local ability = challenge_building:FindAbilityByName(definition.ability_name)
        if not valid(ability) and fixture then
            ability = challenge_building:AddAbility(definition.ability_name)
            if valid(ability) then ability:SetLevel(1) end
        end
        if not valid(ability) then finish("blocked", "challenge_ability_missing:" .. definition.ability_name) return end
        current_round = {index = index, challenge_id = definition.challenge_id, rewards = {},
            before_counter = effect_state.numeric(player_id, "building_challenge_reward_doubles"),
            expected_rewards = index <= 5 and 2 or 1,
            expected_counter = math.max(0, 5 - index),
            started_at = GameRules:GetGameTime(),
            kill_mode = options.kill_mode == "force_kill" and "ForceKill(false)" or "Kill(nil, registered_builder)"}
        trial.current_round = current_round
        local result = bus.request(events.BUILDING_CHALLENGE_SUMMON_REQUEST, {
            player_id = player_id, building = challenge_building, building_entindex = challenge_building:entindex(),
            challenge_id = definition.challenge_id, source_ability = ability})
        if not result or not result.ok or not valid(result.unit) then
            finish("blocked", result and result.error or "native_challenge_spawn_failed") return
        end
        current_round.wave_number = result.wave_number
        current_round.monster_entindex = result.unit:entindex()
        current_round.before_meta = challenge_meta(current_round.monster_entindex)
        current_round.before_wall = wall_status()
        result.unit.survival_rogue_probe = true
        local monster = result.unit
        current_round.before_native_kill = native_status(monster)
        local kill_ok, kill_error
        if options.kill_mode == "force_kill" then kill_ok, kill_error = pcall(monster.ForceKill, monster, false)
        else kill_ok, kill_error = pcall(monster.Kill, monster, nil, builder(player_id)) end
        current_round.kill_call_ok = kill_ok
        current_round.kill_call_error = not kill_ok and tostring(kill_error) or nil
        if not kill_ok then finish("blocked", "native_kill_call_failed:" .. tostring(kill_error)) return end
        current_round.after_native_kill = native_status(monster)
        -- Native death and the downstream reward dispatch can arrive after
        -- the kill call returns. Wait for their actual events and quota state,
        -- rather than turning a fixed 0.4-second snapshot into a failed card.
        scheduler.every(0.05, function()
            local round = current_round
            round.after_counter = effect_state.numeric(player_id, "building_challenge_reward_doubles")
            round.waited_seconds = GameRules:GetGameTime() - round.started_at
            local settled = #round.rewards >= round.expected_rewards and round.after_counter == round.expected_counter
            if not settled and round.waited_seconds < (tonumber(options.reward_timeout_seconds) or 10) then
                return true
            end
            round.final_native_state = native_status(monster)
            round.final_meta = challenge_meta(round.monster_entindex)
            round.final_wall = wall_status()
            round.matches = #round.rewards == round.expected_rewards and round.after_counter == round.expected_counter
            for _, reward in ipairs(round.rewards) do if not reward.ok then round.matches = false end end
            if index <= 5 and #round.rewards == 2 then
                round.identical_copy = round.rewards[1].reward_profile_id == round.rewards[2].reward_profile_id
                    and same_effects(round.rewards[1], round.rewards[2])
                round.matches = round.matches and round.identical_copy
            end
            trial.rounds[#trial.rounds + 1] = round
            trial.ok = trial.ok and round.matches
            publish({kind = "bounty_round", player_id = player_id, boundary = trial.boundary, round = round})
            if not round.matches then
                local why = round.direct_native_game_event and not round.native_death_event
                    and "native_entity_killed_not_routed_to_production_bus"
                    or not round.direct_native_game_event and not round.native_death_event and "native_death_event_not_observed"
                    or #round.rewards == 0 and "native_challenge_reward_event_not_observed"
                    or "native_reward_count_or_quota_mismatch"
                finish("timeout_or_mismatch", why); return false
            end
            run_round(index + 1)
            return false
        end, "rogue_boss_actions_bounty_round:" .. tostring(player_id))
    end
    scheduler.after(0.05, function() run_round(1) return false end)
    return publish({kind = "bounty_trial", ok = true, started = true, boundary = trial.boundary,
        category_mode = options.all_categories == true and "five_categories_plus_sixth" or "six_mountain_giant_waves",
        fixture_building_registration = fixture, building_entindex = trial.building_entindex})
end

function M.divine_child_observe(player_id, options)
    player_id = tonumber(player_id) or 0
    local selection = last_selections[player_id] and last_selections[player_id].divine_wish
    local grant_id = options and options.grant_id or selection and selection.grant_id
    if not grant_id then
        local newest = -1
        for _, instance in ipairs(runtime.snapshot(player_id)) do
            if instance.card_id == "divine_wish" then
                local index = tonumber(tostring(instance.effect_instance_id):match("(%d+)$")) or 0
                if index > newest then newest = index; grant_id = instance.grant_id end
            end
        end
    end
    if not grant_id then return publish({kind = "divine_children", ok = false, error = "wish_grant_missing"}) end
    local prefix = grant_id .. ":child:"
    local children, by_id = {}, {}
    for _, instance in ipairs(runtime.snapshot(player_id)) do
        if tostring(instance.grant_id):sub(1, #prefix) == prefix then
            local item = by_id[instance.card_id]
            if not item then
                item = {card_id = instance.card_id, grant_id = instance.grant_id, effects = {}}
                by_id[instance.card_id] = item; children[#children + 1] = item
            end
            item.effects[#item.effects + 1] = {effect_id = instance.effect.effect_id,
                effect_type = instance.effect.effect_type, execution_mode = instance.effect.execution_mode,
                status = instance.status, counter_remaining = instance.counter_remaining,
                upgrade_remaining = instance.upgrade_remaining, completed_reason = instance.completed_reason}
        end
    end
    local rows = effect_rows(player_id)
    local result = {kind = "divine_children", grant_id = grant_id, player_id = player_id,
        ok = #children == 3, unique_child_count = #children, children = children,
        all_runtime_effects = rows, all_runtime_effect_count = #rows,
        snapshot = M.observe(player_id, true),
        boundary = "real_random_selection_and_production_runtime_observation",
        child_behavior_verification = "runtime_applied_is_not_a_substitute_for_each_child_card_native_consumer_test"}
    return publish(result)
end

-- Exercise the granted slots through the ordinary training request without
-- free-recruit flags or currency overrides. This is a synchronous native
-- worker path; it leaves the trained units alive in the isolated test match.
function M.internship_capacity_trial(player_id, options)
    player_id = tonumber(player_id) or 0
    local allowed, err = gate(player_id, options)
    if not allowed then return publish({kind = "internship_capacity_trial", ok = false, error = err}) end
    local before = M.observe(player_id, true)
    local progress = before.repairer_junior or {}
    local maximum = tonumber(progress.max_count)
    if maximum ~= 7 then return publish({kind = "internship_capacity_trial", ok = false,
        error = "requires_granted_junior_capacity_seven", actual = maximum}) end
    local city
    for _, row in ipairs(list(player_id)) do
        if row.building_id == "main_city" and valid(row.unit) and row.unit:IsAlive() then city = row.unit break end
    end
    if not valid(city) then return publish({kind = "internship_capacity_trial", ok = false, error = "city_missing"}) end
    local result = {kind = "internship_capacity_trial", player_id = player_id,
        boundary = "ordinary_paid_worker_training_requests_and_native_spawn",
        maximum = maximum, before_count = tonumber(progress.count) or 0, rounds = {}, ok = true}
    for index = result.before_count + 1, maximum do
        local training = bus.request(events.WORKER_TRAIN_REQUEST, {
            city = city, player_id = player_id, training_id = "train_repairer_01"}) or {}
        local after = M.observe(player_id, true)
        local spawned = training.unit or training.entindex and EntIndexToHScript(tonumber(training.entindex))
        local native_alive = valid(spawned) and spawned:IsAlive()
        result.rounds[#result.rounds + 1] = {ordinal = index, ok = training.ok == true,
            error = training.error, entindex = training.entindex,
            native_alive = native_alive == true,
            native_player_id = native_alive and spawned.survival_player_id or nil,
            actual_count = after.repairer_junior and after.repairer_junior.count}
        if not training.ok or not native_alive or tonumber(spawned.survival_player_id) ~= player_id
            or tonumber(after.repairer_junior and after.repairer_junior.count) ~= index then
            result.ok = false; result.error = training.error or "native_worker_count_mismatch"; break
        end
    end
    local after_training = M.observe(player_id, true)
    if result.ok then
        local blocked = bus.request(events.WORKER_TRAIN_REQUEST, {
            city = city, player_id = player_id, training_id = "train_repairer_01"}) or {}
        local after_blocked = M.observe(player_id, true)
        result.eighth_request = {ok = blocked.ok == true, error = blocked.error,
            actual_count = after_blocked.repairer_junior and after_blocked.repairer_junior.count,
            resource_unchanged = after_blocked.wallet.gold == after_training.wallet.gold
                and after_blocked.wallet.wood == after_training.wallet.wood
                and after_blocked.wallet.population == after_training.wallet.population}
        result.ok = not blocked.ok and tonumber(result.eighth_request.actual_count) == maximum
            and result.eighth_request.resource_unchanged
    end
    result.after_count = after_training.repairer_junior and after_training.repairer_junior.count
    result.senior_unchanged = (after_training.repairer_senior or {}).max_count == (before.repairer_senior or {}).max_count
    result.paid_wood = before.wallet.wood - after_training.wallet.wood
    result.paid_gold = before.wallet.gold - after_training.wallet.gold
    result.population_added = after_training.wallet.population - before.wallet.population
    local trained = #result.rounds
    result.normal_costs = result.paid_wood == trained * (tonumber(progress.wood_cost) or 0)
        and result.paid_gold == trained * (tonumber(progress.gold_cost) or 0)
        and result.population_added == trained * (tonumber(progress.population_cost) or 0)
    result.ok = result.ok and result.senior_unchanged and result.normal_costs
    return publish(result)
end

local function copy_keys(target, source)
    for key, value in pairs(source or {}) do target[key] = value end
end
local function upvalue_table(fn, wanted)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    for index = 1, 80 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted and type(value) == "table" then return value end
    end
end
-- Recover a probe already running before this result API was added. The
-- active scheduler closures still mutate the very same report objects; only
-- those object references are copied, so no test or production state resets.
function M.adopt_previous(previous)
    if type(previous) ~= "table" then return {ok = false, error = "previous_probe_missing"} end
    copy_keys(last_selections, upvalue_table(previous.select, "last_selections"))
    copy_keys(infrastructure_watches, upvalue_table(previous.infrastructure_watch, "infrastructure_watches"))
    copy_keys(bounty_trials, upvalue_table(previous.bounty_trial, "bounty_trials"))
    return {ok = true, selection_players = last_selections[0] and 1 or 0,
        infrastructure_recovered = infrastructure_watches[0] ~= nil,
        bounty_recovered = bounty_trials[0] ~= nil}
end
local function compact_report(report)
    if not report then return nil end
    local result = {}
    for _, key in ipairs({"kind", "player_id", "boundary", "finished", "ok", "reason", "error",
        "status", "completed_reason", "remaining", "upgraded_levels", "expected_upgrades",
        "completed_event_count", "gold_delta", "wood_delta", "no_resource_spend_observed",
        "fixture_building_registration", "building_entindex", "counter_before", "counter_final",
        "baseline_level", "current_level", "target_entindex", "item_entindex", "item_removed", "charge_consumed",
        "on_complete_called", "on_complete_error"}) do
        result[key] = report[key]
    end
    result.events = report.events
    result.ticks = report.ticks
    result.exhaustion_quotes = report.exhaustion_quotes
    if report.current_round and not report.finished then
        local round = report.current_round
        result.current_round = {index = round.index, challenge_id = round.challenge_id,
            monster_entindex = round.monster_entindex, reward_count = #(round.rewards or {}),
            after_counter = round.after_counter, waited_seconds = round.waited_seconds,
            before_native_kill = round.before_native_kill, after_native_kill = round.after_native_kill,
            native_death_event = round.native_death_event, direct_native_game_event = round.direct_native_game_event}
    end
    if report.rounds then
        result.rounds = {}
        for _, round in ipairs(report.rounds) do result.rounds[#result.rounds + 1] = {
            index = round.index, challenge_id = round.challenge_id, wave_number = round.wave_number,
            monster_entindex = round.monster_entindex, before_counter = round.before_counter,
            after_counter = round.after_counter, expected_counter = round.expected_counter,
            reward_count = #(round.rewards or {}), expected_rewards = round.expected_rewards,
            identical_copy = round.identical_copy, matches = round.matches,
            kill_mode = round.kill_mode, waited_seconds = round.waited_seconds,
            before_native_kill = round.before_native_kill, after_native_kill = round.after_native_kill,
            final_native_state = round.final_native_state, native_death_event = round.native_death_event,
            direct_native_game_event = round.direct_native_game_event,
            kill_call_ok = round.kill_call_ok, kill_call_error = round.kill_call_error,
            before_meta = round.before_meta, final_meta = round.final_meta,
            before_wall = round.before_wall, final_wall = round.final_wall} end
    end
    return result
end
-- Read-only and non-printing; the root harness can encode a short completion
-- packet even if the original full console report was lost or truncated.
function M.results(player_id, full)
    player_id = tonumber(player_id) or 0
    local selections = {}
    for card_id, selection in pairs(last_selections[player_id] or {}) do
        selections[card_id] = full and selection or {ok = selection.ok, error = selection.error,
            grant_id = selection.grant_id, checked = selection.checked}
    end
    return {player_id = player_id, selections = selections,
        infrastructure = full and infrastructure_watches[player_id] or compact_report(infrastructure_watches[player_id]),
        bounty = full and bounty_trials[player_id] or compact_report(bounty_trials[player_id]),
        upgrade_item = full and state.upgrade_trials[player_id] or compact_report(state.upgrade_trials[player_id]),
        command_change = state.last_published.command_change_trial,
        internship_capacity = state.last_published.internship_capacity_trial,
        divine_children = full and state.last_published.divine_children or nil}
end
-- For a native item cast which completed before the result API existed,
-- compare the caller's recorded before-cast level against authoritative state
-- now, and confirm the specific granted item left the builder's inventory.
function M.capture_upgrade_result(player_id, target_entindex, options)
    player_id = tonumber(player_id) or 0; options = options or {}
    local target = EntIndexToHScript(tonumber(target_entindex) or -1)
    if not valid(target) then return {ok = false, error = "target_missing"} end
    local selection = last_selections[player_id] and last_selections[player_id].construction_order
    local baseline = tonumber(options.baseline_level)
    if not baseline and selection then
        for _, row in ipairs(selection.after.buildings or {}) do
            if row.entindex == tonumber(target_entindex) then baseline = tonumber(row.level) end
        end
    end
    local item_entindex = tonumber(options.item_entindex)
    if not item_entindex and selection then
        for _, row in ipairs(selection.after.inventory or {}) do
            if row.item_name == "item_survival_rogue_building_upgrade" then item_entindex = row.entindex end
        end
    end
    local query = bus.request(events.BUILDING_QUERY_REQUEST, {entindex = target:entindex()}) or {}
    local level = tonumber(query.level) or tonumber(target.__building_level) or tonumber(target.survival_level)
    local present = false
    for _, row in ipairs(inventory(builder(player_id))) do if row.entindex == item_entindex then present = true end end
    local result = {kind = "upgrade_item_settlement", player_id = player_id, finished = true,
        target_entindex = target:entindex(), item_entindex = item_entindex,
        baseline_level = baseline, current_level = level, item_removed = not present,
        boundary = "root_recorded_before_cast_native_state_compared_to_current_authoritative_state",
        ok = baseline ~= nil and level == baseline + 1 and item_entindex ~= nil and not present}
    state.upgrade_trials[player_id] = result
    return result
end
M.card_ids = IDS
return M
