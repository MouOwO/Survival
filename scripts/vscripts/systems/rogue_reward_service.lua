local event_bus = require("core/event_bus")
local events = require("core/events")
local cards = require("config/generated/rogue_reward_cards")
local rules_config = require("config/generated/rogue_reward_rules")
local effects = require("systems/rogue_reward_effect_service")
local effect_state = require("systems/rogue_effect_state_service")

local M = {}
local state_by_player = {}
local next_token = 0

local function state_for(player_id)
    if not state_by_player[player_id] then
        state_by_player[player_id] = {
            claimed = {}, queue = {}, consumed_builder = false, random_grants = {},
        }
    end
    return state_by_player[player_id]
end

local function rules()
    return (rules_config.by_id or {}).default_rogue_reward or {
        choice_count = 3, free_reroll_count = 1,
    }
end

local function publish(player_id, reason)
    local state = state_for(player_id)
    local offer = state.offer
    local payload = { active = offer and 1 or 0, reason = reason or "changed" }
    if offer then
        payload.token = offer.token
        payload.rerolls_remaining = offer.rerolls_remaining
        payload.source = offer.source
        payload.cards = offer.cards
    end
    CustomNetTables:SetTableValue("survival_rogue_reward", tostring(player_id), payload)
    event_bus.emit(events.ROGUE_REWARD_CHANGED, { player_id = player_id, snapshot = payload })
end

