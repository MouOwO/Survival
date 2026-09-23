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
}
package.loaded["systems/hero_summon_projection"] = {
    entitlements = function() return {vip = 1} end,
    update_altar = function() count("altar_updates") end,
    build = function(player_id, altar, city_level, summoned)
        return {player_id = player_id, city_level = city_level,
            altar_built = altar and not altar:IsNull() and 1 or 0,
            hero_summoned = summoned and 1 or 0,
            shop_unlocked = summoned and 1 or 0,
            heroes = {{hero_id = hero_id, available = summoned and 0 or 1}}}
    end,
}
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
    resolve = function(altar, row, player_id)
        count("resolve")
        eq(altar, ctx.altar)
        eq(row, definition)
        eq(player_id, 0)
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
        eq(name, definition.unit_name)
        eq(anchor.phase(id), "replacing", "replacement requires a live transaction")
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

local function fixture()
    ctx = {calls = {}, next_index = 0, player = {}, assets_ready = true,
        destination = Vector(1280, -384, 384), client_events = {},
        summoned = {}, published = {}, unlocks = {}, notifications = {}}
    bus.reset()
    anchor.init()
    summon_system.init()
    ctx.selected = entity("npc_dota_hero_wisp")
    ctx.original = ctx.selected
    ctx.altar = entity("npc_dota_hero_altar")
    ctx.old_marker = entity("old_hero_spawn_marker")
    ctx.old_marker.origin = Vector(1280, -384, -1024)
    assert(anchor.register_placeholder(0, ctx.selected))
    bus.emit(events.BUILDER_READY, {player_id = 0, team = 2, builder = entity("builder")})
    bus.emit(events.BUILDING_CREATED, {player_id = 0, team = 2,
        building_id = "main_city", level = 10, unit = entity("city")})
    bus.emit(events.BUILDING_CREATED, {player_id = 0, team = 2,
        building_id = "hero_altar", unit = ctx.altar})
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
    function instance:GetCaster() return ctx.altar end
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

print("test_hero_summon_flow: PASS (7 integrated summon and native ability scenarios)")
