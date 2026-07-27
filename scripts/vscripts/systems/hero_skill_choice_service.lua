local event_bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local choice_rules = require("config/generated/hero_skill_choice_rules")
local exclusive = require("config/generated/hero_exclusive_skills")
local heroes = require("config/generated/hero_definitions")

local M = {}

local pending_by_player = {}
local sequence = 0
local reward_retry_by_player = {}

local function state(player_id)
    local result = event_bus.request(
        events.HERO_SKILL_STATE_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or nil
end

local function progression(player_id)
    local result = event_bus.request(
        events.HERO_PROGRESSION_GET_REQUEST,
        { player_id = player_id }
    )
    return result and result.snapshot or {}
end

local function rule_for(level)
    for _, row in ipairs(choice_rules.rows or {}) do
        local minimum = tonumber(row.min_trigger_level) or 0
        local maximum = tonumber(row.max_trigger_level) or 999
        if row.enabled ~= false
            and row.trigger_type == "rebirth_complete"
            and level >= minimum
            and level <= maximum then
            return row
        end
    end
    return nil
end

local function project_pending(player_id)
    local pending = pending_by_player[player_id]
    if not pending then
        return {
            player_id = player_id,
            pending = 0,
            candidates = {},
        }
    end
    return {
        player_id = player_id,
        pending = 1,
        choice_token = pending.token,
        candidates = pending.candidates,
        source = pending.source,
    }
end

local function publish(player_id)
    local data = project_pending(player_id)
    CustomNetTables:SetTableValue(
        "survival_hero_skill_choice",
        "player_" .. tostring(player_id),
        data
    )
    event_bus.emit(events.HERO_SKILL_CHOICE_CHANGED, data)
end

local function create_offer(player_id, source, trigger_level)
    local hero_state = state(player_id)
    if not hero_state or hero_state.hero_ready ~= 1 then
        return { ok = false, error = "combat_hero_not_ready" }
    end

    local level = tonumber(trigger_level)
        or tonumber(progression(player_id).rebirth_level) or 0
    local rule = rule_for(level)
    if not rule then
        return { ok = false, error = "skill_choice_rule_missing" }
    end

    local hero_definition = heroes.by_id[hero_state.hero_id]
    local pool_id = hero_definition
        and hero_definition.public_skill_pool_id
        or rule.pool_id

    local draw = event_bus.request(
        events.HERO_SKILL_POOL_DRAW_REQUEST,
        {
            player_id = player_id,
            pool_id = pool_id,
            choice_count = rule.choice_count,
            rebirth_level = level,
        }
    )
    if not draw or not draw.ok then
        return draw or { ok = false, error = "skill_draw_failed" }
    end

    sequence = sequence + 1
    local token = tostring(player_id)
        .. "_" .. tostring(sequence)
        .. "_" .. tostring(math.floor(GameRules:GetGameTime() * 100))
    pending_by_player[player_id] = {
        token = token,
        candidates = draw.candidates,
        source = source or "rebirth_reward",
    }
    publish(player_id)
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "获得技能三选一，请选择一个技能。",
        level = "info",
    })
    return {
        ok = true,
        choice_token = token,
        candidates = draw.candidates,
    }
end

local function grant_exclusive(player_id)
    local hero_state = state(player_id)
    if not hero_state then
        return { ok = false, error = "combat_hero_not_ready" }
    end

    local definition = heroes.by_id[hero_state.hero_id]
    local group_id = definition
        and definition.exclusive_skill_group_id or ""

    for _, row in ipairs(exclusive.rows or {}) do
        if row.enabled ~= false
            and row.hero_id == hero_state.hero_id
            and (group_id == ""
                or row.exclusive_group_id == group_id)
            and row.guaranteed == true then
            return event_bus.request(
                events.HERO_SKILL_GRANT_REQUEST,
                {
                    player_id = player_id,
                    skill_id = row.skill_id,
                    levels = 1,
                    source = "rebirth_exclusive_reward",
                }
            )
        end
    end
    return { ok = false, error = "exclusive_skill_missing" }
