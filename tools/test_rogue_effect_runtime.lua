package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local effects = {
    { effect_id = "instant", card_id = "instant_card", effect_type = "test_instant",
        execution_mode = "instant_transaction", initial_phase = "active", enabled = true },
    { effect_id = "projection", card_id = "projection_card", effect_type = "test_projection",
        execution_mode = "continuous_projection", initial_phase = "active", enabled = true },
    { effect_id = "timed", card_id = "timed_card", effect_type = "test_timed",
        execution_mode = "timed_state", initial_phase = "active", enabled = true },
    { effect_id = "counter", card_id = "counter_card", effect_type = "test_counter",
        execution_mode = "event_counter", initial_phase = "active", enabled = true },
    { effect_id = "next", card_id = "next_card", effect_type = "test_next",
        execution_mode = "next_matching_event", initial_phase = "active", enabled = true },
    { effect_id = "empty_next", card_id = "empty_next_card", effect_type = "test_empty_next",
        execution_mode = "next_matching_event", initial_phase = "active", enabled = true },
    { effect_id = "phase", card_id = "phase_card", effect_type = "test_phase",
        execution_mode = "phase_transition", initial_phase = "burst", enabled = true },
}
local params = {
    { effect_id = "timed", param_name = "duration_seconds", value_type = "number",
        number_value = 10, enabled = true },
    { effect_id = "counter", param_name = "count", value_type = "number",
        number_value = 2, enabled = true },
    { effect_id = "phase", param_name = "burst.duration_seconds", value_type = "number",
        number_value = 10, enabled = true },
}
local lifecycle = {
    { effect_id = "projection", phase_id = "active", rule_order = 1,
        rule_role = "recompute", event_type = "building_changed", predicate = "owner_matches",
        transition = "none", counter_delta = 0, enabled = true },
    { effect_id = "counter", phase_id = "active", rule_order = 1,
        rule_role = "consume", event_type = "challenge_completed", predicate = "owner_matches",
        transition = "none", counter_delta = -1, enabled = true },
    { effect_id = "next", phase_id = "active", rule_order = 1,
        rule_role = "consume", event_type = "wave_boss_spawned", predicate = "always",
        transition = "none", counter_delta = -1, enabled = true },
    { effect_id = "empty_next", phase_id = "active", rule_order = 1,
        rule_role = "consume", event_type = "wave_boss_spawned", predicate = "always",
        transition = "none", counter_delta = -1, enabled = true },
    { effect_id = "phase", phase_id = "burst", rule_order = 1,
        rule_role = "transition", event_type = "timer_elapsed", predicate = "always",
        transition = "next_phase", counter_delta = 0, enabled = true },
    { effect_id = "phase", phase_id = "permanent", rule_order = 2,
        rule_role = "activate", event_type = "grant_applied", predicate = "always",
        transition = "none", counter_delta = 0, enabled = true },
}

package.preload["config/generated/rogue_reward_effects"] = function() return { rows = effects } end
package.preload["config/generated/rogue_reward_effect_params"] = function() return { rows = params } end
package.preload["config/generated/rogue_reward_effect_lifecycle"] = function()
    return { rows = lifecycle }
end
package.preload["core/scheduler"] = function()
    _G.scheduled = {}
    return { after = function(_, callback, id) scheduled[id] = callback return id end,
        cancel = function(id) scheduled[id] = nil end }
end
package.preload["core/event_bus"] = function()
    return { subscribe = function() return {} end, unsubscribe = function() end,
        request = function() return { ok = true } end }
end
package.preload["systems/player_context_service"] = function()
    return { is_owned_by = function(player_id, unit)
        return unit and unit.player_id == player_id
    end }
end

DOTA_TEAM_GOODGUYS = 2
PlayerResource = {
    GetPlayer = function(_, player_id) return player_id >= 0 and {} or nil end,
    GetTeam = function() return DOTA_TEAM_GOODGUYS end,
}
GameRules = { GetGameTime = function() return 100 end }

local registry = require("systems/rogue_effect_registry")
local applied, removed, recomputed, events_seen, phase_applied = {}, {}, {}, {}, {}
for _, effect_type in ipairs({
    "test_instant", "test_projection", "test_timed", "test_counter", "test_next",
}) do
    registry.register_for_test(effect_type, {
        apply = function(instance)
            applied[instance.effect_instance_id] = (applied[instance.effect_instance_id] or 0) + 1
            return true
        end,
        remove = function(instance) removed[instance.effect_instance_id] = true end,
        recompute = function(instance, payload)
            recomputed[instance.effect_instance_id] = (recomputed[instance.effect_instance_id] or 0) + 1
            local runtime = require("systems/rogue_effect_runtime_service")
            if payload.level < 5 then runtime.bind(instance, payload.target_key)
            else runtime.unbind(instance, payload.target_key) end
        end,
        on_event = function(instance)
            events_seen[instance.effect_instance_id] =
                (events_seen[instance.effect_instance_id] or 0) + 1
            return true
        end,
    })
