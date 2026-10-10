-- Integrated summon transaction: real event bus, summon system, placeholder
-- lifecycle, catalog and native ability factory. Only engine/rendering and
-- asynchronous resource/destination boundaries are mocked here; geometry has
-- its own destination tests. Run from the addon root with Lua 5.1 or newer.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local heroes = require("config/generated/hero_definitions")
local definition = assert(heroes.by_id.hero_doom)
local hero_id = definition.hero_id
local effects = require("systems/rogue_effect_state_service")
local ctx, anchor
local function count(name)
    ctx.calls[name] = (ctx.calls[name] or 0) + 1
end
local function calls(name) return ctx.calls[name] or 0 end
local function eq(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

class = function(value) return value end
IsServer = function() return true end
UF_SUCCESS, UF_FAIL_CUSTOM = 0, 1
DOTA_UNIT_CAP_NO_ATTACK, DOTA_UNIT_CAP_MOVE_NONE = 0, 0
Vector = function(x, y, z) return {x = x, y = y, z = z or 0} end

package.loaded["systems/unit_health_bar_service"] = {
    exclude = function(unit) unit.health_bar_excluded = true end,
}
package.loaded["core/modifier_registry"] = {
    ensure = function(unit, name, args)
        return unit:AddNewModifier(unit, nil, name, args)
    end,
}
package.loaded["systems/hero_stat_adapter"] = {apply = function(unit, row)
    count("stats")
    eq(row, definition, "real hero definition reaches stat adapter")
    unit.stats_applied = true
end}
package.loaded["systems/hero_cosmetic_service"] = {
    apply = function() count("cosmetics") end,
    clear = function(unit) count("cosmetic_clear"); ctx.cleared_hero = unit end,
}
local projection = require("systems/hero_summon_projection")
projection.entitlements = function() return {vip = ctx.vip == nil and 1 or ctx.vip} end
projection.update_altar = function() count("altar_updates") end
package.loaded["systems/hero_asset_preload_service"] = {
    is_ready = function(id) eq(id, hero_id); return ctx.assets_ready end,
    request = function(id, callbacks)
        eq(id, hero_id)
        count("preload_requests")
        ctx.preload = callbacks
        return true, "hero_resource_loading"
    end,
}
package.loaded["systems/hero_summon_destination"] = {
    resolve = function(altar, row, player_id, moving_unit, options)
        count("resolve")
        eq(altar, ctx.altar or ctx.builder)
        eq(row, definition)
        eq(player_id, 0)
        eq(moving_unit, nil)
        eq(options.allow_without_city, true)
        eq(options.anchor_source, ctx.altar and "hero_altar" or "builder")
        if not ctx.destination then return nil, "hero_spawn_blocked" end
        return ctx.destination, nil
    end,
}
package.loaded["systems/destination_validation_service"] = {
    teleport = function(unit, position, find_clear_space)
        count("teleport")
        ctx.teleport_position = position
        eq(find_clear_space, false, "do not replace the validated landing point")
        if ctx.teleport_fails then return false, "hero_landing_failed" end
        unit:SetAbsOrigin(position)
        return true
    end,
}

local function entity(name)
    ctx.next_index = ctx.next_index + 1
    local unit = {name = name, index = ctx.next_index, modifiers = {},
        owner_id = 0, origin = Vector(0, 0, 0), controllable = true}
    function unit:IsNull() return self.removed == true end
    function unit:IsAlive() return not self.dead end
    function unit:entindex() return self.index end
    function unit:GetUnitName() return self.name end
    function unit:GetPlayerOwnerID() return self.owner_id end
    function unit:SetPlayerID(id) self.owner_id = id end
    function unit:SetOwner(owner) self.owner = owner end
    function unit:SetControllableByPlayer(_, value) self.controllable = value end
    function unit:AddNoDraw() self.hidden = true end
    function unit:RemoveNoDraw() self.hidden = false end
    function unit:SetAttackCapability(value) self.attack_capability = value end
    function unit:SetMoveCapability(value) self.move_capability = value end
    function unit:SetAbsOrigin(value) self.origin = value end
    function unit:GetAbsOrigin() return self.origin end
    function unit:GetAbilityCount() return 0 end
    function unit:SetAbilityPoints(value) self.ability_points = value end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:AddNewModifier(_, _, name, args)
        self.modifiers[name] = args
        return args
    end
    return unit
end

PlayerResource = {
    IsValidPlayerID = function(_, id) return id == 0 end,
    GetTeam = function() return 2 end,
    GetPlayer = function() return ctx.player end,
    ReplaceHeroWithNoTransfer = function(_, id, name)
        eq(id, 0)
        if name == "npc_dota_hero_wisp" then
            eq(anchor.phase(id), "combat_ready", "deletion starts from the combat hero")
            if ctx.delete_fails then return nil end
        else
            eq(name, definition.unit_name)
            eq(anchor.phase(id), "replacing", "replacement requires a live transaction")
        end
        count("replace")
        -- The engine discards the previous carrier. Keeping it valid would
        -- conceal the original abort-after-replacement retry deadlock.
        ctx.selected.removed = true
        ctx.selected = entity(name)
        return ctx.selected
    end,
}
Entities = {FindByName = function()
    count("marker_reads")
    return ctx.old_marker
end}
CustomGameEventManager = {Send_ServerToPlayer = function(_, player, name, payload)
    eq(player, ctx.player)
    ctx.client_events[#ctx.client_events + 1] = {name = name, payload = payload}
end}

anchor = require("systems/hero_anchor_service")
local actual_begin = anchor.begin_replacement
anchor.begin_replacement = function(player_id)
    count("begin")
    return actual_begin(player_id)
end
local summon_system = require("systems/hero_summon_system")
local factory = require("abilities/hero_summon_ability_factory")
local altar_open = require("abilities/ability_open_hero_altar")

local function fixture(options)
    options = options or {}
    ctx = {calls = {}, next_index = 0, player = {}, assets_ready = true,
        destination = Vector(1280, -384, 384), client_events = {},
        summoned = {}, published = {}, unlocks = {}, notifications = {}}
    bus.reset()
    effects.reset()
    anchor.init()
    summon_system.init()
    ctx.selected = entity("npc_dota_hero_wisp")
    ctx.original = ctx.selected
    ctx.altar = options.altar_built ~= false and entity("npc_dota_hero_altar") or nil
    ctx.builder = entity("builder")
    ctx.old_marker = entity("old_hero_spawn_marker")
    ctx.old_marker.origin = Vector(1280, -384, -1024)
    assert(anchor.register_placeholder(0, ctx.selected))
    bus.emit(events.BUILDER_READY, {player_id = 0, team = 2, builder = ctx.builder})
    local city_level = options.city_level == nil and 10 or options.city_level
    if city_level > 0 then
        bus.emit(events.BUILDING_CREATED, {player_id = 0, team = 2,
            building_id = "main_city", level = city_level, unit = entity("city")})
    end
    if ctx.altar then
        bus.emit(events.BUILDING_CREATED, {player_id = 0, team = 2,
            building_id = "hero_altar", unit = ctx.altar})
    end
    bus.subscribe(events.HERO_SUMMONED, function(p) ctx.summoned[#ctx.summoned + 1] = p end)
    bus.subscribe(events.HERO_SUMMON_STATE_CHANGED, function(p) ctx.published[#ctx.published + 1] = p end)
    bus.subscribe(events.SHOP_UNLOCK_CHANGED, function(p) ctx.unlocks[#ctx.unlocks + 1] = p end)
    bus.subscribe(events.UI_NOTIFICATION, function(p) ctx.notifications[#ctx.notifications + 1] = p end)
    ctx.calls = {}
end
local function request(extra)
    local payload = {player_id = 0, hero_id = hero_id, source = "summon_flow_test"}
    for key, value in pairs(extra or {}) do payload[key] = value end
    local result, handler_error = bus.request(events.HERO_SUMMON_REQUEST, payload)
    assert(result, handler_error or "summon handler returned no result")
    return result
end
local function no_summon_publication()
    eq(#ctx.summoned, 0, "failed summon must not announce a combat hero")
    eq(#ctx.published, 0, "failed summon must not refresh successful summon UI")
    eq(#ctx.unlocks, 0, "failed summon must not unlock the shop")
    eq(#ctx.client_events, 0, "failed summon must not select the replacement")
    local result = bus.request(events.HERO_SUMMON_GET_REQUEST, {player_id = 0})
    eq(result.ok, false)
end
local function no_replacement()
    eq(calls("begin"), 0, "invalid position must not begin replacement")
    eq(calls("replace"), 0)
    eq(calls("teleport"), 0)
    eq(calls("stats"), 0)
    eq(calls("cosmetics"), 0)
    eq(anchor.phase(0), "placeholder")
    eq(ctx.selected, ctx.original)
    eq(ctx.original:IsNull(), false)
    no_summon_publication()
end
local function ability()
    local instance = factory.create(hero_id)
    instance.cooldown_refunds = 0
    function instance:GetCaster() return ctx.altar or ctx.builder end
    function instance:IsNull() return false end
    function instance:EndCooldown() self.cooldown_refunds = self.cooldown_refunds + 1 end
    return instance
end
local function error_notifications()
    local result = {}
    for _, item in ipairs(ctx.notifications) do
        if item.level == "error" then result[#result + 1] = item end
    end
    return result
end

-- 1. Placement uses the already grounded result, not the old marker height.
fixture()
local resolved = ctx.destination
local success = request()
eq(success.ok, true)
eq(calls("resolve"), 1)
eq(calls("marker_reads"), 0, "initialization must not reread the stale marker")
eq(ctx.teleport_position, resolved, "use the exact validated destination")
eq(ctx.selected:GetAbsOrigin().z, 384)
eq(calls("replace"), 1)
eq(anchor.phase(0), "combat_ready")
eq(ctx.selected.hidden, false)
eq(ctx.selected.survival_hero_id, hero_id)
eq(#ctx.summoned, 1)
eq(ctx.summoned[1].unit, ctx.selected)
eq(ctx.unlocks[1].unlocked, 1)
eq(ctx.client_events[1].name, "survival_select_unit")
eq(success.snapshot.hero_summoned, 1)
eq(request().ok, false, "only one successful summon is permitted")
eq(calls("replace"), 1)
eq(#ctx.summoned, 1)

-- 2. No traversable destination: no replacement, resource queue or UI mutation.
fixture()
ctx.destination = nil
ctx.assets_ready = false
local blocked = request()
eq(blocked.ok, false)
eq(blocked.error, "hero_spawn_blocked")
eq(calls("preload_requests"), 0)
no_replacement()

-- 3. The space can become occupied while asset loading is pending. Recheck it
-- before mutating the carrier; the same request can then be retried safely.
fixture()
ctx.assets_ready = false
local completion, completion_count = nil, 0
local pending = request({on_completed = function(result)
    completion, completion_count = result, completion_count + 1
end})
eq(pending.pending, true)
no_replacement()
ctx.destination, ctx.assets_ready = nil, true
ctx.preload.on_ready()
eq(calls("resolve"), 2, "asset readiness must trigger destination revalidation")
eq(completion_count, 1)
eq(completion.ok, false)
eq(completion.error, "hero_spawn_blocked")
no_replacement()
ctx.destination = Vector(1408, -384, 384)
eq(request().ok, true)
eq(ctx.teleport_position, ctx.destination)
eq(#ctx.summoned, 1)

-- 4. An engine landing failure after ReplaceHeroWithNoTransfer leaves the NEW
-- unit as an isolated retryable carrier, because the original no longer exists.
fixture()
ctx.teleport_fails = true
local failed = request()
eq(failed.ok, false)
eq(failed.error, "hero_landing_failed")
eq(calls("replace"), 1)
eq(ctx.original:IsNull(), true)
local failed_unit = ctx.selected
eq(failed_unit:IsNull(), false)
eq(anchor.phase(0), "placeholder")
eq(failed_unit.hidden, true)
eq(failed_unit.controllable, false)
eq(failed_unit.attack_capability, DOTA_UNIT_CAP_NO_ATTACK)
eq(failed_unit.move_capability, DOTA_UNIT_CAP_MOVE_NONE)
eq(failed_unit:GetAbsOrigin().z, -10000)
eq(failed_unit.survival_hero_id, nil)
eq(failed_unit.survival_display_name, nil)
eq(failed_unit.health_bar_excluded, true)
no_summon_publication()
ctx.teleport_fails = false
eq(request().ok, true, "landing failure must not permanently lock summoning")
eq(calls("replace"), 2)
eq(failed_unit:IsNull(), true)
eq(anchor.phase(0), "combat_ready")
eq(#ctx.summoned, 1)

-- 5. Native ability: a deferred failure refunds THIS ability's cooldown and
-- reports one error. This catches an on_completed closure with no ability local.
fixture()
ctx.assets_ready = false
local native = ability()
eq(native:CastFilterResult(), UF_SUCCESS)
native:OnSpellStart()
eq(native.cooldown_refunds, 0, "loading is pending rather than a failed cast")
ctx.destination, ctx.assets_ready = nil, true
ctx.preload.on_ready()
eq(native.cooldown_refunds, 1, "asynchronous failure must refund the initiating ability")
local errors = error_notifications()
eq(#errors, 1)
eq(errors[1].message, "hero_spawn_blocked")
no_replacement()

-- 6. Asset failure already provides a friendly notification in the service;
-- the native completion must refund the cooldown without duplicating that error.
fixture()
ctx.assets_ready = false
native = ability()
native:OnSpellStart()
ctx.preload.on_failed("test_asset_failure")
eq(native.cooldown_refunds, 1)
errors = error_notifications()
eq(#errors, 1)
eq(errors[1].message, "英雄资源加载失败，请稍后重试")
no_replacement()

-- 7. A synchronous validation failure likewise refunds once and only notifies.
fixture()
ctx.destination = nil
native = ability()
native:OnSpellStart()
eq(native.cooldown_refunds, 1)
errors = error_notifications()
eq(#errors, 1)
eq(errors[1].message, "hero_spawn_blocked")
no_replacement()

-- 8. Delete returns the player to a hidden native carrier, releases the slot,
-- publishes the removed identity and allows repeated full summon transactions.
fixture()
local removed = {}
bus.subscribe(events.HERO_REMOVED, function(payload)
    removed[#removed + 1] = payload
    eq(bus.request(events.HERO_SUMMON_GET_REQUEST, {player_id = 0}).ok, false,
        "removed hero is unavailable before lifecycle cleanup runs")
end)
for iteration = 1, 3 do
    eq(request().ok, true)
    local old_hero, old_index = ctx.selected, ctx.selected:entindex()
    local deleted = assert(bus.request(events.HERO_DELETE_REQUEST, {player_id = 0}))
    eq(deleted.ok, true)
    eq(deleted.removed, true)
    eq(deleted.snapshot.hero_summoned, 0)
    eq(old_hero:IsNull(), true)
    eq(ctx.cleared_hero, old_hero)
    eq(removed[iteration].unit, old_hero)
    eq(removed[iteration].entindex, old_index)
    eq(anchor.phase(0), "placeholder")
    eq(ctx.selected:GetUnitName(), "npc_dota_hero_wisp")
    eq(ctx.selected.hidden, true)
    eq(ctx.selected.controllable, false)
    eq(ctx.selected:GetAbsOrigin().z, -10000)
    eq(ctx.selected.survival_hero_id, nil)
    eq(ctx.selected.survival_deleted_hero_placeholder, true)
    eq(bus.request(events.HERO_DELETE_REQUEST, {player_id = 0}).ok, true,
        "repeated deletion is harmless")
    eq(#removed, iteration, "no duplicate removal lifecycle")
end
eq(request().ok, true)

-- 9. Failed native deletion keeps the original summon and anchor intact.
fixture(); eq(request().ok, true)
local retained = ctx.selected
ctx.delete_fails = true
eq(bus.request(events.HERO_DELETE_REQUEST, {player_id = 0}).ok, false)
eq(ctx.selected, retained)
eq(retained:IsNull(), false)
eq(anchor.phase(0), "combat_ready")
eq(bus.request(events.HERO_SUMMON_GET_REQUEST, {player_id = 0}).unit, retained)
eq(calls("cosmetic_clear"), 0)
ctx.delete_fails = false
eq(bus.request(events.HERO_DELETE_REQUEST, {player_id = 0}).ok, true)
eq(request().ok, true)

-- 10. Deleting during preload cancels exactly once. Late asset callbacks may
-- not summon the cancelled hero or execute the old test-resource completion.
fixture(); ctx.assets_ready = false
local cancelled_count, cancellation = 0, nil
eq(request({on_completed = function(result)
    cancelled_count, cancellation = cancelled_count + 1, result
end}).pending, true)
local stale_preload = ctx.preload
local cancelled = bus.request(events.HERO_DELETE_REQUEST, {player_id = 0})
eq(cancelled.ok, true); eq(cancelled.cancelled, true)
eq(cancelled_count, 1); eq(cancellation.cancelled, true)
ctx.assets_ready = true
stale_preload.on_ready(); stale_preload.on_failed("late")
eq(cancelled_count, 1); eq(calls("replace"), 0)
eq(request().ok, true)
stale_preload.on_ready()
eq(#ctx.summoned, 1)

local function snapshot()
    return assert(bus.request(events.HERO_SUMMON_SNAPSHOT_REQUEST, {player_id = 0})).snapshot
end
local function open_ability()
    return setmetatable({GetCaster = function() return ctx.altar or ctx.builder end}, {__index = altar_open})
end

-- 11. The free construction charge is consumed before BUILDING_CREATED. The
-- completed early altar must still enable native casts and the summon itself.
fixture({city_level = 0, altar_built = false})
effects.add_numeric(0, "builder_free_hero_altar", 1)
assert(effects.consume_numeric(0, "builder_free_hero_altar", 1))
ctx.altar = entity("npc_dota_hero_altar")
bus.emit(events.BUILDING_CREATED, {player_id = 0, building_id = "hero_altar", unit = ctx.altar})
eq(snapshot().city_level, 0); eq(snapshot().summon_unlocked, 1)
eq(snapshot().summon_unlock_source, "hero_altar")
eq(ability():CastFilterResult(), UF_SUCCESS)
eq(open_ability():CastFilterResult(), UF_SUCCESS)
eq(request().ok, true)
eq(effects.numeric(0, "builder_free_hero_altar"), 0)

-- 12. An owner's rogue unlock enables a direct summon before either building,
-- refreshes the snapshot immediately and does not consume the build charge.
fixture({city_level = 0, altar_built = false})
eq(snapshot().summon_unlocked, 0)
effects.add_numeric(0, "builder_free_hero_altar", 1)
bus.emit(events.ROGUE_REWARD_CHANGED, {player_id = 0})
eq(#ctx.published, 1); eq(ctx.published[1].reason, "rogue_unlock_changed")
eq(ctx.published[1].summon_unlocked, 1); eq(ctx.published[1].altar_built, 0)
eq(ability():CastFilterResult(), UF_SUCCESS)
eq(open_ability():CastFilterResult(), UF_SUCCESS)
eq(request().ok, true); eq(effects.numeric(0, "builder_free_hero_altar"), 1)
eq(request().ok, false, "early unlock does not permit a second hero")
eq(open_ability():CastFilterResult(), UF_FAIL_CUSTOM)

-- 13. Normal altar unlock also enables a summon without requiring construction.
fixture({city_level = 3, altar_built = false})
eq(snapshot().altar_built, 0); eq(snapshot().summon_unlocked, 1)
eq(snapshot().summon_unlock_source, "city_level")
eq(ability():CastFilterResult(), UF_SUCCESS); eq(request().ok, true)

-- 14. No unlock, including another player's rogue effect, must fail closed.
fixture({city_level = 2, altar_built = false})
effects.add_numeric(1, "builder_free_hero_altar", 1)
bus.emit(events.ROGUE_REWARD_CHANGED, {player_id = 1})
eq(snapshot().summon_unlocked, 0)
eq(ability():CastFilterResult(), UF_FAIL_CUSTOM)
eq(open_ability():CastFilterResult(), UF_FAIL_CUSTOM)
eq(request().ok, false); eq(calls("resolve"), 0); no_replacement()

-- 15. Losing the early unlock while preloading revalidates before replacement.
fixture({city_level = 0, altar_built = false})
effects.add_numeric(0, "builder_free_hero_altar", 1)
ctx.assets_ready = false
local revoked
eq(request({on_completed = function(result) revoked = result end}).pending, true)
effects.set_numeric(0, "builder_free_hero_altar", 0)
ctx.assets_ready = true; ctx.preload.on_ready()
eq(revoked.ok, false); eq(calls("resolve"), 1); no_replacement()

-- 16. Rogue stage eligibility does not grant a paid/VIP hero's access.
fixture({city_level = 0, altar_built = false})
effects.add_numeric(0, "builder_free_hero_altar", 1)
ctx.vip = 0
eq(request({hero_id = "hero_monkey_king", vip = 1}).ok, false)
eq(calls("preload_requests"), 0); eq(calls("resolve"), 0); no_replacement()

-- 17. Stage qualification is private and cannot use a foreign/dead builder.
fixture({city_level = 0, altar_built = false})
effects.add_numeric(0, "builder_free_hero_altar", 1)
ctx.builder.owner_id = 1
eq(request().ok, false); eq(calls("resolve"), 0); no_replacement()
ctx.builder.owner_id = 0; ctx.builder.dead = true
eq(request().ok, false); eq(calls("resolve"), 0); no_replacement()

-- 18. Grant consumption during preload is allowed when the altar has finished.
fixture({city_level = 0, altar_built = false})
effects.add_numeric(0, "builder_free_hero_altar", 1); ctx.assets_ready = false
local completed
eq(request({on_completed = function(result) completed = result end}).pending, true)
assert(effects.consume_numeric(0, "builder_free_hero_altar", 1))
ctx.altar = entity("npc_dota_hero_altar")
bus.emit(events.BUILDING_CREATED, {player_id = 0, building_id = "hero_altar", unit = ctx.altar})
ctx.assets_ready = true; ctx.preload.on_ready()
eq(completed.ok, true); eq(calls("replace"), 1)

print("test_hero_summon_flow: PASS (18 integrated summon, rogue unlock, deletion/retry and native ability scenarios)")
