-- Exercise the real UI router/listeners and real event bus. Only unrelated
-- rendering systems and engine entities are replaced with small test fixtures.
package.path = "scripts/vscripts/?.lua;" .. package.path

local listeners, packets, admitted = {}, {}, {}
local defeated = {}
package.loaded["systems/multiplayer_player_service"] = {
    is_defeated = function(id) return defeated[id] == true end,
}
local player_handles = { [0] = {}, [1] = {} }
PlayerResource = {
    IsValidPlayerID = function(_, id) return player_handles[id] ~= nil end,
    GetPlayer = function(_, id) return player_handles[id] end,
}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback) listeners[name] = callback return name end,
    Send_ServerToPlayer = function(_, player, name, payload)
        packets[#packets + 1] = { player = player, name = name, payload = payload }
    end,
}
package.loaded["systems/startup_loading_service"] = {
    is_player_ready = function(id) return admitted[id] == true end,
}
for _, name in ipairs({ "systems/building_system", "ui/weapon_synthesis_snapshot_service",
    "ui/combat_stat_projection", "config/asset_catalog", "systems/hero_summon_projection",
    "systems/building_batch_upgrade_service", "systems/gold_mine_batch_upgrade_service" }) do
    package.loaded[name] = {}
end
package.loaded["config/tree_config"] = { unit_name = "enemy_tree" }

local bus = require("core/event_bus")
local events = require("core/events")
bus.reset()
local calls = { difficulty = 0, place = 0, build = 0, draw = 0, exchange = 0 }
local tickets, permanent_items, wood, cooldown = 5, 0, 100, 0
local unit = { survival_player_id = 0 }
function unit:IsNull() return false end
function unit:GetPlayerOwnerID() return 0 end
local ability = {}
function ability:IsNull() return false end
function ability:GetAbilityName() return "ability_build_wall" end
function ability:GetCaster() return unit end
function ability:GetBehaviorInt() return 16 end
function ability:GetLevel() return 1 end
function ability:GetCooldown() return 3 end
function ability:StartCooldown(value) cooldown = cooldown + value end
EntIndexToHScript = function(index) return ({ [400] = unit, [401] = ability })[index] end
DOTA_ABILITY_BEHAVIOR_POINT = 16
bit = { band = function(value, mask) return value == mask and mask or 0 end }
Vector = function(x, y, z) return { x = x, y = y, z = z } end

bus.handle_request(events.WAVE_DIFFICULTY_SET_REQUEST, function(payload)
    assert(payload.player_id == 0 and payload.difficulty_id == "hard")
    calls.difficulty = calls.difficulty + 1
    return { ok = true, difficulty_id = "hard", total_waves = 50 }
end)
bus.handle_request(events.BUILD_CAN_PLACE_REQUEST, function(payload)
    assert(payload.caster == unit and payload.building_id == "wall")
    assert(payload.position.x == 128 and payload.position.y == 256)
    calls.place = calls.place + 1
    return { ok = true }
end)
bus.handle_request(events.BUILD_REQUEST, function(payload)
    assert(payload.caster == unit and payload.source_ability == ability and payload.building_id == "wall")
    calls.build, wood = calls.build + 1, wood - 20
    return { ok = true }
end)
bus.handle_request(events.LOTTERY_DRAW_REQUEST, function(payload)
    assert(payload.player_id == 0 and payload.pool_id == "map" and payload.count == 2)
    assert(payload.request_id == "draw-one" and type(payload.complete) == "function")
    calls.draw, tickets = calls.draw + 1, tickets - payload.count
    return { ok = true, results = { "fixture-item" } }
end)
bus.handle_request(events.LOTTERY_EXCHANGE_REQUEST, function(payload)
    assert(payload.player_id == 0 and payload.item_id == "permanent-test-item")
    assert(payload.request_id == "exchange-one" and type(payload.complete) == "function")
    calls.exchange, permanent_items = calls.exchange + 1, permanent_items + 1
    return { ok = true, item_id = payload.item_id }
end)