local function available(state)
    local result = {}
    for _, card in ipairs(cards.rows or {}) do
        if card.enabled ~= false and not state.claimed[card.card_id] then
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
    local parent_grant_id = tostring(payload and payload.parent_grant_id or "")
    local parent_card_id = tostring(payload and payload.parent_card_id or "")
    if not state or player_id < 0 then return { ok = false, error = "player_invalid" } end
    if parent_grant_id == "" then return { ok = false, error = "parent_grant_id_missing" } end

    local transaction = state.random_grants[parent_grant_id]
    if not transaction then
        local pool = {}
        for _, card in ipairs(available(state)) do
            if card.card_id ~= parent_card_id then pool[#pool + 1] = card end
        end
        local count = math.max(1, math.floor(tonumber(payload.count) or 3))
        local draw = weighted_draw(pool, count)
        if #draw < count then return { ok = false, error = "random_card_pool_insufficient" } end
        transaction = { cards = draw, completed = {} }
        state.random_grants[parent_grant_id] = transaction
    end

    for index, card in ipairs(transaction.cards) do
        if not transaction.completed[index] then
            local child_grant_id = parent_grant_id .. ":child:"
                .. tostring(index) .. ":" .. card.card_id
            local result = effects.grant(player_id, card.card_id, child_grant_id)
            if not result or not result.ok then
                return {
                    ok = false,
                    error = result and result.error or "child_effect_failed",
                    effect_id = result and result.effect_id,
                    child_card_id = card.card_id,
                }
            end
            transaction.completed[index] = true
            state.claimed[card.card_id] = true
        end
    end
    return { ok = true, cards = transaction.cards }
end

local function create_offer(player_id, source, rerolls_remaining)
    local state = state_for(player_id)
    local draw = weighted_draw(available(state), tonumber(rules().choice_count) or 3)
    if #draw == 0 then publish(player_id, "pool_exhausted") return false end
    next_token = next_token + 1
    local reroll_count = rerolls_remaining
    if reroll_count == nil then
        reroll_count = (tonumber(rules().free_reroll_count) or 1)
            + effect_state.take_numeric(player_id, "next_rogue_reroll_count")
    end
    state.offer = {
        token = tostring(player_id) .. ":" .. tostring(next_token),
        source = source or "unknown",
        rerolls_remaining = reroll_count,
        cards = draw,
    }
    publish(player_id, "offer_created")
    return true
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
        seen[card_id] = true
        selected[#selected + 1] = card
    end

    local state = state_for(player_id)
    next_token = next_token + 1
    state.offer = {
        token = tostring(player_id) .. ":debug:" .. tostring(next_token),
        source = "debug",
        rerolls_remaining = 0,
        cards = selected,
        allow_claimed = true,
    }
    publish(player_id, "debug_offer_created")
    return { ok = true, token = state.offer.token }
end

local function open(payload)
    local player_id = tonumber(payload and payload.player_id)
    if player_id == nil or player_id < 0 then return { ok = false, error = "player_invalid" } end
    local state = state_for(player_id)
    local source = tostring(payload.source or "unknown")
    if source == "builder" and state.consumed_builder then
        return { ok = false, error = "builder_reward_consumed" }
    end
    local queued = state.offer ~= nil
    if queued then
        state.queue[#state.queue + 1] = source
    elseif not create_offer(player_id, source) then
        return { ok = false, error = "pool_exhausted" }
    end
    if source == "builder" then
        state.consumed_builder = true
        publish(player_id, "builder_consumed")
    end
    return { ok = true, queued = queued }
end

local function valid_offer(payload)
    local player_id = tonumber(payload and payload.player_id)
    local state = player_id and state_for(player_id) or nil
    if not state or not state.offer or tostring(payload.token or "") ~= state.offer.token then
        return nil, nil, { ok = false, error = "offer_stale" }
    end
    return player_id, state
end

local function log_select_failure(payload, state, card_id, failure)
    print(string.format(
        "[RogueReward] select_failed player_id=%s source=%s card_id=%s token=%s effect_id=%s error=%s",
        tostring(payload and payload.player_id or ""),
        tostring(state and state.offer and state.offer.source or ""),
        tostring(card_id or payload and payload.card_id or ""),
        tostring(payload and payload.token or ""),
        tostring(failure and failure.effect_id or ""),
        tostring(failure and failure.error or "effect_failed")
    ))
end

local function select_card(payload)
    local player_id, state, failure = valid_offer(payload)
    if failure then
        log_select_failure(payload, state, nil, failure)
        return failure
    end
    local card_id = tostring(payload.card_id or "")
    local offered = false
    for _, card in ipairs(state.offer.cards) do
        if card.card_id == card_id then offered = true break end
    end
    if not offered or (state.claimed[card_id] and not state.offer.allow_claimed) then
        failure = { ok = false, error = "card_invalid" }
        log_select_failure(payload, state, card_id, failure)
        return failure
    end
    local result = effects.grant(
        player_id,
        card_id,
        "reward:" .. tostring(state.offer.token) .. ":" .. card_id
    )
    if not result or not result.ok then
        log_select_failure(payload, state, card_id, result)
        return result or { ok = false, error = "effect_failed" }
    end
    state.claimed[card_id] = true
    state.offer = nil
    if #state.queue > 0 then create_offer(player_id, table.remove(state.queue, 1))
    else publish(player_id, "selected") end
    return { ok = true, card_id = card_id, grant_id = result.grant_id }
end

local function reroll(payload)
    local player_id, state, failure = valid_offer(payload)
    if failure then return failure end
    if state.offer.rerolls_remaining <= 0 then return { ok = false, error = "reroll_consumed" } end
    local source = state.offer.source
    if not create_offer(player_id, source, state.offer.rerolls_remaining - 1) then
        return { ok = false, error = "pool_exhausted" }
    end
    publish(player_id, "rerolled")
    return { ok = true }
end

function M.init()
    state_by_player = {}; next_token = 0; effects.init()
    event_bus.handle_request(events.ROGUE_REWARD_OPEN_REQUEST, open)
    event_bus.handle_request(events.ROGUE_REWARD_SELECT_REQUEST, select_card)
    event_bus.handle_request(events.ROGUE_REWARD_REROLL_REQUEST, reroll)
    event_bus.handle_request(events.ROGUE_REWARD_GRANT_RANDOM_REQUEST, grant_random_cards)
    event_bus.handle_request(events.ROGUE_REWARD_CONSUMED_GET_REQUEST, function(payload)
        return state_for(tonumber(payload.player_id) or -1).consumed_builder == true
    end)
end

return M