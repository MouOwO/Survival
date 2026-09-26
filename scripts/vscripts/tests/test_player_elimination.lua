package.path = "scripts/vscripts/?.lua;" .. package.path
-- Real multiplayer lifecycle, ownership registry, event bus and online service.
-- The engine and HTTP provider are isolated; no network or real account data.
local tasks, requests, handles, native_heroes, creatures = {}, {}, {}, {}, {}
local clock, in_flight_player, pending_checkpoint = 100, nil, nil
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS = 2, 3
GameRules = { GetGameTime = function() return clock end }
package.loaded["core/scheduler"] = {
    cancel = function(id) tasks[id] = nil end,
    after = function(delay, callback, id) tasks[id] = { delay = delay, callback = callback } end,
    every = function(delay, callback, id) tasks[id] = { delay = delay, callback = callback } end,
}
PlayerResource = {
    IsValidPlayerID = function(_, id) return handles[id] ~= nil end,
    GetPlayer = function(_, id) return handles[id] end,
    GetTeam = function() return DOTA_TEAM_GOODGUYS end,
    GetSelectedHeroEntity = function(_, id) return native_heroes[id] end,
}
HeroList = { GetAllHeroes = function() return { native_heroes[0], native_heroes[1] } end }
Entities = { FindAllByClassname = function() return creatures end }
UTIL_Remove = function(unit) unit.removed = true end
local provider = {
    resolve_account_id = function(id) return "simulation-account-" .. id end,
    online_checkpoint = function(payload, ok)
        requests[#requests + 1] = payload
        if in_flight_player ~= nil and payload.account_id == "simulation-account-" .. in_flight_player
            and not payload.final then
            pending_checkpoint = ok
        else
            ok({ grants = {} })
        end
    end,
}
package.loaded["systems/player_profile_service"] = { get_provider = function() return provider end }
local bus, events = require("core/event_bus"), require("core/events")
local context = require("systems/player_context_service")
local multiplayer = require("systems/multiplayer_player_service")
local online = require("systems/online_time_service")
local notices, defeat_events, cleanup_events, winner_calls = {}, 0, 0, 0
bus.subscribe(events.UI_NOTIFICATION, function(p) notices[#notices + 1] = p end)
bus.subscribe(events.PLAYER_DEFEATED, function(p)
    assert(multiplayer.is_defeated(p.player_id), "defeat must be visible before subscribers run")
    defeat_events = defeat_events + 1
    if multiplayer.all_participants_defeated() then winner_calls = winner_calls + 1 end
end)
bus.subscribe(events.PLAYER_DISCONNECTED, function(p)
    assert(p.defeat_cleanup == true and multiplayer.is_defeated(p.player_id))
    cleanup_events = cleanup_events + 1
end)
local function unit(index, player, hero, register)
    local value = { index = index, player = player, alive = true }
    function value:IsNull() return self.removed == true end
    function value:entindex() return self.index end
    function value:GetPlayerOwnerID() return self.player end
    function value:IsRealHero() return hero == true end
    function value:IsAlive() return self.alive end
    function value:ForceKill() self.alive = false end
    function value:Stop() self.stopped = true end
    function value:SetControllableByPlayer(id, allowed) self.controlled = allowed end
    function value:SetRespawnsDisabled(disabled) self.respawns_disabled = disabled end
    function value:AddNoDraw() self.hidden = true end
    if register then assert(context.register_unit(player, value, "fixture")) end
    return value
end
for id = 0, 3 do handles[id] = {}; multiplayer.mark_connected(id) end
native_heroes[0], native_heroes[1] = unit(10, 0, true), unit(11, 1, true)
local own, other, unknown = unit(20, 0, false, true), unit(21, 1, false, true), unit(22, 0, false)
creatures = { own, other, unknown }
online.init()
for id = 0, 3 do bus.emit(events.HERO_READY, { player_id = id }) end
assert(#requests == 4)
-- Disconnect has its existing 20-second grace; reconnection cancels that timer.
assert(multiplayer.mark_disconnected(1))
assert(tasks.player_disconnect_defeat_1.delay == 20 and cleanup_events == 0)
assert(multiplayer.mark_connected(1))
assert(tasks.player_disconnect_defeat_1 == nil and not multiplayer.is_defeated(1))
-- Defeat player 0 while their ordinary online checkpoint is in flight.
in_flight_player = 0
tasks.online_time_checkpoint.callback()
local before = #requests
assert(pending_checkpoint and multiplayer.defeat(0, "monster_limit_exceeded"))
assert(#requests == before, "final waits for the in-flight request without duplicating it")
assert(multiplayer.is_defeated(0) and not multiplayer.is_defeated(1))
assert(defeat_events == 1 and cleanup_events == 1 and winner_calls == 0)
assert(own.removed and not other.removed and not unknown.removed,
    "cleanup uses authoritative ownership, never team or unreliable native creature owner")
assert(not native_heroes[0].alive and native_heroes[0].hidden and native_heroes[0].respawns_disabled)
assert(native_heroes[0].controlled == false and native_heroes[1].alive and not native_heroes[1].hidden)
assert(#notices == 1 and notices[1].player_id == 0)
assert(not multiplayer.reject_defeated_unit(unknown), "spawn before ownership registration is not slot 0")
assert(context.register_unit(0, unknown, "late-owned-creature"))
assert(multiplayer.reject_defeated_unit(unknown) and unknown.removed)
in_flight_player = nil
pending_checkpoint({ grants = {} })
assert(#requests == before + 1 and requests[#requests].final == true)
assert(requests[#requests].account_id == "simulation-account-0")
assert(not multiplayer.defeat(0, "again") and #notices == 1)
multiplayer.mark_connected(0)
assert(multiplayer.is_defeated(0), "reconnection cannot revive an eliminated account")
local late_hero = unit(40, 0, true)
assert(multiplayer.reject_defeated_unit(late_hero) and not late_hero.alive and late_hero.respawns_disabled)
local count = #requests
bus.emit(events.HERO_READY, { player_id = 0, hero = late_hero })
assert(#requests == count, "late hero readiness cannot start a new online session")
tasks.online_time_checkpoint.callback()
assert(#requests == count + 3, "only the three survivors keep earning online time")
for i = count + 1, #requests do assert(not requests[i].final and requests[i].account_id ~= "simulation-account-0") end
local active = context.active_player_ids()
assert(#active == 3 and active[1] == 1 and active[2] == 2 and active[3] == 3)
for id = 1, 3 do
    assert(multiplayer.defeat(id, "monster_limit_exceeded"))
    assert(winner_calls == (id == 3 and 1 or 0), "only the final participant permits global defeat")
end
assert(defeat_events == 4 and cleanup_events == 4 and #notices == 4)
local finals = {}
for _, request in ipairs(requests) do
    if request.final then finals[request.account_id] = (finals[request.account_id] or 0) + 1 end
end
for id = 0, 3 do assert(finals["simulation-account-" .. id] == 1, "each personal online session finalizes once") end
assert(#context.active_player_ids() == 0)
print("PLAYER_ELIMINATION_PASS: real services, personal queued final, four-player isolation, grace/reconnect, strict ownership, late-spawn rejection and last-player result")