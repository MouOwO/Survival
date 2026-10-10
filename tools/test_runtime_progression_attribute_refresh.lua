-- Real runtime service/builder/event bus; mock only engine handles/transport.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local errors, tables, writes, registry = {}, {}, {}, {}
local mode = { IsNull = function() return false end }
GameRules = { GetGameModeEntity = function() return mode end }
local original_print = print
print = function(text)
    if tostring(text):find("handler error", 1, true) then errors[#errors + 1] = text end
end
CustomNetTables = { SetTableValue = function(_, name, key, value)
    if name == "survival_ability_runtime" then
        tables[key] = value
        writes[#writes + 1] = key
    end
end }
PlayerResource = { GetTeam = function() return 2 end }
EntIndexToHScript = function(id) return registry[id] end
local ranks, rank_valid = { [0] = 3, [1] = 3, [2] = 3, [3] = 3 }, true
local other_calls, attributes = 0, { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
local authority_hook
local function setup_handlers()
    bus.handle_request(events.RESOURCE_GET_REQUEST, function() return { gold = 100000, wood = 100000 } end)
    bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST, function(p)
        local result = { ok = rank_valid, snapshot = { rebirth_level = ranks[p.player_id] } }
        if authority_hook then authority_hook(p, result) end
        return result
    end)
    bus.handle_request(events.HERO_SUMMON_SNAPSHOT_REQUEST, function(p)
        return { ok = true, snapshot = { player_id = p.player_id, hero_summoned = 1 } }
    end)
    -- A combat/progression listener must still receive every event while only
    -- the runtime listener skips redundant native/nettable work.
    bus.subscribe(events.HERO_PROGRESSION_CHANGED, function(p)
        other_calls = other_calls + 1
        if p.reason == "star_blessing_attributes_per_second" then
            attributes[p.player_id] = attributes[p.player_id] + (tonumber(p.amount) or 0)
        end
    end)
end
local function unit(id, owner, name)
    local a = { active = true, level = 1 }
    function a:IsNull() return false end
    function a:entindex() return id + 10000 end
    function a:GetAbilityName() return name end
    function a:GetLevel() return self.level end
    function a:SetLevel(value) self.level = value end
    function a:IsPassive() return false end
    function a:IsHidden() return false end
    function a:IsActivated() return self.active end
    function a:SetActivated(value) self.active = value end
    local u = { ability = a, owner = owner }
    function u:IsNull() return self.removed == true end
    function u:entindex() return id end
    function u:GetTeamNumber() return 2 end
    function u:GetPlayerOwnerID() return self.owner end
    function u:GetAbilityCount() return 1 end
    function u:GetAbilityByIndex() return a end
    function u:FindAbilityByName(wanted) return wanted == name and a or nil end
    function u:GetUnitName() return "mock_combat_hero" end
    registry[id] = u
    return u
end
local service = dofile(arg[1] or "scripts/vscripts/ui/ability_runtime_service.lua")
bus.reset(); setup_handlers(); service.init()
local entities = {}
local function publish(u, kind)
    bus.emit(events.BUILDING_CHANGED, { unit = u, player_id = u.owner,
        team = 2, building_id = kind or "combat_hero", level = 1, hero_summoned = 1 })
end
for owner = 0, 3 do
    entities[owner] = { unit(100 + owner * 10, owner, "ability_enter_shadow_realm"),
        unit(101 + owner * 10, owner, "ability_mock") }
    publish(entities[owner][1], "hero_altar"); publish(entities[owner][2])
end
local function emit(p)
    bus.emit(events.HERO_PROGRESSION_CHANGED, p)
    assert(#errors == 0, table.concat(errors, "\n"))
end
local function star(owner, tick)
    return { player_id = owner, reason = "star_blessing_attributes_per_second",
        amount = 2, attack_amount = 3, tick = tick or 1 }
end
local function expect_full(p)
    local before = #writes; emit(p); assert(#writes > before, "a changed/unknown state must retain full refresh")
end
local function expect_same(p)
    local before = #writes; emit(p); assert(#writes == before, "known unchanged attribute events must skip nettable/native runtime work")
end
for owner = 0, 3 do expect_full(star(owner)) end
local count = other_calls
for tick = 2, 101 do for owner = 0, 3 do expect_same(star(owner, tick)) end end
assert(other_calls == count + 400)
for owner = 0, 3 do assert(attributes[owner] == 202, "all real attribute listener updates remain") end
expect_same({ player_id = 0, reason = "archive_building_minute_growth" })
local growth = { player_id = 0, reason = "attack_all_attribute_growth", rebirth_level = 0,
    all_attributes = 99, display_all_attributes = 0, attack_flat = 0, attack_all_attribute_gain = 1,
    split_multishot_unlocked = false, multishot_count = 0, pending_skill_rewards = {}, version = 2 }
expect_same(growth)
assert(tables[tostring(entities[0][1].ability:entindex())].available == 0)
ranks[0] = 10
expect_full(growth) -- Its event rank is stale zero: only the authoritative GET may decide.
assert(tables[tostring(entities[0][1].ability:entindex())].available == 1, "real altar rank gate updates immediately")
expect_same(star(0))
local new_hero = unit(102, 0, "ability_mock")
publish(new_hero)
expect_full(star(0)); expect_same(star(0))
local replacement = unit(new_hero:entindex(), 0, "ability_mock")
publish(replacement)
expect_full(star(0)); expect_same(star(0))
replacement.owner = 1
publish(replacement)
expect_full(star(0)); expect_full(star(1))
expect_same(star(2)); expect_same(star(3))
bus.emit(events.BUILDING_DESTROYED, { entindex = replacement:entindex() })
expect_full(star(1)); expect_same(star(1))
local unknown = star(0); unknown.future_runtime_dependency = 1
expect_full(unknown); expect_full(star(0)); expect_same(star(0))
expect_full({ player_id = 0, reason = "reward_applied", rebirth_level = 10 })
expect_full(star(0)); expect_same(star(0))
local wrong_type = star(0); wrong_type.amount = "2"
expect_full(wrong_type)
local incomplete = star(0); incomplete.tick = nil
expect_full(incomplete)
rank_valid = false
expect_full(star(0)); expect_full(star(0))
rank_valid = true; ranks[0] = 0/0
expect_full(star(0)); expect_full(star(0))
ranks[0] = 10; expect_full(star(0)); expect_same(star(0))
mode = { IsNull = function() return false end }
expect_full(star(0)); expect_same(star(0))
local before_skill = #writes
entities[0][2].ability.level = 2
bus.emit(events.HERO_SKILL_CHANGED, { unit_entindex = entities[0][2]:entindex() })
assert(#writes > before_skill, "skill listener must still refresh its runtime independently")
assert(tables[tostring(entities[0][2].ability:entindex())].engine_level == 2)
-- A module/service reset must forget the old completed baseline even when the
-- new match happens to use the same rank, owner and exact entity mocks.
bus.reset(); setup_handlers(); service.init()
for owner = 0, 3 do publish(entities[owner][1], "hero_altar"); publish(entities[owner][2]) end
expect_full(star(0)); expect_same(star(0))
-- Workers register immediately, before the scheduled fusion publication. Their
-- immutable identities must invalidate both affected owners on every lifecycle.
GameRules.GetGameTime = function() return 0 end
local function worker_change(worker, owner)
    bus.emit(events.WORKER_CHANGED, { unit = worker, entindex = worker:entindex(),
        player_id = owner, team = 2, worker_type = "lumberjack" })
    assert(#errors == 0, table.concat(errors, "\n"))
end
local worker = unit(999, 0, "ability_mock")
worker_change(worker, 0)
expect_full(star(0)); expect_same(star(0))
worker = unit(999, 0, "ability_mock")
worker_change(worker, 0)
expect_full(star(0)); expect_same(star(0))
expect_full(star(1)); expect_same(star(1))
worker.owner = 1; worker_change(worker, 1)
expect_full(star(0)); expect_full(star(1))
expect_same(star(0)); expect_same(star(1))
bus.emit(events.WORKER_CHANGED, { entindex = 999, player_id = 1,
    team = 2, worker_type = "lumberjack", removed = true })
expect_full(star(1)); expect_same(star(1))

-- A native publication may synchronously change authority, even without a
-- nested progression event. Do not certify mixed rows using only the end rank.
local saved_set = CustomNetTables.SetTableValue
local altar_key = tostring(entities[0][1].ability:entindex())
local function rank_changes_during_publish(nested)
    local changed = false
    CustomNetTables.SetTableValue = function(self, name, key, value)
        if not changed and name == "survival_ability_runtime" and key == altar_key then
            changed = true; ranks[0] = 10
            if nested then emit({ player_id = 0, reason = "reward_applied", rebirth_level = 10 }) end
        end
        saved_set(self, name, key, value)
    end
    ranks[0] = 9; expect_full(star(0))
    CustomNetTables.SetTableValue = saved_set
    assert(changed and tables[altar_key].available == 0, "outer write preserves the existing publication order")
    expect_full(star(0))
    assert(tables[altar_key].available == 1, "uncertified outer rows must be repaired on the next attribute event")
    expect_same(star(0))
end
rank_changes_during_publish(false)
rank_changes_during_publish(true)

-- The authority GET in the fast path can itself synchronously register a unit
-- or replace the current mode. Revalidate identity/mode after it returns.
local armed = true
authority_hook = function(payload)
    if armed and payload.player_id == 0 then
        armed = false; worker_change(unit(997, 0, "ability_mock"), 0)
    end
end
expect_full(star(0)); assert(not armed)
authority_hook = nil; expect_same(star(0))
armed = true
authority_hook = function(payload)
    if armed and payload.player_id == 0 then
        armed = false; mode = { IsNull = function() return false end }
    end
end
expect_full(star(0)); assert(not armed)
authority_hook = nil; expect_same(star(0))

-- Unknown nested refreshes invalidate an outer token even when rank does not
-- change. The next event must rebuild before establishing a stable baseline.
local nested = false
CustomNetTables.SetTableValue = function(self, name, key, value)
    if not nested and name == "survival_ability_runtime" and key == altar_key then
        nested = true; emit({ player_id = 0, reason = "reward_applied", rebirth_level = 9 })
    end
    saved_set(self, name, key, value)
end
ranks[0] = 9; expect_full(star(0))
CustomNetTables.SetTableValue = saved_set
assert(nested); expect_full(star(0)); expect_same(star(0))

-- State changes during a full refresh must also leave it uncertified.
local changed = false
CustomNetTables.SetTableValue = function(self, name, key, value)
    if not changed and name == "survival_ability_runtime" and key == altar_key then
        changed = true; worker_change(unit(996, 0, "ability_mock"), 0)
    end
    saved_set(self, name, key, value)
end
ranks[0] = 10; expect_full(star(0))
CustomNetTables.SetTableValue = saved_set
assert(changed); expect_full(star(0)); expect_same(star(0))
assert(#errors == 0, table.concat(errors, "\n"))
original_print("PASS runtime progression: 4 owners/400 attribute ticks, authoritative rank gate, other listeners, exact replacement/ownership/removal, unknown payload, skill refresh and map/reset lifecycle; real worker add/replace/migrate/remove, mid-publish rank/identity changes, nested refresh and authority GET reentry")
