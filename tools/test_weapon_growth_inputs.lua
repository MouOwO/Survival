-- Real growth service and authored weapon progression; expensive source reads
-- are counted separately from exact per-hit growth snapshots.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local weapons = require("config/generated/weapon_definitions")
local HAMMER = "item_forging_hammer"
local function copy(value)
    local result = {}; for key, item in pairs(value or {}) do result[key] = item end; return result
end
local function harness()
    bus.reset()
    package.loaded["systems/weapon_growth_service"] = nil
    local h = {inventory_reads = 0, permanent_reads = 0, profile_reads = 0,
        counts = {[0] = {}, [1] = {}}, totals = {[0] = {}, [1] = {}},
        upgrades = {}, notifications = {}, profiles = {}, equipped = {}, publications = {}}
    package.loaded["systems/technology_stat_manager"] = {
        training_room_multiplier = function() return h.training_multiplier or 1 end,
    }
    package.loaded["systems/gameplay_phase_guard"] = {post_clear_frozen = function() return h.frozen == true end}
    package.loaded["systems/commerce_effects"] = {
        owned = function(_, key) return key == "growth_ring" and h.growth_ring == true end,
    }
    package.loaded["systems/player_profile_service"] = {
        get_profile = function(player_id)
            h.profile_reads = h.profile_reads + 1
            return h.profiles[player_id]
        end,
    }
    bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function(payload)
        h.permanent_reads = h.permanent_reads + 1
        if h.permanent_unavailable then return nil end
        if h.permanent_error then return {ok = false, totals = {}} end
        return {ok = true, totals = copy(h.totals[payload.player_id])}
    end)
    bus.handle_request(events.CONTENT_INVENTORY_GET_REQUEST, function(payload)
        h.inventory_reads = h.inventory_reads + 1
        if h.inventory_unavailable then return {ok = false} end
        return {ok = true, snapshot = {counts = copy(h.counts[payload.player_id])}}
    end)
    function h.inventory_event(player_id, changes, omit_snapshot)
        bus.emit(events.CONTENT_INVENTORY_CHANGED, {
            player_id = player_id, changes = changes or {}, reason = "test_inventory_commit",
            snapshot = not omit_snapshot and {counts = copy(h.counts[player_id])} or nil,
        })
    end
    function h.equip(player_id, id, reason)
        local previous = h.equipped[player_id]
        h.equipped[player_id] = id
        bus.emit(events.WEAPON_EQUIPPED_CHANGED, {player_id = player_id, slot = "main_hand",
            content_id = id, previous_content_id = previous, reason = reason or "test_equipped"})
    end
    bus.handle_request(events.CONTENT_INVENTORY_TRANSACTION_REQUEST, function(payload)
        if h.upgrade_failure then return {ok = false, error = "test_upgrade_failed"} end
        local counts = h.counts[payload.player_id]
        for id, amount in pairs(payload.consume) do
            assert((counts[id] or 0) >= amount); counts[id] = counts[id] - amount
        end
        for id, amount in pairs(payload.grant) do counts[id] = (counts[id] or 0) + amount end
        h.upgrades[#h.upgrades + 1] = payload
        h.inventory_event(payload.player_id)
        h.equip(payload.player_id, next(payload.grant), payload.reason)
        return {ok = true}
    end)
    bus.subscribe(events.WEAPON_GROWTH_CHANGED, function(payload)
        h.publications[#h.publications + 1] = payload
    end)
    bus.subscribe(events.UI_NOTIFICATION, function(payload) h.notifications[#h.notifications + 1] = payload end)
    h.service = require("systems/weapon_growth_service")
    h.service.init()
    function h.snapshot(player_id)
        return assert(bus.request(events.WEAPON_GROWTH_GET_REQUEST, {player_id = player_id or 0})).snapshot
    end
    function h.attacks(count, player_id, secondary)
        for _ = 1, count do
            bus.emit(events.HERO_MAIN_ATTACK_LANDED, {player_id = player_id or 0,
                is_main_attack = not secondary, target = {}})
        end
    end
    function h.hero(player_id)
        local hero = {IsNull = function() return false end, AddNewModifier = function() end}
        bus.emit(events.HERO_SUMMONED, {player_id = player_id, unit = hero})
        return hero
    end
    return h
end

-- Sparse authoritative totals override legacy profile values, including zero.
-- Repeated attacks and HUD/combat snapshot consumers do not copy inputs again.
do
    local h = harness()
    h.profiles[0] = {save = {gameplay_stats = {weapon_upgrade_requirement_reduction = 199}}}
    h.equip(0, "weapon_growth_sword_max")
    assert(h.snapshot().stage_attack_target == 0 and h.snapshot().is_max_level == 1 and h.profile_reads == 0)
    assert(h.inventory_reads == 1 and h.permanent_reads == 0)
    for _ = 1, 1000 do
        h.attacks(1)
        for _ = 1, 5 do h.snapshot() end
    end
    local result = h.snapshot()
    assert(result.lifetime_attack_count == 1000 and result.stage_attack_count == 1000
        and result.growth_attack == 1000 * weapons.by_id.weapon_growth_sword_max.attack_gain_per_attack)
    assert(#h.publications == 1001 and #h.upgrades == 0)
    assert(h.inventory_reads == 1 and h.permanent_reads == 0 and h.profile_reads == 0,
        "terminal growth retains every hit while skipping inapplicable upgrade requirements")
end

-- Hammer snapshots update immediately, including zero/removal and the cap of
-- four. Legacy inventory events without a snapshot invalidate just this input.
do
    local h = harness(); h.equip(0, "weapon_growth_sword_max")
    local initial_reads = h.inventory_reads
    for _, quantity in ipairs({2, 0, 9, 1}) do
        h.counts[0][HAMMER] = quantity
        h.inventory_event(0, {[HAMMER] = quantity})
        local current = h.snapshot()
        assert(current.forging_hammer_count == math.min(4, quantity)
            and current.progress_per_attack == 1 + math.min(4, quantity))
        assert(h.publications[#h.publications].snapshot.progress_per_attack == current.progress_per_attack)
    end
    assert(h.inventory_reads == initial_reads)
    h.counts[0][HAMMER] = 3; h.inventory_event(0, {[HAMMER] = 2}, true)
    assert(h.snapshot().forging_hammer_count == 3 and h.inventory_reads == initial_reads + 1)
    h.snapshot(); assert(h.inventory_reads == initial_reads + 1)
end

-- Real effects changes and profile reload ordering invalidate/update the
-- reduction independently of per-hit counters and independent player caches.
do
    local h = harness(); h.equip(0, "weapon_growth_sword_01"); h.equip(1, "weapon_growth_sword_01")
    h.attacks(3)
    local reads = h.permanent_reads
    h.totals[0] = {weapon_upgrade_requirement_reduction = 35}
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, totals = copy(h.totals[0])})
    assert(h.snapshot().stage_attack_target == 165 and h.snapshot(1).stage_attack_target == 200)
    h.totals[0] = {}
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, totals = {}})
    assert(h.snapshot().stage_attack_target == 200 and h.permanent_reads == reads)
    h.totals[0] = {weapon_upgrade_requirement_reduction = 1999}
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, reason = "unknown_new_effect"})
    assert(h.snapshot().stage_attack_target == 1 and h.permanent_reads == reads + 1)
    h.totals[0] = {weapon_upgrade_requirement_reduction = 10}
    h.counts[0][HAMMER] = 2
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, totals = copy(h.totals[0])})
    assert(h.snapshot().stage_attack_target == 190 and h.snapshot().forging_hammer_count == 2)
    h.totals[0] = {weapon_upgrade_requirement_reduction = 20}
    bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {player_id = 0, totals = copy(h.totals[0])})
    bus.emit(events.PLAYER_PROFILE_CHANGED, {player_id = 0})
    assert(h.snapshot().stage_attack_target == 180 and h.snapshot().lifetime_attack_count == 3)
    assert(h.snapshot(1).stage_attack_target == 200 and h.snapshot(1).forging_hammer_count == 0)
