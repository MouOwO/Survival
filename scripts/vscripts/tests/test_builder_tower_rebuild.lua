package.path = "scripts/vscripts/?.lua;" .. package.path

local bus = require("core/event_bus")
local events = require("core/events")
local scheduler = require("core/scheduler")
local progression = require("systems/builder_progression_system")
local clock = 0
GameRules = { GetGameTime = function() return clock end }

local function builder(entindex)
    local result = { abilities = {} }
    function result:IsNull() return false end
    function result:entindex() return entindex end
    function result:HasModifier() return true end
    function result:GetAbilityCount() return 24 end
    function result:GetAbilityByIndex(index) return self.abilities[index + 1] end
    function result:FindAbilityByName(name)
        for _, ability in pairs(self.abilities) do
            if ability.name == name then return ability end
        end
    end
    function result:AddAbility(name)
        local ability = { name = name, active = true, hidden = false, cooldown = 0 }
        function ability:IsNull() return self.removed == true end
        function ability:GetAbilityName() return self.name end
        function ability:SetLevel(value) self.level = value end
        function ability:SetHidden(value) self.hidden = value end
        function ability:SetActivated(value) self.active = value end
        function ability:GetCooldownTimeRemaining() return self.cooldown end
        function ability:EndCooldown() self.cooldown = 0 end
        function ability:StartCooldown(value) self.cooldown = value end
        for index = 1, self:GetAbilityCount() do
            if not self.abilities[index] then self.abilities[index] = ability break end
        end
        return ability
    end
    function result:RemoveAbility(name)
        for index, ability in pairs(self.abilities) do
            if ability.name == name then
                ability.removed = true
                self.abilities[index] = nil
                return
            end
        end
    end
    result:AddAbility("ability_build_wall")
    return result
end

local listed = {}
for player_id = 0, 1 do
    listed[player_id] = {
        { building_id = "wall", entindex = 10 + player_id, level = 1 },
        { building_id = "main_city", entindex = 20 + player_id, level = 1 },
    }
end
bus.reset()
bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
    return { buildings = listed[payload.player_id] }
end)
local talent_consumed = false
bus.handle_request(events.ROGUE_REWARD_CONSUMED_GET_REQUEST, function() return talent_consumed end)
local notifications = {}
bus.subscribe(events.BUILDER_UNLOCK_CHANGED, function(payload)
    notifications[payload.player_id] = (notifications[payload.player_id] or 0) + 1
end)
progression.init()
local builders = { [0] = builder(100), [1] = builder(101) }
for player_id = 0, 1 do
    bus.emit(events.BUILDER_READY, {
        player_id = player_id, team = 2, builder = builders[player_id],
    })
end

local function can_build(player_id)
    local ability = builders[player_id]:FindAbilityByName("ability_build_arrow_tower")
    if ability then
        assert(builders[player_id]:GetAbilityByIndex(0) == ability,
            "restored tower construction must retain the first native ability slot")
    end
    return ability ~= nil and ability.active and not ability.hidden
end
local function count(player_id, kind)
    return progression._state_snapshot_for_test(player_id).counts[kind] or 0
end
local function tower(index, player_id, class_id)
    return {
        building_id = "arrow_tower", entindex = index,
        player_id = player_id or 0, team = 2, tower_class = class_id,
    }
end

assert(can_build(0) and can_build(1), "builders must initially be able to construct towers")
for index = 1, 6 do bus.emit(events.BUILDING_CREATED, tower(200 + index)) end
local tower_entry = builders[0]:FindAbilityByName("ability_build_arrow_tower")
assert(count(0, "arrow_tower") == 6 and can_build(0), "six towers must leave construction ready")
bus.emit(events.BUILDING_CREATED, tower(207))
assert(count(0, "arrow_tower") == 7 and not can_build(0), "seven base towers must disable construction")
assert(builders[0]:FindAbilityByName("ability_build_arrow_tower") == tower_entry
    and builders[0]:GetAbilityByIndex(0) == tower_entry
    and not tower_entry.hidden and not tower_entry:IsNull(),
    "seven towers must keep the same disabled construction button visible in its native slot")
assert(can_build(1), "another player's tower allowance must remain independent")