end
registry.register_for_test("test_phase", {
    apply = function() return true end,
    apply_phase = function(instance) phase_applied[instance.phase_instance_id] = true end,
})
registry.register_for_test("test_empty_next", {
    apply = function(instance)
        instance.complete_on_apply = true
        instance.complete_reason = "no_target"
        return true
    end,
    on_event = function() error("completed empty effect received an event") end,
})

local runtime = require("systems/rogue_effect_runtime_service")
runtime.init()
local function check(value, message) if not value then error(message, 2) end end
local function one(player_id, card_id)
    for _, instance in ipairs(runtime.snapshot(player_id)) do
        if instance.card_id == card_id then return instance end
    end
    return nil
end

local instant = runtime.grant(0, "instant_card", "grant:instant")
check(instant.ok, "instant grant failed")
check(runtime.grant(0, "instant_card", "grant:instant").idempotent,
    "grant idempotency failed")
check(applied[instant.effect_instance_ids[1]] == 1, "instant effect applied twice")
check(not runtime.grant(1, "instant_card", "grant:instant").ok, "grant conflict accepted")

check(runtime.grant(0, "projection_card", "grant:projection").ok, "projection grant failed")
local projection = one(0, "projection_card")
runtime.dispatch("building_changed", { player_id = 1, level = 2, target_key = "tower:1" })
check(next(projection.bindings) == nil, "cross-player projection bound target")
runtime.dispatch("building_changed", { player_id = 0, level = 2, target_key = "tower:1" })
check(next(projection.bindings) ~= nil, "eligible projection target not bound")
runtime.dispatch("building_changed", { player_id = 0, level = 5, target_key = "tower:1" })
check(next(projection.bindings) == nil, "ineligible projection target not unbound")
runtime.dispatch("building_changed", { player_id = 0, level = 3, target_key = "tower:1" })
check(next(projection.bindings) ~= nil, "projection target did not re-enter")

check(runtime.grant(0, "counter_card", "grant:counter").ok, "counter grant failed")
local counter = one(0, "counter_card")
runtime.dispatch("challenge_completed", { player_id = 1 })
check(counter.counter_remaining == 2, "cross-player counter consumed")
runtime.dispatch("challenge_completed", { player_id = 0 })
check(counter.counter_remaining == 1 and counter.status == "active", "counter first consume failed")
runtime.dispatch("challenge_completed", { player_id = 0 })
check(counter.status == "completed" and removed[counter.effect_instance_id],
    "counter completion cleanup failed")

check(runtime.grant(0, "next_card", "grant:next").ok, "next-event grant failed")
local next_event = one(0, "next_card")
runtime.dispatch("wave_boss_spawned", { is_boss = true })
check(next_event.status == "completed" and events_seen[next_event.effect_instance_id] == 1,
    "next matching event did not consume once")
runtime.dispatch("wave_boss_spawned", { is_boss = true })
check(events_seen[next_event.effect_instance_id] == 1, "completed next-event consumed twice")

check(runtime.grant(0, "empty_next_card", "grant:empty_next").ok,
    "empty next-event grant failed")
local empty_next = one(0, "empty_next_card")
check(empty_next.status == "completed" and empty_next.completed_reason == "no_target",
    "empty next-event effect did not complete on apply")
runtime.dispatch("wave_boss_spawned", { is_boss = true })

check(runtime.grant(0, "timed_card", "grant:timed").ok, "timed grant failed")
local timed = one(0, "timed_card")
check(timed.expires_at == 110 and timed.status == "active", "timed expiry not scheduled")
scheduled[timed.expiry_task_id]()
check(timed.status == "completed" and removed[timed.effect_instance_id],
    "timed state expiry cleanup failed")

check(runtime.grant(0, "phase_card", "grant:phase").ok, "phase grant failed")
local phase = one(0, "phase_card")
local first_phase_instance = phase.phase_instance_id
scheduled[phase.expiry_task_id]()
check(phase.phase_id == "permanent" and phase.phase_instance_id ~= first_phase_instance,
    "phase transition failed")
check(phase_applied[phase.phase_instance_id], "next phase handler not applied")
check(phase.expiry_task_id == nil, "permanent phase inherited burst expiry")

print("ROGUE_EFFECT_RUNTIME_LUA51_PASS")