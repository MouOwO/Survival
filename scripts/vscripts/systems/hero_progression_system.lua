local event_bus = require("core/event_bus")
local events = require("core/events")

local M = {}

local state_by_player = {}

local function new_state(player_id)
    return {
        player_id = player_id,
        rebirth_level = 0,
        all_attributes = 0,
        attack_flat = 0,
        attack_all_attribute_gain = 0,
        split_multishot_unlocked = false,
        multishot_count = 0,
        pending_skill_rewards = {},
        version = 0,
    }
end

local function get_state(player_id)
    if not state_by_player[player_id] then
        state_by_player[player_id] = new_state(player_id)
    end
    return state_by_player[player_id]
end

local function snapshot(player_id)
    local state = get_state(player_id)
    local result = {}
    for key, value in pairs(state) do
        if key == "pending_skill_rewards" then
            result[key] = {}
            for index, item in ipairs(value) do
                result[key][index] = item
            end
        else
            result[key] = value
        end
    end
    return result
end

local function append_skill_reward(state, effect)
    table.insert(state.pending_skill_rewards, {
        effect_type = effect.effect_type,
        value = effect.value or 1,
        value_text = effect.value_text or "",
    })
end

local function apply_effect(state, player_id, effect)
    local effect_type = effect.effect_type
    local value = tonumber(effect.value) or 0

    if effect_type == "set_rebirth_level" then
        state.rebirth_level = math.max(state.rebirth_level, value)
        return
    end
    if effect_type == "add_all_attributes" then
        state.all_attributes = state.all_attributes + value
        return
    end
    if effect_type == "add_attack_flat" then
        state.attack_flat = state.attack_flat + value
        return
    end
    if effect_type == "add_attack_all_attribute_gain" then
        state.attack_all_attribute_gain =
            state.attack_all_attribute_gain + value
        return
    end
    if effect_type == "unlock_split_multishot" then
        state.split_multishot_unlocked = true
        state.multishot_count = math.max(state.multishot_count, 1)
        return
    end
    if effect_type == "add_multishot_count" then
        state.multishot_count = state.multishot_count + value
        return
    end
    if effect_type == "grant_exclusive_skill"
        or effect_type == "grant_random_skill_or_upgrade" then
        append_skill_reward(state, effect)
        event_bus.emit(events.HERO_SKILL_REWARD_REQUEST, {
            player_id = player_id,
            effect = effect,
            trigger_level = state.rebirth_level,
        })
        return
    end
    if effect_type == "grant_skill_points" then
        event_bus.request(events.HERO_SKILL_POINT_GRANT_REQUEST, {
            player_id = player_id,
            points = value,
            source = "rebirth_reward",
        })
    end
end

local function apply_rewards(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end

    local state = get_state(player_id)
    for _, effect in ipairs(payload.effects or {}) do
        if effect.enabled ~= false then
            apply_effect(state, player_id, effect)
        end
    end

    state.version = state.version + 1
    local data = snapshot(player_id)
    data.reason = payload.reason or "reward_applied"
    event_bus.emit(events.HERO_PROGRESSION_CHANGED, data)
    return { ok = true, snapshot = data }
end

local function get_progression(payload)
    local player_id = tonumber(payload.player_id)
    if player_id == nil or player_id < 0 then
        return { ok = false, error = "player_id_invalid" }
    end
    return { ok = true, snapshot = snapshot(player_id) }
end

local function on_hero_ready(payload)
    if payload.player_id == nil or not payload.hero then
        return
    end
    get_state(payload.player_id)
end

local function on_hero_summoned(payload)
    if payload.player_id == nil or not payload.unit then
        return
    end
    get_state(payload.player_id)
end

local function on_attack_landed(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil then return end
    local state = get_state(player_id)
    local gain = tonumber(state.attack_all_attribute_gain) or 0
    if gain <= 0 then return end
    local technology_stat_manager = require("systems/technology_stat_manager")
    local multiplier = technology_stat_manager.training_room_multiplier(
        player_id,
        payload.target
    )
    local amount = gain * multiplier
    state.all_attributes = state.all_attributes + amount
    state.version = state.version + 1
    local data = snapshot(player_id)
    data.reason = "attack_all_attribute_growth"
    event_bus.emit(events.HERO_PROGRESSION_CHANGED, data)
end

function M.init()
    state_by_player = {}
    event_bus.handle_request(
        events.HERO_PROGRESSION_GET_REQUEST,
        get_progression
    )
    event_bus.handle_request(
        events.HERO_PROGRESSION_APPLY_REQUEST,
        apply_rewards
    )
    event_bus.subscribe(events.HERO_READY, on_hero_ready)
    event_bus.subscribe(events.HERO_SUMMONED, on_hero_summoned)
    event_bus.subscribe(events.HERO_MAIN_ATTACK_LANDED, on_attack_landed)
end

return M