local before = notifications[0]
bus.emit(events.BUILDING_CREATED, tower(201))
bus.emit(events.BUILDING_CHANGED, tower(201))
assert(count(0, "arrow_tower") == 7 and notifications[0] == before,
    "duplicate creation and ordinary tower updates must not change counts or rebuild builder slots")

-- The logical death notification arrives before the visible corpse is removed.
local dead = tower(201)
dead.unit = { IsNull = function() return false end, IsAlive = function() return false end }
bus.emit(events.BUILDING_DESTROYED, dead)
assert(count(0, "arrow_tower") == 6 and can_build(0),
    "death must restore the native build ability synchronously while the corpse still exists")
assert(builders[0]:FindAbilityByName("ability_build_arrow_tower") == tower_entry,
    "a tower death must reactivate the retained button without replacing its handle")
before = notifications[0]
bus.emit(events.BUILDING_DESTROYED, dead)
bus.emit(events.BUILDING_CHANGED, tower(201, 0, "class_1"))
assert(count(0, "arrow_tower") == 6 and count(0, "class_1") == 0 and notifications[0] == before,
    "late engine death and stale class updates must not release an extra slot or resurrect a dead tower")

bus.emit(events.BUILDING_CREATED, tower(301))
assert(count(0, "arrow_tower") == 7 and not can_build(0), "a replacement must consume the released slot")
bus.emit(events.BUILDING_CHANGED, tower(202, 0, "class_2"))
assert(count(0, "arrow_tower") == 6 and count(0, "class_2") == 1 and not can_build(0),
    "class promotion keeps the owner's seventh live tower slot occupied")
before = notifications[0]
bus.emit(events.BUILDING_CHANGED, tower(202, 0, "class_2"))
assert(notifications[0] == before, "unchanged class upgrades must not refresh builder slots")
bus.emit(events.BUILDING_DESTROYED, tower(202, 0, "class_2"))
bus.emit(events.BUILDING_DESTROYED, tower(202, 0, "class_2"))
assert(count(0, "arrow_tower") == 6 and count(0, "class_2") == 0,
    "promoted tower death must release only its class allowance exactly once")

-- A builder recreated while towers survive rebuilds entity identities from the authoritative list.
listed[0][#listed[0] + 1] = tower(401)
listed[0][#listed[0] + 1] = tower(402, 0, "class_3")
bus.emit(events.BUILDER_READY, { player_id = 0, team = 2, builder = builders[0] })
assert(count(0, "arrow_tower") == 1 and count(0, "class_3") == 1 and can_build(0))
bus.emit(events.BUILDING_DESTROYED, tower(401))
bus.emit(events.BUILDING_DESTROYED, tower(401))
assert(count(0, "arrow_tower") == 0 and count(0, "class_3") == 1,
    "recovered base towers must retain an identity for idempotent removal")

-- Entity indices can later be reused after the prior tower's death.
bus.emit(events.BUILDING_CREATED, tower(401))
assert(count(0, "arrow_tower") == 1 and can_build(0))

-- Fusion status notifications do not fabricate a living ultimate entity;
-- its actual committed occupancy arrives through BUILDING_COUNTS_CHANGED.
before = notifications[0]
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_completed", ultimate_count = 1,
})
assert(can_build(0) and notifications[0] == before,
    "fusion completion must not hide or rebuild the base tower entry")
for index = 1, 5 do bus.emit(events.BUILDING_CREATED, tower(500 + index)) end
assert(count(0, "arrow_tower") == 6 and count(0, "class_3") == 1 and not can_build(0))
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_destroyed", ultimate_count = 0,
})
assert(not can_build(0), "ultimate destruction must not bypass a full base tower allowance")
bus.emit(events.BUILDING_DESTROYED, tower(501))
assert(count(0, "arrow_tower") == 5 and can_build(0),
    "a base tower death after fusion must immediately reopen its slot")
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_completed", ultimate_count = 1,
})
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_destroyed", ultimate_count = 0,
})
assert(can_build(0), "base construction must remain governed by the current count after repeated fusion events")
bus.emit(events.BUILDING_CREATED, tower(601))
assert(count(0, "arrow_tower") == 6 and count(0, "class_3") == 1 and not can_build(0))
print("BUILDER_TOWER_REBUILD_PASS: retained seven-total capacity button, synchronous death re-enable, duplicate events, promotion retains slots, recovery and player isolation")

