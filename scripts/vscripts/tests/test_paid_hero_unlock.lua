-- Real profile event, altar projection, nettable publication and summon validation.
-- Engine spawning is stopped at the independently tested destination boundary.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local profiles, vip, last_state, altars = {}, {}, {}, {}
GameRules = {GetGameTime = function() return 0 end}
local destination_calls = 0
local runtime_writes, event_errors = {}, {}
local original_print = print
print = function(message, ...)
    if tostring(message):find("[EventBus] handler error", 1, true) then
        event_errors[#event_errors + 1] = tostring(message)
    end
    original_print(message, ...)
end
CustomNetTables = { SetTableValue = function(_, name, key, value)
    if name == "survival_ability_runtime" then runtime_writes[key] = value end
end }
PlayerResource = { IsValidPlayerID = function(_, id)
    return type(id) == "number" and id >= 0 and id <= 2
end }
package.loaded["systems/hero_stat_adapter"] = {}
package.loaded["systems/hero_cosmetic_service"] = {}
package.loaded["systems/hero_anchor_service"] = {}
package.loaded["systems/destination_validation_service"] = {}
package.loaded["systems/hero_asset_preload_service"] = {}
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return false end,
    is_owned_by = function(id, unit) return unit:GetPlayerOwnerID() == id end,
}
package.loaded["systems/hero_summon_destination"] = { resolve = function()
    destination_calls = destination_calls + 1
    return nil, "test_destination_checked"
end }
local access = require("systems/hero_summon_access")
local projection = require("systems/hero_summon_projection")
local system = require("systems/hero_summon_system")
local heroes = require("config/generated/hero_definitions")
local runtime_service = require("ui/ability_runtime_service")
local runtime_builder = require("ui/ability_runtime_builder")
local function profile(items, mode)
    return { mode = mode or "standard", save = {content_inventory = items or {}} }
end
local function altar(id)
    local result = {abilities = {}, slots = {}}
    function result:IsNull() return false end
    function result:entindex() return 100 + id end
    function result:GetTeamNumber() return 2 end -- Teammates must stay independent.
    function result:GetPlayerOwnerID() return id end
    function result:GetAbilityCount() return #self.slots end
    function result:GetAbilityByIndex(slot) return self.slots[slot + 1] end
    function result:FindAbilityByName(name)
        if not self.abilities[name] then
            local index = 1000 + id * 100 + #self.slots
            self.abilities[name] = {
                IsNull = function() return false end,
                GetAbilityName = function() return name end,
                GetLevel = function(a) return a.level or 1 end,
                SetLevel = function(a, value) a.level = value end,
                IsActivated = function(a) return a.activated == true end,
                entindex = function() return index end,
                SetActivated = function(a, value) a.activated = value end,
                SetHidden = function(a, value) a.hidden = value end,
            }
            self.slots[#self.slots + 1] = self.abilities[name]
        end
        return self.abilities[name]
    end
    result:FindAbilityByName("ability_summon_monkey_king")
    result:FindAbilityByName("ability_summon_blademaster")
    result:FindAbilityByName("ability_summon_doom")
    return result
end
local function runtime(id, name)
    local a = altars[id]:FindAbilityByName(name or "ability_summon_monkey_king")
    local value = assert(runtime_writes[tostring(a:entindex())], "missing altar nettable")
    assert(value.hero_summon == 1 and value.summon_player_id == id,
        "paid hero UI must receive the explicit decision for this player")
    return value
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
-- Same order as addon_game_mode: UI registers before the summon system.
runtime_service.init()
system.init()
profiles[0], profiles[1] = profile(), profile({lottery_monkey_king = 1})
for id = 0, 2 do
    altars[id] = altar(id)
    bus.emit(events.BUILDING_CREATED, {player_id = id, building_id = "main_city", level = 3})
    bus.emit(events.BUILDING_CREATED, {player_id = id, building_id = "hero_altar", unit = altars[id]})
end
assert(available(0) == 0 and not active(0))
assert(available(1) == 1 and active(1), "paid inventory must unlock the owner's altar")
assert(available(2) == 0 and not active(2), "missing profile must not inherit another player's purchase")
assert(available(1, "hero_blademaster") == 0, "single hero purchase must not grant other VIP heroes")
assert(available(0, "hero_doom") == 1, "free heroes remain free")
assert(runtime(0).available == 0 and runtime(1).available == 1 and runtime(2).available == 0,
    "actual client nettable must match each player's paid ownership")
assert(runtime(1).status_text == "可召唤", "paid UI must leave the syncing state")
assert(runtime(1, "ability_summon_blademaster").available == 0)
assert(runtime(0, "ability_summon_doom").available == 1)
bus.emit(events.BUILDING_CHANGED, {player_id = 1, building_id = "main_city", level = 0})
assert(runtime(1).available == 1 and active(1),
    "real altar nettable/native ability stays available below the normal city threshold")
local client_fixtures = {
    owned = runtime(1), unowned = runtime(0), unloaded = runtime(2),
    other_hero = runtime(1, "ability_summon_blademaster"),
}
assert(not summon(0).ok and destination_calls == 0, "unowned direct requests must be rejected")
assert(summon(1).error == "test_destination_checked" and destination_calls == 1,
    "authoritative summon validation must accept the same owner as the UI")
assert(profiles[1].save.content_inventory.lottery_monkey_king == 1 and vip[1] == nil)

profiles[0].save.content_inventory.lottery_monkey_king = 1
local teammate_before = runtime(1)
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0, reason = "payment_delivered"})
assert(active(0) and available(0) == 1 and last_state[0].reason == "profile_changed",
    "payment profile refresh must enable an already-built altar")
