package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local handlers = {}
package.preload["core/event_bus"] = function()
    return {
        handle_request = function(name, handler) handlers[name] = handler end,
        subscribe = function() return {} end,
        unsubscribe = function() end,
        emit = function() end,
        request = function(name, payload) return handlers[name](payload or {}) end,
    }
end

local grants = {}
local fail_once = true
package.preload["systems/rogue_reward_effect_service"] = function()
    return {
        init = function() end,
        grant = function(player_id, card_id, grant_id)
            grants[#grants + 1] = { player_id = player_id, card_id = card_id, grant_id = grant_id }
            if fail_once and #grants == 2 then
                fail_once = false
                return { ok = false, error = "injected_failure", effect_id = "test_effect" }
            end
            return { ok = true, grant_id = grant_id }
        end,
    }
end

PlayerResource = {
    GetPlayer = function(_, player_id) return player_id == 0 and {} or nil end,
}
CustomNetTables = { SetTableValue = function() end }
RandomFloat = function() return 0 end
RandomInt = function() return 1 end

local events = require("core/events")
local service = require("systems/rogue_reward_service")
service.init()
local request = handlers[events.ROGUE_REWARD_GRANT_RANDOM_REQUEST]
assert(request, "divine wish internal request was not registered")

local payload = {
    player_id = 0,
    parent_card_id = "divine_wish",
    parent_grant_id = "reward:9:divine_wish",
    count = 3,
}
local first = request(payload)
assert(first.ok == false and first.error == "injected_failure",
    "divine wish did not fail closed on child grant failure")
assert(grants[1].card_id ~= "divine_wish" and grants[2].card_id ~= "divine_wish",
    "divine wish drew itself")
local first_card = grants[1].card_id
local second_card = grants[2].card_id
local second_grant_id = grants[2].grant_id

local retried = request(payload)
assert(retried.ok == true and #retried.cards == 3,
    "divine wish retry did not finish fixed transaction")
assert(grants[3].card_id == second_card and grants[3].grant_id == second_grant_id,
    "divine wish retry redrew cards or changed deterministic grant id")
assert(grants[4].card_id ~= first_card and grants[4].card_id ~= second_card,
    "divine wish draw was not without replacement")

print("ROGUE_DIVINE_WISH_TRANSACTION_LUA51_PASS")