end

-- Missing/failed APIs retain legacy fallback but never cache it across service
-- availability. A temporarily unavailable inventory must not cache a false zero.
for _, unavailable in ipairs({"permanent_unavailable", "permanent_error"}) do
    local h = harness(); h[unavailable] = true; h.inventory_unavailable = true
    h.profiles[0] = {save = {gameplay_stats = {weapon_upgrade_requirement_reduction = 17}}}
    h.equip(0, "weapon_growth_sword_01")
    assert(h.snapshot().stage_attack_target == 183 and h.profile_reads > 0)
    h[unavailable], h.inventory_unavailable = false, false
    h.counts[0][HAMMER] = 2
    local result = h.snapshot()
    assert(result.stage_attack_target == 200 and result.forging_hammer_count == 2)
    local profile_reads, inventory_reads, permanent_reads = h.profile_reads, h.inventory_reads, h.permanent_reads
    h.attacks(10)
    assert(h.profile_reads == profile_reads and h.inventory_reads == inventory_reads
        and h.permanent_reads == permanent_reads)
end

-- Thresholds, hammer progress, training income and atomic failure recovery are
-- unchanged: four attacks advance 12/10 and retain two points after upgrade.
do
    local h = harness()
    h.totals[0].weapon_upgrade_requirement_reduction = 190
    h.counts[0] = {weapon_growth_sword_01 = 1, [HAMMER] = 2}
    h.training_multiplier = 2
    h.equip(0, "weapon_growth_sword_01")
    h.attacks(3); assert(#h.upgrades == 0 and h.snapshot().stage_attack_count == 9)
    h.attacks(1)
    local result = h.snapshot()
    assert(#h.upgrades == 1 and result.content_id == "weapon_growth_sword_02"
        and result.stage_attack_count == 2 and result.lifetime_attack_count == 4 and result.growth_attack == 8)
    h.attacks(1); assert(h.snapshot().growth_attack == 12 and h.snapshot().stage_attack_count == 5)
    h.upgrade_failure = true; h.attacks(2)
    assert(#h.upgrades == 1 and h.snapshot().stage_attack_count == 11,
        "failed upgrade restores all accumulated stage progress")
    h.upgrade_failure = false; h.attacks(1)
    assert(#h.upgrades == 2 and h.snapshot().content_id == "weapon_growth_sword_03"
        and h.snapshot().stage_attack_count == 4)
    assert(h.inventory_reads == 1 and h.permanent_reads == 1 and h.profile_reads == 0)
    local before = h.snapshot().lifetime_attack_count
    h.attacks(10, 0, true); h.frozen = true; h.attacks(10)
    assert(h.snapshot().lifetime_attack_count == before)
end

-- Damage-growth weapons still gain on every owned hero hit. Hero replacement
-- clears the small input cache and detached heroes cannot keep growing weapons.
do
    local h = harness(); h.equip(0, "weapon_ice_blade_01")
    local hero = h.hero(0)
    h.training_multiplier = 3
    for _ = 1, 1000 do
        bus.emit(events.COMBAT_DAMAGE_RESOLVED, {player_id = 0, attacker = hero,
            owner_hero = hero, final_damage = 10, target = {}})
    end
    assert(h.snapshot().growth_attack == 36000 and h.inventory_reads == 2
        and h.permanent_reads == 2 and h.profile_reads == 0)
    bus.emit(events.HERO_REMOVED, {player_id = 0, unit = hero})
    bus.emit(events.COMBAT_DAMAGE_RESOLVED, {player_id = 0, attacker = hero,
        owner_hero = hero, final_damage = 10, target = {}})
    assert(h.snapshot().growth_attack == 36000)
    h.counts[0][HAMMER] = 4
    h.totals[0].weapon_upgrade_requirement_reduction = 50
    h.hero(0)
    assert(h.snapshot().forging_hammer_count == 4 and h.snapshot().stage_attack_target == 150)
end
print("WEAPON_GROWTH_INPUTS_PASS: 1000 exact terminal attacks + 5000 reads use 1 inventory/0 projection/0 profile copies; sparse zero, live effects/hammers, profile order, players, fallback, thresholds and 1000 damage hits preserved")
