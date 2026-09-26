-- Offline regression: history records successful choices, newest first, per player.
package.path = "scripts/vscripts/?.lua;" .. package.path
local fixtures = { rows = {}, by_id = {} }
for index = 1, 25 do
    local card = { card_id = "card_" .. index, type = "boss", display_name = "Treasure " .. index,
        description = "Effect " .. index, icon_name = "test_icon_" .. index, enabled = true }
    fixtures.rows[index] = card
    fixtures.by_id[card.card_id] = card
end
package.loaded["config/generated/rogue_reward_cards"] = fixtures
local fail_grant = false
package.loaded["systems/rogue_reward_effect_service"] = {
    init = function() end,
    grant = function(_, _, grant_id)
        return { ok = not fail_grant, grant_id = grant_id, error = fail_grant and "test_failure" or nil }
    end,
}
package.loaded["systems/rogue_effect_state_service"] = { take_numeric = function() return 0 end }
PlayerResource = { GetPlayer = function() return {} end }
local snapshots = {}
CustomNetTables = { SetTableValue = function(_, _, key, value) snapshots[key] = value end }
local bus, events = require("core/event_bus"), require("core/events")
local service = require("systems/rogue_reward_service")
service.init()
local function offer(player, index)
    local result = service.debug_offer(player, { "card_" .. index, "card_24", "card_25" })
    assert(result.ok)
    return { player_id = player, token = result.token, card_id = "card_" .. index }
end
local function choose(payload)
    return bus.request(events.ROGUE_REWARD_SELECT_REQUEST, payload)
end
for index = 1, 23 do assert(choose(offer(0, index)).ok) end
local history = snapshots["0"].history
assert(#history == 20, "history must retain twenty entries")
for index = 1, 20 do
    local source = 24 - index
    assert(history[index].card_id == "card_" .. source)
    assert(history[index].icon_name == "test_icon_" .. source)
    assert(history[index].description == "Effect " .. source)
end
assert(choose(offer(1, 1)).ok)
assert(#snapshots["1"].history == 1 and #snapshots["0"].history == 20, "players must stay isolated")
local failed = offer(0, 1)
fail_grant = true
assert(not choose(failed).ok)
assert(snapshots["0"].history[1].card_id == "card_23", "failed grants must not appear in history")
fail_grant = false
assert(choose(failed).ok)
assert(snapshots["0"].history[1].card_id == "card_1")
assert(not choose(failed).ok, "repeated tokens cannot add another history row")
assert(snapshots["0"].history[2].card_id == "card_23")
print("ROGUE_REWARD_HISTORY_PASS: capacity, order, icon projection, player isolation, failure and duplicate selection")

for i = 1, 3 do
    local row = {card_id = "talent_" .. i, type = "builder_start", display_name = "Talent " .. i,
        description = "Talent effect", icon_name = "test", enabled = true, weight = 1}
    fixtures.rows[#fixtures.rows + 1] = row; fixtures.by_id[row.card_id] = row
end
RandomFloat = function() return 0 end
RandomInt = function() return 1 end
local opened = bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {player_id = 2, source = "builder"})
assert(opened.ok and snapshots["2"].talent_pending == 1)
local token = snapshots["2"].token
assert(bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {player_id = 2, source = "builder"}).ok)
assert(snapshots["2"].token == token, "reopening reuses the offer")
local payload = {player_id = 2, token = token, card_id = "talent_1"}
fail_grant = true; assert(not choose(payload).ok)
assert(snapshots["2"].talent_pending == 1, "failed choice must keep the reminder")
fail_grant = false; assert(choose(payload).ok)
assert(snapshots["2"].talent_pending == 0)
assert(snapshots["2"].builder_talent.icon_name == "survival/native/talent_talent_1")
for index = 1, 23 do assert(choose(offer(2, index)).ok) end
assert(snapshots["2"].builder_talent.card_id == "talent_1", "boss history rotation must preserve selected talent")
assert(not snapshots["0"].builder_talent.card_id, "talents remain player-local")
local shown = bus.request(events.ROGUE_REWARD_OPEN_REQUEST, {player_id = 2, source = "builder"})
assert(shown.ok and shown.selected == "talent_1", "completed talent displays without granting twice")
print("BUILDER_TALENT_STATE_PASS")
