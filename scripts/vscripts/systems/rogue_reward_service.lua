local event_bus = require("core/event_bus")
local events = require("core/events")
local cards = require("config/generated/rogue_reward_cards")
local rules_config = require("config/generated/rogue_reward_rules")
local effects = require("systems/rogue_reward_effect_service")
local effect_state = require("systems/rogue_effect_state_service")

local M = {}
local state_by_player = {}
local next_token = 0

local DEFAULT_REWARD_TYPE = "boss"
local BUILDER_REWARD_TYPE = "builder_start"

local function state_for(player_id)
    if not state_by_player[player_id] then
        state_by_player[player_id] = {
            pools = {
                [DEFAULT_REWARD_TYPE] = {
                    claimed = {}, queue = {}, random_grants = {}, consumed = false,
                    offer = nil,
                },
                [BUILDER_REWARD_TYPE] = {
                    claimed = {}, queue = {}, random_grants = {}, consumed = false,
                    offer = nil,
                },
            },
            -- 预留给 Builder 创建完成后自动弹出奖励的旧流程。
            -- 当前改为通过专门入口手动打开，恢复自动弹出时可继续使用此幂等标记。
            builder_ready = false,
            visible_reward_type = nil,
        }
    end
    return state_by_player[player_id]
end

local function reward_type(payload)
    local requested = tostring(payload and payload.reward_type or "")
    if requested == BUILDER_REWARD_TYPE or requested == DEFAULT_REWARD_TYPE then
        return requested
    end
    if tostring(payload and payload.source or "") == "builder" then
        return BUILDER_REWARD_TYPE
    end
    return DEFAULT_REWARD_TYPE
end

local function pool_for(state, reward_type_id)
    return state.pools[reward_type_id] or state.pools[DEFAULT_REWARD_TYPE]
end

local function rules()
    return (rules_config.by_id or {}).default_rogue_reward or {
        choice_count = 3, free_reroll_count = 1,
    }
end

local function publish(player_id, reason, reward_type_id)
    local state = state_for(player_id)
    reward_type_id = reward_type_id or state.visible_reward_type
        or DEFAULT_REWARD_TYPE
    local pool_state = pool_for(state, reward_type_id)
    local offer = pool_state.offer
    local payload = { active = offer and 1 or 0, reason = reason or "changed" }
    if offer then
        payload.token = offer.token
        payload.rerolls_remaining = offer.rerolls_remaining
        payload.source = offer.source
        payload.reward_type = offer.reward_type
        payload.cards = offer.cards
    end
    CustomNetTables:SetTableValue("survival_rogue_reward", tostring(player_id), payload)
    event_bus.emit(events.ROGUE_REWARD_CHANGED, { player_id = player_id, snapshot = payload })
end

