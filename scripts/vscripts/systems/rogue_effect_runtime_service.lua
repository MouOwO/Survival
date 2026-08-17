local event_bus = require("core/event_bus")
local scheduler = require("core/scheduler")
local effect_config = require("config/generated/rogue_reward_effects")
local param_config = require("config/generated/rogue_reward_effect_params")
local lifecycle_config = require("config/generated/rogue_reward_effect_lifecycle")
local effect_registry = require("systems/rogue_effect_registry")
local event_registry = require("systems/rogue_event_registry")
local predicate_registry = require("systems/rogue_predicate_registry")
local effect_state = require("systems/rogue_effect_state_service")

local M = {}
local effects_by_card = {}
local params_by_effect = {}
local rules_by_effect = {}
local phases_by_effect = {}
local grants_by_id = {}
local instances_by_id = {}
local instances_by_player = {}
local subscriptions = {}
local next_grant_id = 0
local next_effect_instance_id = 0
local next_phase_instance_id = 0
local next_target_binding_id = 0

local function enabled(row)
    return row and row.enabled ~= false
end

local function now()
    if GameRules and GameRules.GetGameTime then return GameRules:GetGameTime() end
    return 0
end

local function parameter_value(row)
    if row.value_type == "number" then return tonumber(row.number_value) end
    if row.value_type == "boolean" then return row.boolean_value == true end
    return row.string_value
end