-- The chosen talent is a permanent icon, including after construction rebuilds.
talent_consumed = true
for player_id = 0, 1 do
    bus.emit(events.ROGUE_REWARD_CHANGED, {player_id = player_id})
    local talent = builders[player_id]:FindAbilityByName("ability_survival_rogue_reward")
    assert(talent and not talent.hidden and talent.active, "consuming the offer must retain the talent icon")
end
print("BUILDER_TALENT_RETENTION_PASS")

-- Accepted unique orders occupy their allowance before travel/construction,
-- while stage progression and prerequisites still depend on completion.
assert(events.BUILDING_COUNTS_REQUEST and events.BUILDING_COUNTS_CHANGED)
local rogue_effects = require("systems/rogue_effect_state_service")
bus.reset()
scheduler.clear()
rogue_effects.reset()
clock = 0
local completed = { [0] = {}, [1] = {} }
local occupied = { [0] = {}, [1] = {} }
local snapshot_reads = { [0] = 0, [1] = 0 }
local function copied_counts(player_id)
    local result = {}
    for id, value in pairs(occupied[player_id]) do result[id] = value end
    return result
end
bus.handle_request(events.BUILDING_LIST_REQUEST, function(payload)
    return { ok = true, buildings = completed[payload.player_id] }
end)
bus.handle_request(events.BUILDING_COUNTS_REQUEST, function(payload)
    snapshot_reads[payload.player_id] = snapshot_reads[payload.player_id] + 1
    return { ok = true, counts = copied_counts(payload.player_id) }
end)
progression.init()
local unique_builders = { [0] = builder(700), [1] = builder(701) }
local function ready(player_id)
    bus.emit(events.BUILDER_READY, {
        player_id = player_id, team = 2, builder = unique_builders[player_id],
    })
end
local function entry(player_id, name)
    return unique_builders[player_id]:FindAbilityByName(name)
end
local function next_frame()
    clock = clock + 0.05
    scheduler.think()
end
local function occupancy(player_id, building_id, value, reason)
    occupied[player_id][building_id] = value
    bus.emit(events.BUILDING_COUNTS_CHANGED, {
        player_id = player_id, team = 2, counts = copied_counts(player_id), reason = reason,
    })
end
local function assert_ready_entry(player_id, name, slot)
    local ability = entry(player_id, name)
    assert(ability and not ability:IsNull() and not ability.hidden and ability.active
        and ability.level == 1, "restored unique skill must be ready: " .. name)
    assert(unique_builders[player_id]:GetAbilityByIndex(slot) == ability,
        "unique skill must retain its original native slot: " .. name)
    return ability
end
local function assert_empty_slot(player_id, name, slot)
    assert(not entry(player_id, name), "reserved skill must actually be removed: " .. name)
    local placeholder = unique_builders[player_id]:GetAbilityByIndex(slot)
    assert(placeholder and placeholder.name == "ability_survival_builder_slot_"
        .. tostring(slot + 1) .. "_placeholder" and placeholder.hidden
        and not placeholder.active, "reserved slot must have a hidden inactive placeholder")
