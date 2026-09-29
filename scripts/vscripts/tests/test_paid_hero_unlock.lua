-- Real profile event, altar projection, native activation and summon validation.
-- Engine spawning is stopped at the independently tested destination boundary.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local profiles, vip, last_state, altars = {}, {}, {}, {}
local destination_calls = 0
PlayerResource = { IsValidPlayerID = function(_, id)
    return type(id) == "number" and id >= 0 and id <= 2
end }
package.loaded["systems/hero_stat_adapter"] = {}
package.loaded["systems/hero_cosmetic_service"] = {}
package.loaded["systems/hero_anchor_service"] = {}
package.loaded["systems/destination_validation_service"] = {}
package.loaded["systems/hero_asset_preload_service"] = {}
package.loaded["systems/player_context_service"] = { is_defeated = function() return false end }
package.loaded["systems/hero_summon_destination"] = { resolve = function()
    destination_calls = destination_calls + 1
    return nil, "test_destination_checked"
end }
local access = require("systems/hero_summon_access")
local projection = require("systems/hero_summon_projection")
local system = require("systems/hero_summon_system")
local heroes = require("config/generated/hero_definitions")
local function profile(items, mode)
    return { mode = mode or "standard", save = {content_inventory = items or {}} }
end
local function altar()
    local result = {abilities = {}}
    function result:IsNull() return false end
    function result:FindAbilityByName(name)
        if not self.abilities[name] then
            self.abilities[name] = {
                SetActivated = function(a, value) a.activated = value end,
                SetHidden = function(a, value) a.hidden = value end,
            }
        end
        return self.abilities[name]
    end
    return result
end
local function available(id, hero)
    local result = bus.request(events.HERO_SUMMON_SNAPSHOT_REQUEST, {player_id = id})
    for _, option in ipairs(result.snapshot.heroes) do
        if option.hero_id == (hero or "hero_monkey_king") then return option.available end
    end
    error("missing hero")
end
local function active(id)
    return altars[id]:FindAbilityByName("ability_summon_monkey_king").activated
end
local function summon(id, hero)
    return bus.request(events.HERO_SUMMON_REQUEST, {
        player_id = id, hero_id = hero or "hero_monkey_king",
        -- Client-supplied ownership/VIP assertions must not authorize a summon.
        vip = 1, content_inventory = {lottery_monkey_king = 1}, paid = true,
    })
end

bus.reset()
bus.handle_request(events.PLAYER_ENTITLEMENT_GET_REQUEST, function(p)
    return {ok = true, snapshot = {vip = vip[p.player_id] or 0}}
end)
bus.handle_request(events.PLAYER_PROFILE_GET_REQUEST, function(p)
    return {ok = profiles[p.player_id] ~= nil, profile = profiles[p.player_id]}
end)
bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function()
    return {ok = true, snapshot = {rebirth_level = 0}}
end)
bus.subscribe(events.HERO_SUMMON_STATE_CHANGED, function(p) last_state[p.player_id] = p end)
system.init()
profiles[0], profiles[1] = profile(), profile({lottery_monkey_king = 1})
for id = 0, 2 do
    altars[id] = altar()
    bus.emit(events.BUILDING_CREATED, {player_id = id, building_id = "main_city", level = 3})
    bus.emit(events.BUILDING_CREATED, {player_id = id, building_id = "hero_altar", unit = altars[id]})
end
assert(available(0) == 0 and not active(0))
assert(available(1) == 1 and active(1), "paid inventory must unlock the owner's altar")
assert(available(2) == 0 and not active(2), "missing profile must not inherit another player's purchase")
assert(available(1, "hero_blademaster") == 0, "single hero purchase must not grant other VIP heroes")
assert(available(0, "hero_doom") == 1, "free heroes remain free")
assert(not summon(0).ok and destination_calls == 0, "unowned direct requests must be rejected")
assert(summon(1).error == "test_destination_checked" and destination_calls == 1,
    "authoritative summon validation must accept the same owner as the UI")
assert(profiles[1].save.content_inventory.lottery_monkey_king == 1 and vip[1] == nil)

profiles[0].save.content_inventory.lottery_monkey_king = 1
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0, reason = "payment_delivered"})
assert(active(0) and available(0) == 1 and last_state[0].reason == "profile_changed",
    "payment profile refresh must enable an already-built altar")
assert(available(2) == 0 and available(0, "hero_blademaster") == 0)
profiles[0].save.content_inventory.lottery_monkey_king = nil
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
assert(not active(0) and available(0) == 0, "ownership removal must not leave a cached unlock")

profiles[1] = profile({}, "pure")
profiles[1].account_profile = profile({lottery_monkey_king = 1})
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 1})
assert(not active(1) and available(1) == 0, "pure mode must use the match view, not old account rewards")
profiles[1].save.content_inventory.lottery_monkey_king = 1
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 1})
assert(active(1) and available(1) == 1, "a newly delivered match reward can unlock in pure mode")
profiles[1] = nil
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 1})
assert(not active(1), "unloaded/replaced player profile must not retain ownership")

for _, invalid in ipairs({0, -1, 0.5, "1", true, {}, math.huge, 0/0}) do
    assert(not access.check(heroes.by_id.hero_monkey_king,
        {inventory = {lottery_monkey_king = invalid}}), "invalid inventory quantity must fail closed")
end
vip[0] = 1
bus.emit(events.PLAYER_ENTITLEMENT_CHANGED, {player_id = 0})
assert(active(0) and available(0, "hero_blademaster") == 1, "existing VIP access remains valid")
projection.update_altar(0, altars[0], true)
assert(not active(0) and altars[0]:FindAbilityByName("ability_summon_monkey_king").hidden,
    "ownership must not bypass the one-hero-per-match restriction")
print("PAID_HERO_UNLOCK_PASS")