end

local function on_skill_reward(payload)
    local effect = payload.effect or {}
    if effect.effect_type == "grant_exclusive_skill" then
        grant_exclusive(payload.player_id)
    elseif effect.effect_type == "grant_random_skill_or_upgrade" then
        local player_id = tonumber(payload.player_id)
        local trigger_level = tonumber(payload.trigger_level)
            or tonumber(progression(player_id).rebirth_level)
        local result = create_offer(player_id, "rebirth_reward", trigger_level)
        if result and result.ok then return end

        reward_retry_by_player[player_id] = {
            trigger_level = trigger_level,
            attempts = 0,
        }
        scheduler.after(0.1, function()
            local pending = reward_retry_by_player[player_id]
            if not pending or pending_by_player[player_id] then
                reward_retry_by_player[player_id] = nil
                return
            end
            pending.attempts = pending.attempts + 1
            local retry = create_offer(
                player_id,
                "rebirth_reward",
                pending.trigger_level
            )
            if retry and retry.ok then
                reward_retry_by_player[player_id] = nil
                return
            end
            if pending.attempts < 10
                and retry and retry.error == "combat_hero_not_ready" then
                return 0.1
            end
            reward_retry_by_player[player_id] = nil
            local error_message = retry and retry.error
                or result and result.error or "skill_choice_create_failed"
            print(string.format(
                "[HERO_SKILL_CHOICE_CREATE_FAILED] player=%s level=%s error=%s",
                tostring(player_id), tostring(pending.trigger_level),
                tostring(error_message)
            ))
            event_bus.emit(events.UI_NOTIFICATION, {
                player_id = player_id,
                message = "转生技能选择生成失败：" .. tostring(error_message),
                level = "error",
            })
        end, "rebirth_skill_choice_retry:" .. tostring(player_id))
    end
end

local function select_request(payload)
    local player_id = tonumber(payload.player_id)
    local pending = pending_by_player[player_id]
    if not pending then
        return { ok = false, error = "skill_choice_not_pending" }
    end
    if tostring(payload.choice_token or "") ~= pending.token then
        return { ok = false, error = "skill_choice_token_invalid" }
    end

    local skill_id = tostring(payload.skill_id or "")
    local found = false
    for _, candidate in ipairs(pending.candidates) do
        if candidate.skill_id == skill_id then
            found = true
            break
        end
    end
    if not found then
        return { ok = false, error = "skill_not_in_offer" }
    end

    local result = event_bus.request(
        events.HERO_SKILL_GRANT_REQUEST,
        {
            player_id = player_id,
            skill_id = skill_id,
            levels = 1,
            source = "skill_choice",
        }
    )
    if not result or not result.ok then
        return result or { ok = false, error = "skill_grant_failed" }
    end

    pending_by_player[player_id] = nil
    publish(player_id)
    return {
        ok = true,
        skill_id = skill_id,
        skill_result = result,
    }
end

local function get_request(payload)
    return {
        ok = true,
        snapshot = project_pending(tonumber(payload.player_id)),
    }
end

local function create_request(payload)
    return create_offer(
        tonumber(payload.player_id),
        payload.source or "manual_request",
        payload.trigger_level
    )
end

function M.init()
    pending_by_player = {}
    sequence = 0
    reward_retry_by_player = {}
    event_bus.handle_request(
        events.HERO_SKILL_CHOICE_CREATE_REQUEST,
        create_request
    )
    event_bus.handle_request(
        events.HERO_SKILL_CHOICE_GET_REQUEST,
        get_request
    )
    event_bus.handle_request(
        events.HERO_SKILL_CHOICE_SELECT_REQUEST,
        select_request
    )
    event_bus.subscribe(events.HERO_SKILL_REWARD_REQUEST, on_skill_reward)
end

return M