end
local function complete(player_id, building_id, index, level)
    local payload = { player_id = player_id, team = 2, building_id = building_id,
        entindex = index, level = level or 1 }
    completed[player_id][#completed[player_id] + 1] = payload
    occupied[player_id][building_id] = math.max(1, occupied[player_id][building_id] or 0)
    bus.emit(events.BUILDING_CREATED, payload)
end
ready(0)
ready(1)
local wall_cast = assert_ready_entry(0, "ability_build_wall", 0)
wall_cast:StartCooldown(8)
entry(0, "ability_survival_builder_blink"):StartCooldown(6)
local retained_talent = entry(0, "ability_survival_rogue_reward")
occupancy(0, "wall", 1, "accepted")
assert(entry(0, "ability_build_wall") == wall_cast and wall_cast.hidden
    and not wall_cast.active and not wall_cast:IsNull(),
    "accepted order must hide/inactivate immediately without invalidating the casting handle")
local reserved_state = progression._state_snapshot_for_test(0)
assert(reserved_state.stage_id == "wall_pending" and not reserved_state.wall_built_once
    and (reserved_state.counts.wall or 0) == 0 and reserved_state.occupied_counts.wall == 1,
    "accepted wall must reserve its limit without counting as a completed wall")
assert(not entry(0, "ability_build_main_city"), "travel must not unlock the next building")
assert_ready_entry(1, "ability_build_wall", 0)
next_frame()
assert_empty_slot(0, "ability_build_wall", 0)
assert(wall_cast:IsNull(), "deferred removal must invalidate the old native ability handle")
assert(entry(0, "ability_survival_builder_blink"):GetCooldownTimeRemaining() == 6,
    "unique reservation layout rebuild must retain the blink cooldown")
assert(entry(0, "ability_survival_rogue_reward") == retained_talent,
    "unique reservation must retain the independent talent ability")
occupancy(0, "wall", 1, "construction_started")
next_frame()
assert_empty_slot(0, "ability_build_wall", 0)
assert(progression._state_snapshot_for_test(0).stage_id == "wall_pending",
    "underconstruction must not advance the build chain")
occupancy(0, "wall", 0, "canceled")
next_frame()
local restored_wall = assert_ready_entry(0, "ability_build_wall", 0)
assert(restored_wall ~= wall_cast and restored_wall:GetCooldownTimeRemaining() == 0,
    "cancel must restore a fresh ready ability after the original cast handle was removed")
occupancy(0, "wall", 0, "duplicate_release")
next_frame()
assert(entry(0, "ability_build_wall") == restored_wall,
    "duplicate releases must not rebuild or duplicate an already restored skill")

-- A replacement builder must query current commitments, rather than relying
-- on BUILDING_LIST_REQUEST, which intentionally lists only completed units.
occupancy(0, "wall", 1, "accepted_again")
next_frame()
local reads_before = snapshot_reads[0]
unique_builders[0] = builder(702)
ready(0)
assert(snapshot_reads[0] > reads_before, "builder recreation must request occupied counts")
assert_empty_slot(0, "ability_build_wall", 0)
assert_ready_entry(1, "ability_build_wall", 0)
occupancy(0, "wall", 0, "construction_failed")
next_frame()
assert_ready_entry(0, "ability_build_wall", 0)
occupancy(0, "wall", 1, "accepted_final")
next_frame()
complete(0, "wall", 710)
assert(progression._state_snapshot_for_test(0).stage_id == "city_pending")
local city_cast = assert_ready_entry(0, "ability_build_main_city", 0)
occupancy(0, "main_city", 1, "accepted")
assert(city_cast.hidden and not city_cast.active and not city_cast:IsNull())
next_frame()
assert_empty_slot(0, "ability_build_main_city", 0)
assert(not entry(0, "ability_build_arrow_tower") and not entry(0, "ability_build_research_lab"),
    "accepted city must not unlock tower/research construction")
complete(0, "main_city", 711, 3)
assert(progression._state_snapshot_for_test(0).stage_id == "city_built")
local research_cast = assert_ready_entry(0, "ability_build_research_lab", 1)
occupancy(0, "building_research_lab", 1, "accepted")
assert(research_cast.hidden and not research_cast.active and not research_cast:IsNull())
next_frame()
assert_empty_slot(0, "ability_build_research_lab", 1)
assert(not entry(0, "ability_build_advanced_research_lab")
    and not entry(0, "ability_build_challenge"),
    "research reservation must not fulfill either research prerequisite")
bus.emit(events.BUILDING_CHANGED, {
    player_id = 0, building_id = "main_city", entindex = 711, level = 4,
})
assert_empty_slot(0, "ability_build_research_lab", 1)
assert(not entry(0, "ability_build_advanced_research_lab")
    and not entry(0, "ability_build_challenge"),
    "city promotion must not restore a reserved skill or unlock unfinished prerequisites")
occupancy(0, "hero_altar", 1, "accepted")
next_frame()
assert_empty_slot(0, "ability_build_hero_altar", 3)
rogue_effects.set_numeric(0, "builder_free_hero_altar", 1)
bus.emit(events.ROGUE_REWARD_CHANGED, { player_id = 0 })
assert_empty_slot(0, "ability_build_hero_altar", 3)
assert_empty_slot(0, "ability_build_research_lab", 1)
assert(entry(0, "ability_survival_rogue_reward").active,
    "rogue resync must preserve the talent while unique reservations stay hidden")
occupancy(0, "building_research_lab", 0, "resource_or_creation_failure")
next_frame()
assert_ready_entry(0, "ability_build_research_lab", 1)
occupancy(0, "building_research_lab", 1, "accepted_final")
next_frame()
complete(0, "building_research_lab", 712)
assert_ready_entry(0, "ability_build_advanced_research_lab", 1)
assert_ready_entry(0, "ability_build_challenge", 5)
for _, pending in ipairs({
    { "building_advanced_research_lab", "ability_build_advanced_research_lab", 1 },
    { "building_farm", "ability_build_farm", 2 },
    { "building_challenge", "ability_build_challenge", 5 },
}) do
    local casting = assert_ready_entry(0, pending[2], pending[3])
    occupancy(0, pending[1], 1, "accepted")
    assert(casting.hidden and not casting.active and not casting:IsNull())
    next_frame()
    assert_empty_slot(0, pending[2], pending[3])
end
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, { player_id = 0 })
assert_empty_slot(0, "ability_build_advanced_research_lab", 1)
assert_empty_slot(0, "ability_build_farm", 2)
assert_empty_slot(0, "ability_build_challenge", 5)
assert_empty_slot(0, "ability_build_hero_altar", 3)

