-- Full production router/event bus; engine entities and the training service
-- boundary are isolated. The separate service tests own fees/teleport rules.
-- Optional argv[1] loads an immutable pre-fix router to reproduce native-order
-- acceptance without OnSpellStart. No Dota, networking or filesystem writes.
package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
package.loaded["config/test_access"] = {enabled = false}
local checks, handler_errors = 0, 0
local original_print = print
print = function(...)
    local text = tostring(select(1, ...))
    if text:find("handler error", 1, true) then handler_errors = handler_errors + 1 end
end
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local listeners, packets, notices, entities = {}, {}, {}, {}
local admitted, defeated = {[0] = true, [1] = true}, {}
local handles = {[0] = {}, [1] = {}}
local counts = {enter = 0, cast = 0, timer = 0, start = 0, finish = 0}
PlayerResource = {
    IsValidPlayerID = function(_, id) return handles[id] ~= nil end,
    GetPlayer = function(_, id) return handles[id] end,
    GetTeam = function() return 2 end,
}
GameRules = {GetGameTime = function() return 100 end, GetGameModeEntity = function()
    return {SetContextThink = function() counts.timer = counts.timer + 1 end}
end}
CustomGameEventManager = {
    RegisterListener = function(_, name, callback) listeners[name] = callback end,
    Send_ServerToPlayer = function(_, player, name, payload)
        packets[#packets + 1] = {player = player, name = name, payload = payload}
    end,
    Send_ServerToAllClients = function() error("altar travel cannot broadcast") end,
}
package.loaded["systems/startup_loading_service"] = {
    is_player_ready = function(id) return admitted[id] == true end,
}
package.loaded["systems/multiplayer_player_service"] = {
    is_defeated = function(id) return defeated[id] == true end,
}
for _, name in ipairs({"systems/building_system", "ui/weapon_synthesis_snapshot_service",
    "ui/combat_stat_projection", "config/asset_catalog", "systems/hero_summon_projection",
    "systems/building_batch_upgrade_service", "systems/gold_mine_batch_upgrade_service"}) do
    package.loaded[name] = {}
end
package.loaded["systems/hero_summon_projection"].hero_id_for_summon_ability = function() return nil end
local service_result, service_hook = {ok = true}, nil
local last_call
package.loaded["systems/training_room_service"] = {
    enter = function(...)
        eq(select("#", ...), 2, "only server identity and fixed action reach service")
        counts.enter = counts.enter + 1
        last_call = {...}
        if service_hook then service_hook() end
        return service_result
    end,
}
EntIndexToHScript = function(index) return entities[index] end
DOTA_ABILITY_BEHAVIOR_POINT = 16
bit = {band = function(value, mask) return value == mask and mask or 0 end}
local function make_altar(owner, index)
    local unit = {survival_player_id = owner, survival_building_id = "hero_altar", abilities = {}}
    function unit:IsNull() return self.removed == true end
    function unit:GetPlayerOwnerID() return owner end
    function unit:FindAbilityByName(name) return self.abilities[name] end
    function unit:CastAbilityNoTarget() counts.cast = counts.cast + 1 end -- intentionally no OnSpellStart
    entities[index] = unit
    local function add(name, ability_index)
        local ability = {name = name, caster = unit, active = true, level = 1, cooldown = 0}
        function ability:IsNull() return self.removed == true end
        function ability:GetAbilityName() return self.name end
        function ability:GetCaster() return self.caster end
        function ability:IsPassive() return self.passive == true end
        function ability:GetBehaviorInt() return self.behavior or 516 end
        function ability:GetLevel() return self.level end
        function ability:GetCooldown() return 1 end
        function ability:GetCooldownTimeRemaining() return self.cooldown end
        function ability:IsFullyCastable() return self.cooldown == 0 and not self.uncastable end
        function ability:IsActivated() return self.active end
        function ability:IsHidden() return self.hidden == true end
        function ability:StartCooldown(value)
            counts.start = counts.start + 1
            eq(value, 1, "native configured cooldown")
            self.cooldown = value
        end
        function ability:EndCooldown() counts.finish = counts.finish + 1; self.cooldown = 0 end
        function ability:OnSpellStart() error("direct route cannot also trigger native payment") end
        unit.abilities[name], entities[ability_index] = ability, ability
        return ability
    end
    return unit, add
end
local altar0, add0 = make_altar(0, 100)
local endless = add0("ability_enter_endless_training", 101)
local shadow = add0("ability_enter_shadow_realm", 102)
local altar1, add1 = make_altar(1, 200)
local other = add1("ability_enter_endless_training", 201)
local ordinary = add0("ability_fixture_no_target", 103)
local bus, events = require("core/event_bus"), require("core/events")
bus.reset()
local router = arg and arg[1] and dofile(arg[1]) or require("ui/ui_request_router")
router.init()
bus.subscribe(events.UI_NOTIFICATION, function(payload) notices[#notices + 1] = payload end)
local listener = assert(listeners.ui_ability_cast_request)
local function request(id, unit, ability, fields)
    local payload = {PlayerID = id, entindex = unit or 100, ability_entindex = ability or 101}
    for key, value in pairs(fields or {}) do payload[key] = value end
    listener(nil, payload)
end
local function result(id, success)
    local packet = packets[#packets]
    eq(packet.name, "ui_ability_cast_result", "actual result channel")
    eq(packet.player, handles[id], "private result owner")
    eq(packet.payload.success, success, "actual service result")
    return packet.payload
end
request(0)
eq(counts.enter, 1, "native order alone cannot report travel success")
eq(counts.cast, 0, "direct travel never issues duplicate native cast")
eq(counts.timer, 0, "direct travel adds no diagnostic timer")
eq(last_call[1], 0, "trusted player")
eq(last_call[2], "altar_endless_training", "endless fixed mapping")
eq(counts.start, 1, "one native cooldown start")
eq(counts.finish, 0, "successful cooldown retained")
eq(#packets, 1, "success adds only existing result packet")
eq(#notices, 0, "no duplicate success notification")
result(0, 1)

-- The ordinary native cooldown gate prevents immediate duplicate spends and
-- must not be cleared by a rejected click while already cooling down.
request(0)
eq(counts.enter, 1, "cooldown request cannot enter")
eq(endless.cooldown, 1, "rejected click cannot cancel existing cooldown")
eq(counts.finish, 0, "rejected click does not EndCooldown")
result(0, 0)
endless.cooldown = 0
request(0, 100, 102, {player_id = 1, action_id = "altar_endless_training", cost_gold = 0, free = true})
eq(last_call[1], 0, "forged player ignored")
eq(last_call[2], "altar_shadow_realm", "forged action ignored")
result(0, 1)
request(1, 200, 201, {player_id = 0, action_id = "altar_shadow_realm"})
eq(last_call[1], 1, "second player isolated")
eq(last_call[2], "altar_endless_training", "second player's fixed action")
result(1, 1)

-- Authoritative service failures, including ten-ascension and funds gates,
-- reach the user exactly once; no false success and no held cooldown.
for _, failure in ipairs({{ok = false, error = "金币不足"}, {ok = false, error = "需要英雄10转"},
    {ok = false, error = "目的地无效"}, {ok = false}, {ok = 1, error = "非布尔成功"}}) do
    endless.cooldown = 0
    service_result = failure
    local entered, finished, notified, emitted = counts.enter, counts.finish, #notices, #packets
    request(0, nil, nil, {ignore_rebirth = true, ignore_cooldown = true, gold = 999999})
    eq(counts.enter, entered + 1, "one authoritative attempt")
    eq(counts.finish, finished + 1, "failed attempt ends started cooldown")
    eq(endless.cooldown, 0, "failure leaves ability retryable")
    eq(#notices, notified + 1, "one visible failure event")
    eq(notices[#notices].player_id, 0, "failure private identity")
    eq(notices[#notices].message, failure.error or "传送失败", "service failure text preserved")
    eq(notices[#notices].level, "error", "failure severity")
    eq(#packets, emitted + 2, "one notification plus one result")
    eq(packets[#packets - 1].name, "ui_notification", "real notification bridge")
    result(0, 0)
end
service_result = nil
request(0)
eq(result(0, 0).error, "传送失败", "nil result fails closed")
eq(endless.cooldown, 0, "nil result rolls back cooldown")
service_result = {ok = true}

local function reject(label, mutate, restore, unit_index, ability_index)
    endless.cooldown = 0
    local entered, cast, starts, finished = counts.enter, counts.cast, counts.start, counts.finish
    mutate()
    request(0, unit_index, ability_index, {player_id = 1, free = true, ignore_cooldown = true})
    eq(counts.enter, entered, label .. " no service entry")
    eq(counts.cast, cast, label .. " no fallback native order")
    eq(counts.start, starts, label .. " no cooldown start")
    eq(counts.finish, finished, label .. " no unrelated cooldown cancellation")
    result(0, 0)
    restore()
end
reject("foreign altar", function() end, function() end, 200, 201)
reject("non altar", function() altar0.survival_building_id = "city" end, function() altar0.survival_building_id = "hero_altar" end)
reject("wrong caster", function() endless.caster = altar1 end, function() endless.caster = altar0 end)
reject("unbound ability", function() altar0.abilities[endless.name] = shadow end, function() altar0.abilities[endless.name] = endless end)
reject("removed unit", function() altar0.removed = true end, function() altar0.removed = nil end)
reject("inactive", function() endless.active = false end, function() endless.active = true end)
reject("hidden", function() endless.hidden = true end, function() endless.hidden = nil end)
reject("unlearned", function() endless.level = 0 end, function() endless.level = 1 end)
reject("passive", function() endless.passive = true end, function() endless.passive = nil end)
reject("point target", function() endless.behavior = 16 end, function() endless.behavior = nil end)
reject("uncastable", function() endless.uncastable = true end, function() endless.uncastable = nil end)

local entered, packets_before = counts.enter, #packets
admitted[0] = false; request(0); admitted[0] = true
defeated[0] = true; request(0); defeated[0] = nil
request(-1); request(3); listener(nil, {player_id = 0}); listener(nil, nil)
eq(counts.enter, entered, "admission/defeat/invalid identity blocks service")
eq(#packets, packets_before, "closed gameplay gate does not acknowledge")

-- Starting the native cooldown before the synchronous authoritative call
-- prevents a reentrant request from charging the same ability again.
local reentered = false
service_hook = function()
    eq(endless.cooldown, 1, "cooldown precedes service dispatch")
    if not reentered then reentered = true; request(0) end
end
request(0)
service_hook = nil
eq(counts.enter, entered + 1, "reentrant request does not dispatch twice")
result(0, 1)
eq(counts.cast, 0, "all altar operations use service only")
eq(counts.timer, 0, "all altar operations add no timer")
local starts = counts.start
request(0, 100, 103)
eq(counts.cast, 1, "unrelated no-target native route unchanged")
eq(counts.timer, 1, "unrelated existing diagnostic timer retained")
eq(counts.start, starts, "unrelated route cooldown semantics unchanged")
result(0, 1)
eq(handler_errors, 0, "event bus did not swallow an assertion")
original_print("ALTAR_TRAVEL_ROUTER_PASS checks=" .. checks .. " travel_native_casts=0 travel_timers=0 service_calls=" .. counts.enter)