local function available(state, reward_type_id)
    local result = {}
    local pool_state = pool_for(state, reward_type_id)
    for _, card in ipairs(cards.rows or {}) do
        if card.enabled ~= false and card.type == reward_type_id
            and not pool_state.claimed[card.card_id] then
            result[#result + 1] = card
        end
    end
    return result
end

local function weighted_draw(pool, count)
    local result = {}
    while #pool > 0 and #result < count do
        local total = 0
        for _, card in ipairs(pool) do total = total + math.max(0, tonumber(card.weight) or 0) end
        local selected = #pool
        if total > 0 then
            local roll = RandomFloat(0, total)
            local cursor = 0
            for index, card in ipairs(pool) do
                cursor = cursor + math.max(0, tonumber(card.weight) or 0)
                if roll <= cursor then selected = index break end
            end
        else
            selected = RandomInt(1, #pool)
        end
        result[#result + 1] = table.remove(pool, selected)
    end
    return result
end

local function grant_random_cards(payload)
    local player_id = tonumber(payload and payload.player_id)
    local state = player_id and state_for(player_id) or nil
    local reward_type_id = reward_type(payload)
    local pool_state = state and pool_for(state, reward_type_id) or nil
    local parent_grant_id = tostring(payload and payload.parent_grant_id or "")
    local parent_card_id = tostring(payload and payload.parent_card_id or "")
    if not state or player_id < 0 then return { ok = false, error = "player_invalid" } end
    if parent_grant_id == "" then return { ok = false, error = "parent_grant_id_missing" } end

    local transaction = pool_state.random_grants[parent_grant_id]
    if not transaction then
        local pool = {}
        for _, card in ipairs(available(state, reward_type_id)) do
            if card.card_id ~= parent_card_id then pool[#pool + 1] = card end
        end
        local count = math.max(1, math.floor(tonumber(payload.count) or 3))
        local draw = weighted_draw(pool, count)
        if #draw < count then return { ok = false, error = "random_card_pool_insufficient" } end
        transaction = { cards = draw, completed = {} }
        pool_state.random_grants[parent_grant_id] = transaction
    end

    for index, card in ipairs(transaction.cards) do
        if not transaction.completed[index] then
            local child_grant_id = parent_grant_id .. ":child:"
                .. tostring(index) .. ":" .. card.card_id
            local result = effects.grant(
                player_id, card.card_id, child_grant_id, reward_type_id
            )
            if not result or not result.ok then
                return {
                    ok = false,
                    error = result and result.error or "child_effect_failed",
                    effect_id = result and result.effect_id,
                    child_card_id = card.card_id,
                }
            end
            transaction.completed[index] = true
            pool_state.claimed[card.card_id] = true
        end
    end
    return { ok = true, cards = transaction.cards }
end

local function create_offer(player_id, source, reward_type_id, rerolls_remaining)
    local state = state_for(player_id)
    local pool_state = pool_for(state, reward_type_id)
    local draw = weighted_draw(available(state, reward_type_id), tonumber(rules().choice_count) or 3)
    if #draw == 0 then
        if not state.visible_reward_type or state.visible_reward_type == reward_type_id then
            publish(player_id, "pool_exhausted", reward_type_id)
        end
        return false
    end
    next_token = next_token + 1
    local reroll_count = rerolls_remaining
    if reroll_count == nil then
        reroll_count = (tonumber(rules().free_reroll_count) or 1)
            + effect_state.take_numeric(player_id,
                "next_rogue_reroll_count:" .. tostring(reward_type_id))
    end
    pool_state.offer = {
        token = tostring(player_id) .. ":" .. tostring(next_token),
        source = source or "unknown",
        reward_type = reward_type_id,
        pool_state = pool_state,
        rerolls_remaining = reroll_count,
        cards = draw,
    }
    if not state.visible_reward_type
        or not pool_for(state, state.visible_reward_type).offer then
        state.visible_reward_type = reward_type_id
    end
    if state.visible_reward_type == reward_type_id then
        publish(player_id, "offer_created", reward_type_id)
    end
    return true
end

local function promote_next(player_id, reason)
    local state = state_for(player_id)
    for _, reward_type_id in ipairs({ BUILDER_REWARD_TYPE, DEFAULT_REWARD_TYPE }) do
        if pool_for(state, reward_type_id).offer then
            state.visible_reward_type = reward_type_id
            publish(player_id, reason or "offer_promoted", reward_type_id)
            return true
        end
    end
    for _, reward_type_id in ipairs({ BUILDER_REWARD_TYPE, DEFAULT_REWARD_TYPE }) do
        local pool_state = pool_for(state, reward_type_id)
        if #pool_state.queue > 0 then
            local queued = table.remove(pool_state.queue, 1)
            state.visible_reward_type = reward_type_id
            return create_offer(player_id, queued.source, reward_type_id)
        end
    end
    state.visible_reward_type = nil
    publish(player_id, reason or "selected", DEFAULT_REWARD_TYPE)
    return false
end

function M.debug_offer(player_id, card_ids)
    player_id = tonumber(player_id)
    if player_id == nil or player_id < 0 or not PlayerResource:GetPlayer(player_id) then
        return { ok = false, error = "player_invalid" }
    end
    if type(card_ids) ~= "table" or #card_ids ~= 3 then
        return { ok = false, error = "usage: rogue <card_id1> <card_id2> <card_id3>" }
    end

    local selected = {}
    local seen = {}
    local reward_type_id = nil
    for index = 1, 3 do
        local card_id = tostring(card_ids[index] or "")
        if card_id == "" then
            return { ok = false, error = "card_id_missing:" .. tostring(index) }
        end
        if seen[card_id] then
            return { ok = false, error = "card_id_duplicate:" .. card_id }
        end
        local card = (cards.by_id or {})[card_id]
        if not card then
            return { ok = false, error = "card_id_unknown:" .. card_id }
        end
        if reward_type_id and card.type ~= reward_type_id then
            return { ok = false, error = "card_type_mixed" }
        end
        reward_type_id = card.type or DEFAULT_REWARD_TYPE
        seen[card_id] = true
        selected[#selected + 1] = card
    end

    local state = state_for(player_id)
    next_token = next_token + 1
    state.pools[reward_type_id].offer = {
        token = tostring(player_id) .. ":debug:" .. tostring(next_token),
        source = "debug",
        reward_type = tostring((cards.by_id[card_ids[1]] or {}).type or DEFAULT_REWARD_TYPE),
        rerolls_remaining = 0,
        cards = selected,
        allow_claimed = true,
    }
    state.visible_reward_type = reward_type_id
    publish(player_id, "debug_offer_created", reward_type_id)
    return { ok = true, token = state.pools[reward_type_id].offer.token }
end

local function open(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then return { ok = false, error = "player_invalid" } end
    local state = state_for(player_id)
    local source = tostring(payload.source or "unknown")
    local reward_type_id = reward_type(payload)
    local pool_state = pool_for(state, reward_type_id)
    if reward_type_id == BUILDER_REWARD_TYPE and pool_state.consumed then
        return { ok = false, error = "builder_reward_consumed" }
    end
    local visible_offer = state.visible_reward_type
        and pool_for(state, state.visible_reward_type).offer or nil
    local queued = pool_state.offer ~= nil
        or (visible_offer ~= nil and state.visible_reward_type ~= reward_type_id)
    if queued then
        pool_state.queue[#pool_state.queue + 1] = {
            source = source,
        }
    elseif not create_offer(player_id, source, reward_type_id) then
        return { ok = false, error = "pool_exhausted" }
    end
    if reward_type_id == BUILDER_REWARD_TYPE then
        pool_state.consumed = true
        if state.visible_reward_type == reward_type_id then
            publish(player_id, "builder_consumed", reward_type_id)
        end
    end
    return { ok = true, queued = queued }
end

local function valid_offer(payload)
    local player_id = tonumber(payload and payload.player_id)
    local state = player_id and state_for(player_id) or nil
    if not state then
        return nil, nil, nil, nil, { ok = false, error = "offer_stale" }
    end
    local requested = tostring(payload and payload.reward_type or "")
    local reward_type_id = nil
    if requested == DEFAULT_REWARD_TYPE or requested == BUILDER_REWARD_TYPE then
        reward_type_id = requested
    end
    if not reward_type_id then
        local token = tostring(payload and payload.token or "")
        for _, candidate in ipairs({ BUILDER_REWARD_TYPE, DEFAULT_REWARD_TYPE }) do
            local offer = pool_for(state, candidate).offer
            if offer and offer.token == token then reward_type_id = candidate break end
        end
    end
    reward_type_id = reward_type_id or DEFAULT_REWARD_TYPE
    local pool_state = pool_for(state, reward_type_id)
    if not state or not pool_state.offer
        or tostring(payload.token or "") ~= pool_state.offer.token then
        return nil, nil, nil, nil, { ok = false, error = "offer_stale" }
    end
    if state.visible_reward_type ~= reward_type_id then
        return nil, nil, nil, nil, { ok = false, error = "offer_not_visible" }
    end
    return player_id, state, pool_state, pool_state.offer
end

local function log_select_failure(payload, offer, card_id, failure)
    print(string.format(
        "[RogueReward] select_failed player_id=%s source=%s card_id=%s token=%s effect_id=%s error=%s",
        tostring(payload and payload.player_id or ""),
        tostring(offer and offer.source or ""),
        tostring(card_id or payload and payload.card_id or ""),
        tostring(payload and payload.token or ""),
        tostring(failure and failure.effect_id or ""),
        tostring(failure and failure.error or "effect_failed")
    ))
end

local function select_card(payload)
    local player_id, state, pool_state, offer, failure = valid_offer(payload)
    if failure then
        log_select_failure(payload, offer, nil, failure)
        return failure
    end
    local card_id = tostring(payload.card_id or "")
    local offered = false
    for _, card in ipairs(offer.cards) do
        if card.card_id == card_id
            and card.type == offer.reward_type then
            offered = true
            break
        end
    end
    if not offered or (pool_state.claimed[card_id] and not offer.allow_claimed) then
        failure = { ok = false, error = "card_invalid" }
        log_select_failure(payload, offer, card_id, failure)
        return failure
    end
    local result = effects.grant(
        player_id,
        card_id,
        "reward:" .. tostring(offer.token) .. ":" .. card_id,
        offer.reward_type
    )
    if not result or not result.ok then
        log_select_failure(payload, offer, card_id, result)
        return result or { ok = false, error = "effect_failed" }
    end
    pool_state.claimed[card_id] = true
    pool_state.offer = nil
    if state.visible_reward_type == offer.reward_type then
        state.visible_reward_type = nil
    end
    promote_next(player_id, "selected")
    return { ok = true, card_id = card_id, grant_id = result.grant_id }
end

local function reroll(payload)
    local player_id, state, pool_state, offer, failure = valid_offer(payload)
    if failure then return failure end
    if offer.rerolls_remaining <= 0 then return { ok = false, error = "reroll_consumed" } end
    local source = offer.source
    local reward_type_id = offer.reward_type
    if not create_offer(player_id, source, reward_type_id,
        offer.rerolls_remaining - 1) then
        return { ok = false, error = "pool_exhausted" }
    end
    publish(player_id, "rerolled", reward_type_id)
    return { ok = true }
end

function M.init()
    state_by_player = {}; next_token = 0; effects.init()
    event_bus.handle_request(events.ROGUE_REWARD_OPEN_REQUEST, open)
    event_bus.handle_request(events.ROGUE_REWARD_SELECT_REQUEST, select_card)
    event_bus.handle_request(events.ROGUE_REWARD_REROLL_REQUEST, reroll)
    event_bus.handle_request(events.ROGUE_REWARD_GRANT_RANDOM_REQUEST, grant_random_cards)
    event_bus.handle_request(events.ROGUE_REWARD_CONSUMED_GET_REQUEST, function(payload)
        local state = state_for(tonumber(payload.player_id) or -1)
        local reward_type_id = reward_type(payload)
        return pool_for(state, reward_type_id).consumed == true
    end)
    -- 当前 Builder 开局肉鸽由专门入口（ability_survival_rogue_reward）手动打开，
    -- 因此暂时关闭 BUILDER_READY 时自动创建 offer，避免 Builder 创建完成后立即弹出三选一 UI。
    -- 手动入口仍通过 ROGUE_REWARD_OPEN_REQUEST + source="builder" 打开 builder_start 池，
    -- Boss 奖励、双池队列、领取、重抽及效果运行时均不受影响。
    -- 若后续需要恢复开局自动弹出，取消下面整段注释即可；builder_ready 用于保证只触发一次，
    -- 自动创建失败时会重置该标记，允许后续 BUILDER_READY 再次尝试。
    -- event_bus.subscribe(events.BUILDER_READY, function(payload)
    --     local player_id = tonumber(payload and payload.player_id)
    --     if player_id == nil or player_id < 0 then return end
    --     local state = state_for(player_id)
    --     if state.builder_ready then return end
    --     state.builder_ready = true
    --     local result = open({
    --         player_id = player_id,
    --         source = "builder",
    --         reward_type = BUILDER_REWARD_TYPE,
    --     })
    --     if not result or result.ok ~= true then
    --         state.builder_ready = false
    --         print(string.format(
    --             "[RogueReward] builder_offer_failed player_id=%s error=%s",
    --             tostring(player_id), tostring(result and result.error or "unknown")
    --         ))
    --     end
    -- end)
end

return M