-- Tower orders reserve the shared live cap too; unrelated multi-count gold
-- mine behavior remains tied to its completed count.
complete(1, "wall", 750)
complete(1, "main_city", 751)
local teammate_tower = assert_ready_entry(1, "ability_build_arrow_tower", 0)
occupancy(0, "arrow_tower", 6, "six_live_towers")
next_frame()
local pending_tower = assert_ready_entry(0, "ability_build_arrow_tower", 0)
pending_tower:StartCooldown(4)
occupancy(0, "arrow_tower", 7, "constructing_multi_count")
assert(entry(0, "ability_build_arrow_tower") == pending_tower
    and not pending_tower.hidden and not pending_tower.active and not pending_tower:IsNull(),
    "the seventh accepted tower order must disable the visible button immediately")
assert(unique_builders[0]:GetAbilityByIndex(0) == pending_tower,
    "the accepted tower order must retain its original native slot")
assert(entry(1, "ability_build_arrow_tower") == teammate_tower
    and teammate_tower.active and not teammate_tower.hidden,
    "another player's tower construction must remain ready when the first player's cap fills")
occupancy(0, "gold_mine", 5, "constructing_multi_count")
next_frame()
assert(entry(0, "ability_build_arrow_tower") == pending_tower
    and unique_builders[0]:GetAbilityByIndex(0) == pending_tower
    and not pending_tower.hidden and not pending_tower.active and not pending_tower:IsNull(),
    "the deferred count sync must retain the same visible disabled tower handle")
assert(pending_tower:GetCooldownTimeRemaining() == 4,
    "tower capacity updates must retain the construction cooldown")
occupancy(0, "arrow_tower", 6, "tower_order_canceled")
next_frame()
assert(assert_ready_entry(0, "ability_build_arrow_tower", 0) == pending_tower,
    "canceling the seventh tower order must reactivate the same native button")
assert(entry(1, "ability_build_arrow_tower") == teammate_tower
    and teammate_tower.active and not teammate_tower.hidden,
    "canceling one player's tower order must not rebuild another player's button")
assert_ready_entry(0, "ability_build_gold_mine", 4)
for index = 1, 5 do complete(0, "gold_mine", 720 + index) end
assert_empty_slot(0, "ability_build_gold_mine", 4)
bus.emit(events.BUILDING_DESTROYED, {
    player_id = 0, building_id = "gold_mine", entindex = 721,
})
assert_ready_entry(0, "ability_build_gold_mine", 4)
assert_ready_entry(1, "ability_build_arrow_tower", 0)
print("BUILDER_UNIQUE_RESERVATION_PASS: unique hide/deferred removal, tower visible capacity lock/rollback with retained handle, cooldown/talent retention, completion-only gates and player isolation")
