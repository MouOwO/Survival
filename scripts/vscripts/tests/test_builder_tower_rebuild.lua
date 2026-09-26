package.path = "scripts/vscripts/?.lua;" .. package.path

local bus = require("core/event_bus")
local events = require("core/events")
local progression = require("systems/builder_progression_system")

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
        local ability = { name = name, active = true, hidden = false }
        function ability:GetAbilityName() return self.name end
        function ability:SetLevel(value) self.level = value end
        function ability:SetHidden(value) self.hidden = value end
        function ability:SetActivated(value) self.active = value end
        function ability:GetCooldownTimeRemaining() return 0 end
        for index = 1, self:GetAbilityCount() do
            if not self.abilities[index] then self.abilities[index] = ability break end
        end
        return ability
    end
    function result:RemoveAbility(name)
        for index, ability in pairs(self.abilities) do
            if ability.name == name then self.abilities[index] = nil return end
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
for index = 1, 7 do bus.emit(events.BUILDING_CREATED, tower(200 + index)) end
assert(count(0, "arrow_tower") == 7 and not can_build(0), "seven base towers must close the entry")
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
before = notifications[0]
bus.emit(events.BUILDING_DESTROYED, dead)
bus.emit(events.BUILDING_CHANGED, tower(201, 0, "class_1"))
assert(count(0, "arrow_tower") == 6 and count(0, "class_1") == 0 and notifications[0] == before,
    "late engine death and stale class updates must not release an extra slot or resurrect a dead tower")

bus.emit(events.BUILDING_CREATED, tower(301))
assert(count(0, "arrow_tower") == 7 and not can_build(0), "a replacement must consume the released slot")
bus.emit(events.BUILDING_CHANGED, tower(202, 0, "class_2"))
assert(count(0, "arrow_tower") == 6 and count(0, "class_2") == 1 and can_build(0),
    "class promotion must continue to release a base tower slot")
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

-- Fusion owns its own ultimate-tower limit. It must not permanently close the
-- base construction entry while the player's base count is below seven.
before = notifications[0]
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_completed", ultimate_count = 1,
})
assert(can_build(0) and notifications[0] == before,
    "fusion completion must not hide or rebuild the base tower entry")
for index = 1, 6 do bus.emit(events.BUILDING_CREATED, tower(500 + index)) end
assert(count(0, "arrow_tower") == 7 and not can_build(0))
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_destroyed", ultimate_count = 0,
})
assert(not can_build(0), "ultimate destruction must not bypass a full base tower allowance")
bus.emit(events.BUILDING_DESTROYED, tower(501))
assert(count(0, "arrow_tower") == 6 and can_build(0),
    "a base tower death after fusion must immediately reopen its slot")
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_completed", ultimate_count = 1,
})
bus.emit(events.TOWER_FUSION_STATE_CHANGED, {
    player_id = 0, reason = "fusion_destroyed", ultimate_count = 0,
})
assert(can_build(0), "base construction must remain governed by the current count after repeated fusion events")
bus.emit(events.BUILDING_CREATED, tower(601))
assert(count(0, "arrow_tower") == 7 and not can_build(0))
print("BUILDER_TOWER_REBUILD_PASS: seven-base cap, synchronous death re-enable, duplicate events, class counts, recovery, player isolation, fusion does not permanently disable construction")

-- The chosen talent is a permanent icon, including after construction rebuilds.
talent_consumed = true
for player_id = 0, 1 do
    bus.emit(events.ROGUE_REWARD_CHANGED, {player_id = player_id})
    local talent = builders[player_id]:FindAbilityByName("ability_survival_rogue_reward")
    assert(talent and not talent.hidden and talent.active, "consuming the offer must retain the talent icon")
end
print("BUILDER_TALENT_RETENTION_PASS")
