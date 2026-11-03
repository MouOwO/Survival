package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
-- This isolated in-process fixture has four synthetic player handles, no
-- Steam identities or network admission. It does not alter runtime policy.
package.loaded["config/test_access"] = { enabled = false }
local bus = require("core/event_bus")
local events = require("core/events")
local transport = require("ui/compact_ui_transport")
local projection = require("systems/hero_summon_projection")
local service = require("ui/hero_summon_ui_service")
local players, bound, listeners, sent = {}, {}, {}, {}
local queries, requests, registrations, routed, during_snapshot = 0, 0, 0
for id = 0, 3 do players[id] = { id = id } end
PlayerResource = {
    IsValidPlayerID = function(_, id) return players[id] ~= nil end,
    GetPlayer = function(_, id) return players[id] end,
}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback)
        registrations = registrations + 1; listeners[name] = callback
    end,
    Send_ServerToPlayer = function(_, player, name, payload)
        sent[#sent + 1] = { player = player, name = name, payload = payload }
    end,
}
transport.is_bound = function(id) return bound[id] == true end
local function install()
    bus.handle_request(events.PLAYER_ENTITLEMENT_GET_REQUEST, function(p)
        return { snapshot = { vip = p.player_id % 2 } }
    end)
    bus.handle_request(events.PLAYER_PROFILE_GET_REQUEST, function()
        return { ok = true, profile = { save = { content_inventory = {} } } }
    end)
    bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function(p)
        queries = queries + 1
        local snapshot = projection.build(p.player_id, nil, 4, nil)
        if during_snapshot then local fn = during_snapshot; during_snapshot = nil; fn() end
        return { ok = true, snapshot = snapshot }
    end)
    bus.handle_request(events.HERO_SUMMON_REQUEST, function(p)
        requests = requests + 1; routed = p
        return { ok = false, error = "ordinary locked hero" }
    end)
    service.init()
end
local function count(name)
    local result = 0
    for _, row in ipairs(sent) do if row.name == name then result = result + 1 end end
    return result
end
local function changed(id)
    bus.emit(events.HERO_SUMMON_STATE_CHANGED, { player_id = id, heroes = {} })
    bus.emit(events.HERO_ALTAR_OPEN_REQUEST, { player_id = id })
end
local function snapshot_request(id)
    listeners.ui_hero_summon_snapshot_request(nil, { PlayerID = id, player_id = 99 })
end

bus.reset(); install()
assert(registrations == 2); service.init(); assert(registrations == 2)
for n = 1, 1000 do changed((n - 1) % 4) end
assert(queries == 0 and #sent == 0, "cold events must not request/build/send a UI catalogue before Hello")

snapshot_request(0)
assert(queries == 1 and #sent == 1 and sent[1].name == "ui_hero_summon_state")
assert(sent[1].player == players[0] and #sent[1].payload.heroes == 6, "old explicit request retains the real six-hero projection")
local before = #sent
changed(1); assert(#sent == before and queries == 1, "one player's subscription must not subscribe a teammate")
changed(0); assert(#sent == before + 2 and queries == 2)

players[0] = { id = 0, replacement = true }
before = #sent; changed(0)
assert(#sent == before and queries == 2, "replacement player handle cannot inherit an old subscription")
snapshot_request(0); assert(queries == 3)
bound[0] = true
before = #sent
for n = 1, 1000 do changed(0) end
snapshot_request(0)
assert(#sent == before and queries == 3, "compact binding stops an existing legacy subscription, including explicit stale requests")
bound[0] = false; changed(0)
assert(#sent == before and queries == 3, "a retired subscription does not reactivate itself")

listeners.ui_hero_summon_request(nil, { PlayerID = 1, player_id = 99, hero_id = "hero_doom", debug_bypass = true, admin = true })
assert(requests == 1 and routed.player_id == 1 and routed.hero_id == "hero_doom")
local fields = 0
for key in pairs(routed) do fields = fields + 1; assert(key == "player_id" or key == "hero_id") end
assert(fields == 2 and count("ui_hero_summon_operation_result") == 1, "normal summon authority/allowlist is unchanged")

local unlock_before, notification_before = count("ui_shop_unlock_state"), count("ui_notification")
for n = 1, 1000 do bus.emit(events.SHOP_UNLOCK_CHANGED, { player_id = 2, unlocked = 0 }) end
assert(count("ui_shop_unlock_state") == unlock_before + 1, "first false must reach the live shop consumer exactly once")
bus.emit(events.SHOP_UNLOCK_CHANGED, { player_id = 2, unlocked = 1 })
for n = 1, 1000 do bus.emit(events.SHOP_UNLOCK_CHANGED, { player_id = 2, unlocked = 1 }) end
assert(count("ui_shop_unlock_state") == unlock_before + 2 and count("ui_notification") == notification_before + 1)
bus.emit(events.SHOP_UNLOCK_CHANGED, { player_id = 2, unlocked = 0 })
bus.emit(events.SHOP_UNLOCK_CHANGED, { player_id = 2, unlocked = 1 })
assert(count("ui_shop_unlock_state") == unlock_before + 4 and count("ui_notification") == notification_before + 2)
players[2] = { id = 2, replacement = true }
bus.emit(events.SHOP_UNLOCK_CHANGED, { player_id = 2, unlocked = 0 })
assert(count("ui_shop_unlock_state") == unlock_before + 5, "new actual handle receives its own initial state")

local old_snapshot, old_summon = listeners.ui_hero_summon_snapshot_request, listeners.ui_hero_summon_request
before = #sent; local old_queries, old_requests = queries, requests
bus.reset(); install()
old_snapshot(nil, { PlayerID = 1 }); old_summon(nil, { PlayerID = 1, hero_id = "hero_doom" })
assert(#sent == before and queries == old_queries and requests == old_requests, "callbacks captured by the previous world are inert")
changed(1); assert(#sent == before and queries == old_queries, "reset must not retain a legacy subscriber")
snapshot_request(1); assert(queries == old_queries + 1 and #sent == before + 1)

before = #sent
during_snapshot = function() bus.reset(); install() end
snapshot_request(1)
assert(#sent == before, "a reset during projection cannot publish the old world's reply")
before = #sent
during_snapshot = function() players[1] = { id = 1, replacement = true } end
snapshot_request(1)
assert(#sent == before, "a replacement owner during projection cannot receive the old reply")

print("HERO_UI_LEGACY_SUBSCRIPTION_PASS real bus/generation+six-hero projection; 1000 cold/bound events zero UI projection/send; four owners, reentry, ordinary authority and shop dedup")
