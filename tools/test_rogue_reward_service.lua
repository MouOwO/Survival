package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local handlers = {}
local emitted = {}
local net = {}
local subscribers = {}
package.preload["core/event_bus"] = function()
    return {
        handle_request = function(name, handler) handlers[name] = handler end,
        subscribe = function(name, handler)
            subscribers[name] = subscribers[name] or {}
            subscribers[name][#subscribers[name] + 1] = handler
            return { event_name = name, token = #subscribers[name] }
        end,
        unsubscribe = function() end,
        request = function(name, payload)
            if handlers[name] then return handlers[name](payload or {}) end
            error("unhandled request: " .. tostring(name))
        end,
        emit = function(name, payload) emitted[#emitted + 1] = { name = name, payload = payload } end,
    }
end

DOTA_TEAM_GOODGUYS = 2
PlayerResource = {
    GetPlayer = function(_, player_id) return player_id == 0 and {} or nil end,
    GetTeam = function() return DOTA_TEAM_GOODGUYS end,
}
GameRules = { GetGameTime = function() return 0 end }
CustomNetTables = {
    SetTableValue = function(_, table_name, key, value)
        net[table_name .. ":" .. key] = value
    end,
}
RandomFloat = function() return 0 end
RandomInt = function() return 1 end

local events = require("core/events")
local resources = { wood = 1000, gold = 0 }
handlers[events.RESOURCE_GET_REQUEST] = function() return resources end
handlers[events.RESOURCE_ADD_REQUEST] = function(payload)
    resources.wood = resources.wood + (payload.wood or 0)
    resources.gold = resources.gold + (payload.gold or 0)
    return { ok = true }
end
local rogue_attack_speed = 0
handlers[events.TECHNOLOGY_STATS_ROGUE_ADD_REQUEST] = function(payload)
    rogue_attack_speed = rogue_attack_speed + payload.effects[1].value
    return { ok = true }
end

local service = require("systems/rogue_reward_service")
service.init()

local function request(name, payload) return handlers[name](payload or {}) end
local function snapshot() return net["survival_rogue_reward:0"] end
local function assert_true(value, message) if not value then error(message, 2) end end
local function offered_ids(value)
    local result = {}
    for _, card in pairs(value.cards or {}) do result[card.card_id] = true end
    return result
end

assert_true(request(events.ROGUE_REWARD_OPEN_REQUEST, {
    player_id = 0, source = "builder",
}).ok, "builder offer failed")
local first = snapshot()
assert_true(#first.cards == 3, "offer must contain three cards")
assert_true(first.rerolls_remaining == 1, "first offer must have one reroll")
local first_ids = offered_ids(first)

assert_true(request(events.ROGUE_REWARD_REROLL_REQUEST, {
    player_id = 0, token = first.token,
}).ok, "reroll failed")
local rerolled = snapshot()
assert_true(rerolled.token ~= first.token, "reroll must rotate token")
assert_true(rerolled.rerolls_remaining == 0, "reroll must be consumed")
assert_true(not request(events.ROGUE_REWARD_SELECT_REQUEST, {
    player_id = 0, token = first.token, card_id = first.cards[1].card_id,
}).ok, "stale token accepted")
assert_true(not request(events.ROGUE_REWARD_REROLL_REQUEST, {
    player_id = 0, token = rerolled.token,
}).ok, "second reroll accepted")
assert_true(next(first_ids) ~= nil, "initial display missing")
local rerolled_ids = offered_ids(rerolled)
for card_id in pairs(first_ids) do
    assert_true(rerolled_ids[card_id], "unclaimed displayed card was excluded")
end

local selected = rerolled.cards[1].card_id
assert_true(request(events.ROGUE_REWARD_OPEN_REQUEST, {
    player_id = 0, source = "boss",
}).ok, "queued boss failed")
assert_true(request(events.ROGUE_REWARD_SELECT_REQUEST, {
    player_id = 0, token = rerolled.token, card_id = selected,
}).ok, "selection failed")
local queued = snapshot()
assert_true(queued.active == 1 and queued.source == "boss", "queued offer not promoted")
assert_true(not offered_ids(queued)[selected], "claimed card offered again")
assert_true(request(events.ROGUE_REWARD_CONSUMED_GET_REQUEST, {
    player_id = 0,
}) == true, "builder reward not consumed")

local effects = require("systems/rogue_reward_effect_service")
assert_true(effects.apply(0, "fiscal_subsidy").ok and resources.gold == 10000,
    "gold effect failed")
assert_true(effects.apply(0, "radiant_sapling").ok and resources.wood == 1200,
    "wood effect failed")
local speed_before = rogue_attack_speed
assert_true(effects.apply(0, "fortifications").ok
    and rogue_attack_speed == speed_before + 6,
    "tower speed effect failed")

local before_debug = snapshot()
assert_true(not service.debug_offer(0, {
    "fiscal_subsidy", "radiant_sapling",
}).ok, "debug offer accepted fewer than three cards")
assert_true(not service.debug_offer(0, {
    "fiscal_subsidy", "fiscal_subsidy", "fortifications",
}).ok, "debug offer accepted duplicate card IDs")
assert_true(not service.debug_offer(0, {
    "fiscal_subsidy", "missing_card", "fortifications",
}).ok, "debug offer accepted unknown card ID")
assert_true(snapshot().token == before_debug.token,
    "invalid debug offer replaced active offer")

assert_true(service.debug_offer(0, {
    "fiscal_subsidy", "radiant_sapling", "fortifications",
}).ok, "debug offer failed")
local debug_offer = snapshot()
assert_true(debug_offer.active == 1 and debug_offer.source == "debug",
    "debug offer was not published")
assert_true(debug_offer.rerolls_remaining == 0,
    "debug offer unexpectedly allowed reroll")
assert_true(debug_offer.cards[1].card_id == "fiscal_subsidy"
    and debug_offer.cards[2].card_id == "radiant_sapling"
    and debug_offer.cards[3].card_id == "fortifications",
    "debug offer did not preserve requested card order")
assert_true(not request(events.ROGUE_REWARD_SELECT_REQUEST, {
    player_id = 0, token = before_debug.token, card_id = "fiscal_subsidy",
}).ok, "debug offer did not invalidate previous token")
assert_true(request(events.ROGUE_REWARD_SELECT_REQUEST, {
    player_id = 0, token = debug_offer.token, card_id = "fiscal_subsidy",
}).ok and resources.gold == 20000,
    "debug offer selection did not use formal effect runtime")

assert_true(service.debug_offer(0, {
    "fiscal_subsidy", "radiant_sapling", "fortifications",
}).ok, "repeat debug offer failed")
local repeated_offer = snapshot()
assert_true(request(events.ROGUE_REWARD_SELECT_REQUEST, {
    player_id = 0, token = repeated_offer.token, card_id = "fiscal_subsidy",
}).ok and resources.gold == 30000,
    "debug offer could not repeat a claimed card")

print("ROGUE_REWARD_SERVICE_LUA51_PASS")