local function rebuild_config()
    effects_by_card, params_by_effect, rules_by_effect, phases_by_effect = {}, {}, {}, {}
    for _, row in ipairs(effect_config.rows or {}) do
        effects_by_card[row.card_id] = effects_by_card[row.card_id] or {}
        effects_by_card[row.card_id][#effects_by_card[row.card_id] + 1] = row
    end
    for _, row in ipairs(param_config.rows or {}) do
        if enabled(row) then
            params_by_effect[row.effect_id] = params_by_effect[row.effect_id] or {}
            params_by_effect[row.effect_id][row.param_name] = parameter_value(row)
        end
    end
    for _, row in ipairs(lifecycle_config.rows or {}) do
        if enabled(row) then
            rules_by_effect[row.effect_id] = rules_by_effect[row.effect_id] or {}
            rules_by_effect[row.effect_id][#rules_by_effect[row.effect_id] + 1] = row
            phases_by_effect[row.effect_id] = phases_by_effect[row.effect_id] or {}
            local phases = phases_by_effect[row.effect_id]
            local present = false
            for _, phase in ipairs(phases) do
                if phase == row.phase_id then present = true break end
            end
            if not present then phases[#phases + 1] = row.phase_id end
        end
    end
    for _, rules in pairs(rules_by_effect) do
        table.sort(rules, function(a, b)
            return (tonumber(a.rule_order) or 0) < (tonumber(b.rule_order) or 0)
        end)
    end
end

local function new_phase(instance, phase_id)
    next_phase_instance_id = next_phase_instance_id + 1
    instance.phase_id = phase_id
    instance.phase_instance_id = "phase:" .. tostring(next_phase_instance_id)
    instance.phase_started_at = now()
end

local function cancel_expiry(instance)
    if instance.expiry_task_id then scheduler.cancel(instance.expiry_task_id) end
    instance.expiry_task_id = nil
end

local function deactivate(instance, reason)
    if instance.status ~= "active" then return end
    cancel_expiry(instance)
    local handler = effect_registry.get(instance.effect.effect_type)
    if handler and handler.remove then handler.remove(instance, reason) end
    instance.bindings = {}
    instance.status = "completed"
    instance.completed_reason = reason or "completed"
end

local function schedule_expiry(instance)
    local duration = tonumber(instance.params[
        tostring(instance.phase_id) .. ".duration_seconds"
    ]) or tonumber(instance.params.duration_seconds)
    if not duration or duration <= 0 then return end
    instance.expires_at = now() + duration
    instance.expiry_task_id = "rogue_effect_expire:" .. instance.effect_instance_id
    scheduler.after(duration, function()
        if instance.status ~= "active" then return false end
        if instance.effect.execution_mode == "phase_transition" then
            M.dispatch("timer_elapsed", {
                player_id = instance.player_id,
                effect_instance_id = instance.effect_instance_id,
            })
        else
            deactivate(instance, "timer_elapsed")
        end
        return false
    end, instance.expiry_task_id)
end

local function apply_instance(instance)
    local handler = effect_registry.get(instance.effect.effect_type)
    if not handler or not handler.apply then return false, "effect_handler_missing" end
    local ok, error_code = handler.apply(instance)
    if not ok then return false, error_code or "effect_apply_failed" end
    if instance.complete_on_apply == true then
        instance.status = "completed"
        instance.completed_reason = instance.complete_reason or "completed_on_apply"
    elseif instance.effect.execution_mode == "instant_transaction" then
        instance.status = "completed"
        instance.completed_reason = "instant_applied"
    else
        instance.status = "active"
        schedule_expiry(instance)
    end
    return true
end

local function create_instance(grant, effect)
    next_effect_instance_id = next_effect_instance_id + 1
    local instance = {
        grant_id = grant.grant_id,
        effect_instance_id = "effect:" .. tostring(next_effect_instance_id),
        player_id = grant.player_id,
        card_id = grant.card_id,
        effect = effect,
        params = params_by_effect[effect.effect_id] or {},
        status = "pending",
        counter_remaining = tonumber((params_by_effect[effect.effect_id] or {}).count),
        bindings = {},
        created_at = now(),
    }
    new_phase(instance, effect.initial_phase or "active")
    return instance
end

local function matching_rule(instance, rule, event_type, payload)
    if instance.status ~= "active" or rule.event_type ~= event_type
        or rule.phase_id ~= instance.phase_id then return false end
    if payload and payload.effect_instance_id
        and payload.effect_instance_id ~= instance.effect_instance_id then return false end
    local predicate = predicate_registry.get(rule.predicate)
    return predicate ~= nil and predicate(instance, payload or {}) == true
end

local function transition(instance)
    local phases = phases_by_effect[instance.effect.effect_id] or {}
    local next_phase = nil
    for index, phase in ipairs(phases) do
        if phase == instance.phase_id then next_phase = phases[index + 1] break end
    end
    if not next_phase then deactivate(instance, "phase_sequence_complete") return end
    cancel_expiry(instance)
    local handler = effect_registry.get(instance.effect.effect_type)
    if handler and handler.remove_phase then handler.remove_phase(instance) end
    new_phase(instance, next_phase)
    if handler and handler.apply_phase then handler.apply_phase(instance) end
    schedule_expiry(instance)
end

local function process_rule(instance, rule, payload)
    local handler = effect_registry.get(instance.effect.effect_type)
    if rule.rule_role == "recompute" then
        if handler and handler.recompute then handler.recompute(instance, payload) end
    elseif rule.rule_role == "consume" then
        local accepted = true
        if handler and handler.on_event then accepted = handler.on_event(instance, payload) ~= false end
        if accepted then
            instance.counter_remaining = (instance.counter_remaining or 1)
                + (tonumber(rule.counter_delta) or -1)
            if instance.counter_remaining <= 0 then deactivate(instance, "counter_consumed") end
        end
    elseif rule.rule_role == "expire" then
        deactivate(instance, "lifecycle_expired")
    elseif rule.rule_role == "transition" then
        transition(instance)
    end
end

function M.dispatch(event_type, payload)
    for _, instance in pairs(instances_by_id) do
        for _, rule in ipairs(rules_by_effect[instance.effect.effect_id] or {}) do
            if matching_rule(instance, rule, event_type, payload) then
                process_rule(instance, rule, payload or {})
            end
        end
    end
end

function M.bind(instance_or_id, target_key, metadata)
    local instance = type(instance_or_id) == "table" and instance_or_id
        or instances_by_id[instance_or_id]
    if not instance or instance.status ~= "active" then return nil end
    target_key = tostring(target_key or "")
    for _, binding in pairs(instance.bindings) do
        if binding.target_key == target_key then return binding.target_binding_id end
    end
    next_target_binding_id = next_target_binding_id + 1
    local id = "binding:" .. tostring(next_target_binding_id)
    instance.bindings[id] = {
        target_binding_id = id,
        target_key = target_key,
        metadata = metadata,
    }
    return id
end

function M.unbind(instance_or_id, target_key)
    local instance = type(instance_or_id) == "table" and instance_or_id
        or instances_by_id[instance_or_id]
    if not instance then return false end
    for id, binding in pairs(instance.bindings) do
        if binding.target_key == tostring(target_key or "") then
            instance.bindings[id] = nil
            return true
        end
    end
    return false
end

function M.grant(player_id, card_id, grant_id)
    player_id = tonumber(player_id)
    card_id = tostring(card_id or "")
    if player_id == nil or player_id < 0 or not PlayerResource:GetPlayer(player_id) then
        return { ok = false, error = "player_invalid" }
    end
    if not grant_id or grant_id == "" then
        next_grant_id = next_grant_id + 1
        grant_id = "grant:" .. tostring(player_id) .. ":" .. tostring(next_grant_id)
    end
    grant_id = tostring(grant_id)
    local previous = grants_by_id[grant_id]
    if previous then
        if previous.player_id == player_id and previous.card_id == card_id then
            return { ok = true, idempotent = true, grant_id = grant_id,
                effect_instance_ids = previous.effect_instance_ids }
        end
        return { ok = false, error = "grant_id_conflict" }
    end

    local selected = {}
    for _, effect in ipairs(effects_by_card[card_id] or {}) do
        if enabled(effect) then
            if not effect_registry.get(effect.effect_type) then
                return { ok = false, error = "effect_handler_missing", effect_id = effect.effect_id }
            end
            selected[#selected + 1] = effect
        end
    end
    if #selected == 0 then return { ok = false, error = "card_effect_missing" } end

    local grant = {
        grant_id = grant_id, player_id = player_id, card_id = card_id,
        effect_instance_ids = {}, status = "applying",
    }
    for _, effect in ipairs(selected) do
        local instance = create_instance(grant, effect)
        local ok, error_code = apply_instance(instance)
        if not ok then return { ok = false, error = error_code, effect_id = effect.effect_id } end
        instances_by_id[instance.effect_instance_id] = instance
        instances_by_player[player_id] = instances_by_player[player_id] or {}
        instances_by_player[player_id][instance.effect_instance_id] = instance
        grant.effect_instance_ids[#grant.effect_instance_ids + 1] = instance.effect_instance_id
    end
    grant.status = "applied"
    grants_by_id[grant_id] = grant
    return { ok = true, grant_id = grant_id,
        effect_instance_ids = grant.effect_instance_ids }
end

function M.snapshot(player_id)
    local result = {}
    for _, instance in pairs(instances_by_player[tonumber(player_id)] or {}) do
        result[#result + 1] = instance
    end
    table.sort(result, function(a, b)
        return a.effect_instance_id < b.effect_instance_id
    end)
    return result
end

function M.snapshot_for_effect(effect_type, unit)
    local result = {}
    for _, instance in pairs(instances_by_id) do
        if instance.status == "active"
            and instance.effect.effect_type == tostring(effect_type)
            and (not unit or instance.player_id ~= nil) then
            result[#result + 1] = instance
        end
    end
    return result
end

function M.init()
    for _, subscription in ipairs(subscriptions) do event_bus.unsubscribe(subscription) end
    subscriptions = {}
    grants_by_id, instances_by_id, instances_by_player = {}, {}, {}
    next_grant_id, next_effect_instance_id = 0, 0
    next_phase_instance_id, next_target_binding_id = 0, 0
    effect_state.reset()
    rebuild_config()
    local subscribed = {}
    for _, rules in pairs(rules_by_effect) do
        for _, rule in ipairs(rules) do
            local core_event = event_registry.core_event(rule.event_type)
            if core_event and not subscribed[core_event] then
                subscribed[core_event] = true
                local event_type = rule.event_type
                subscriptions[#subscriptions + 1] = event_bus.subscribe(core_event, function(payload)
                    M.dispatch(event_type, payload)
                end)
            end
        end
    end
end

M._rebuild_config_for_test = rebuild_config

return M