require("ui/ui_request_router").init()
local function invoke_all(engine_player_id)
    -- PlayerID is injected by the engine; the distinct lowercase player_id is
    -- client-controlled and must never change the request's acting player.
    assert(listeners.ui_difficulty_select_request)(200 + engine_player_id,
        { PlayerID = engine_player_id, player_id = 1, difficulty_id = "hard" })
    assert(listeners.ui_ability_cast_position_request)(200 + engine_player_id,
        { PlayerID = engine_player_id, player_id = 1, entindex = 400, ability_entindex = 401,
          x = 128, y = 256, z = 0 })
    assert(listeners.ui_lottery_draw_request)(200 + engine_player_id,
        { PlayerID = engine_player_id, player_id = 1, pool_id = "map", count = 2, request_id = "draw-one" })
    assert(listeners.ui_lottery_exchange_request)(200 + engine_player_id,
        { PlayerID = engine_player_id, player_id = 1, pool_id = "map",
          item_id = "permanent-test-item", request_id = "exchange-one" })
end
local function no_effects()
    for _, count in pairs(calls) do assert(count == 0, "closed gate must not dispatch a business request") end
    assert(tickets == 5 and permanent_items == 0 and wood == 100 and cooldown == 0)
    assert(#packets == 0, "closed gate cannot acknowledge an operation as successful")
end

-- A valid connected engine player is not sufficient during loading.
invoke_all(0)
no_effects()

-- The established player is admitted; an engine-valid late entrant is still
-- outside this match's authenticated frozen roster and cannot act through UI.
admitted[0] = true
invoke_all(1)
no_effects()

-- An admitted account retains the complete normal paths: difficulty selection,
-- build validation and construction/cooldown, draw, and permanent exchange.
invoke_all(0)
assert(calls.difficulty == 1 and calls.place == 1 and calls.build == 1)
assert(calls.draw == 1 and calls.exchange == 1)
assert(tickets == 3 and permanent_items == 1 and wood == 80 and cooldown == 3)
assert(#packets == 4)
local expected = { ui_difficulty_select_result = true, ui_ability_cast_result = true,
    ui_lottery_result = true, ui_lottery_exchange_result = true }
for _, packet in ipairs(packets) do
    assert(packet.player == player_handles[0] and expected[packet.name])
    assert(packet.payload.success == 1 or packet.payload.ok == true)
    expected[packet.name] = nil
end
assert(next(expected) == nil)

-- Defeat blocks every mutation above while allowing private snapshots for spectating.
defeated[0] = true
invoke_all(0)
assert(calls.difficulty == 1 and calls.place == 1 and calls.build == 1)
assert(calls.draw == 1 and calls.exchange == 1 and #packets == 4)
local snapshot_requested = false
bus.subscribe(events.UI_SNAPSHOT_REQUESTED, function(payload)
    snapshot_requested = payload.player_id == 0
end)
listeners.ui_request_full_snapshot(nil, { PlayerID = 0, request_id = "spectating" })
assert(snapshot_requested and #packets == 5)
assert(packets[5].player == player_handles[0] and packets[5].name == "ui_operation_result")
assert(packets[5].payload.success == 1)
table.remove(packets)
defeated[0] = nil

-- Losing current admission (disconnect / missing matching profile) also closes
-- the custom-event path after the global startup barrier has been released.
admitted[0] = false
invoke_all(0)
assert(calls.difficulty == 1 and calls.place == 1 and calls.build == 1)
assert(calls.draw == 1 and calls.exchange == 1 and #packets == 4)
assert(tickets == 3 and permanent_items == 1 and wood == 80 and cooldown == 3)

print("STARTUP_UI_REQUEST_GATE_PASS: real router blocks loading/late/revoked actors; ready difficulty/build/lottery paths preserved")