assert(available(2) == 0 and available(0, "hero_blademaster") == 0)
assert(runtime(0).available == 1 and runtime(1) == teammate_before,
    "profile events update the owner's UI immediately, not their teammates")
profiles[0].save.content_inventory.lottery_monkey_king = nil
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
assert(not active(0) and available(0) == 0, "ownership removal must not leave a cached unlock")
assert(runtime(0).available == 0, "client decision must revoke with the profile")
client_fixtures.revoked = runtime(0)

profiles[1] = profile({}, "pure")
profiles[1].account_profile = profile({lottery_monkey_king = 1})
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 1})
assert(not active(1) and available(1) == 0, "pure mode must use the match view, not old account rewards")
assert(runtime(1).available == 0, "pure mode filtering also reaches the real UI")
client_fixtures.pure = runtime(1)
profiles[1].save.content_inventory.lottery_monkey_king = 1
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 1})
assert(active(1) and available(1) == 1, "a newly delivered match reward can unlock in pure mode")
assert(runtime(1).available == 1)
profiles[1] = nil
bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 1})
assert(not active(1), "unloaded/replaced player profile must not retain ownership")
assert(runtime(1).available == 0)

for _, invalid in ipairs({0, -1, 0.5, "1", true, {}, math.huge, 0/0}) do
    assert(not access.check(heroes.by_id.hero_monkey_king,
        {inventory = {lottery_monkey_king = invalid}}), "invalid inventory quantity must fail closed")
end
vip[0] = 1
bus.emit(events.PLAYER_ENTITLEMENT_CHANGED, {player_id = 0})
assert(active(0) and available(0, "hero_blademaster") == 1, "existing VIP access remains valid")
assert(runtime(0, "ability_summon_blademaster").available == 1)
projection.update_altar(0, altars[0], true)
assert(not active(0) and altars[0]:FindAbilityByName("ability_summon_monkey_king").hidden,
    "ownership must not bypass the one-hero-per-match restriction")
local snapshot = projection.build(0, altars[0], 3, {hero_id = "hero_monkey_king"})
local view_state = {player_id = 0, hero_summon_snapshot = snapshot}
assert(runtime_builder.build("ability_summon_monkey_king", view_state).available == 0,
    "one hero per match also locks the UI")
snapshot.hero_summoned, snapshot.city_level = 0, 2
assert(runtime_builder.build("ability_summon_monkey_king", view_state).available == 1,
    "a completed early altar bypasses the ordinary city threshold")
view_state.hero_summon_snapshot = projection.build(0, nil, 2, nil)
assert(runtime_builder.build("ability_summon_monkey_king", view_state).available == 0,
    "paid ownership alone does not unlock the altar stage")
view_state.hero_summon_snapshot = projection.build(0, nil, 3, nil)
assert(runtime_builder.build("ability_summon_monkey_king", view_state).available == 1,
    "altar build eligibility permits direct summoning")
view_state.hero_summon_snapshot.player_id = 1
assert(runtime_builder.build("ability_summon_monkey_king", view_state).available == 0,
    "a mismatched owner's snapshot cannot unlock the button")
assert(runtime_builder.build("ability_summon_monkey_king", {player_id = 0}).available == 0,
    "no snapshot must fail closed before initial publication")
assert(#event_errors == 0, table.concat(event_errors, "\n"))
if arg and arg[1] == "--client-fixtures" then
    print("HERO_RUNTIME_FIXTURES:" .. require("core/json_encoder").encode(client_fixtures))
end
print("PAID_HERO_UNLOCK_PASS")
