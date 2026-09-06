package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local test_mode = arg and arg[1] or ""
local test_difficulty = test_mode == "pending" and "N3" or "N1"
local now = 0
local winner_calls = 0
GameRules = {
    GetGameTime = function() return now end,
    SetGameWinner = function(_, team)
        assert(team == 2, "victory used wrong team")
        winner_calls = winner_calls + 1
    end,
}
DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_UNIT_CAP_RANGED_ATTACK = 1
DOTA_UNIT_CAP_MELEE_ATTACK = 2
DOTA_UNIT_CAP_MOVE_FLY = 3
DOTA_UNIT_CAP_MOVE_GROUND = 4

local vector_mt = { __add = function(a, b)
    return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vector_mt)
end }
local function vector(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector_mt)
end
RandomVector = function() return vector(0, 0, 0) end
GetGroundHeight = function() return 0 end

local tasks = {}
local cancelled = {}
package.loaded["core/scheduler"] = {
    after = function(delay, callback, key)
        tasks[#tasks + 1] = { delay = delay, callback = callback, key = key }
    end,
    every = function(_, callback, key)
        tasks[#tasks + 1] = { delay = 1, callback = callback, key = key, every = true }
    end,
    cancel = function(key) cancelled[key] = true end,
}
package.loaded["core/team_alignment"] = { enforce = function() end }
package.loaded["systems/asset_preload_service"] = {
    queue_model = function() end,
    resources_for_models = function() return {} end,
    resources_for_assets = function() return {} end,
    queue_resources = function() return true, "ready", 0, 0 end,
}
package.loaded["config/armor_balance"] = { from_war3 = function(value) return value end }
package.loaded["config/generated/monster_spawn_points"] = { rows = {} }
package.loaded["config/difficulty_config"] = {
    default_id = test_difficulty,
    initial_wave_delay = 30,
    get = function(id)
        return (id == "N1" or id == "N2" or id == "N3")
            and { difficulty_id = id } or nil
    end,
    client_options = function() return {} end,
}

local old_row = { archetype_id = "old", monster_count = 2, wait_seconds = 30,
    spawn_interval = 1, health = 100, attack = 1, war3_armor = 0,
    attack_speed = 1, is_boss = false }
local final_row = { archetype_id = "final", monster_count = 2, wait_seconds = 30,
    spawn_interval = 1, health = 1000, attack = 10, war3_armor = 1,
    attack_speed = 1, is_boss = true }
package.loaded["config/generated/wave_definitions"] = { rows = {} }
package.loaded["systems/wave_difficulty_builder"] = {
    build = function(_, difficulty_id)
        if difficulty_id == "N1" then
            return { total_waves = 25, waves = { [1] = { old_row } } }
        end
        if difficulty_id == "N3" then
            return { total_waves = 30, waves = {
                [1] = { old_row }, [30] = { final_row },
            } }
        end
        return { total_waves = 30, waves = { [30] = { final_row } } }
    end,
}
package.loaded["config/generated/monster_archetypes"] = { by_id = {
    old = { unit_name = "old_enemy", move_speed = 250,
        attack_type = "melee", movement_type = "ground", passive_skill_ids = {} },
    final = { unit_name = "final_enemy", move_speed = 250,
        attack_type = "melee", movement_type = "ground", passive_skill_ids = {} },
} }
local marker = { GetAbsOrigin = function() return vector(0, 0, 0) end }
package.loaded["systems/monster_spawn_marker"] = { find = function() return marker end }

local next_entindex = 100
local created = {}
local function make_unit(name)
    next_entindex = next_entindex + 1
    local unit = { name = name, removed = false, alive = true, index = next_entindex }
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:SetBaseMaxHealth() end
    function unit:SetMaxHealth() end
    function unit:SetHealth() end
    function unit:SetBaseDamageMin() end
    function unit:SetBaseDamageMax() end
    function unit:SetPhysicalArmorBaseValue() end
    function unit:SetBaseMoveSpeed() end
    function unit:SetBaseAttackTime() end
    function unit:HasModifier() return false end
    function unit:AddNewModifier() end
    function unit:Script_SetAttackRange() end
    function unit:SetAttackCapability() end
    function unit:SetMoveCapability() end
    function unit:SetModelScale() end
    function unit:FindAbilityByName() return nil end
    function unit:AddAbility() end
    function unit:FindModifierByName() return nil end
    created[#created + 1] = unit
    return unit
end
CreateUnitByName = function(name) return make_unit(name) end
UTIL_Remove = function(unit) unit.removed = true; unit.alive = false end

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()
package.loaded["systems/wave_system"] = nil
local wave_system = require("systems/wave_system")
wave_system.init()
event_bus.emit(events.GAME_STARTED, {})

now = 59
local too_early = event_bus.request(events.WAVE_EARLY_FINAL_REQUEST, {})
assert(too_early and too_early.ok == false,
    "early final wave was available before 1 minute")

event_bus.emit(events.WAVE_START_NEXT, {})
local old_spawn_task = tasks[#tasks - 2]
local stale_old_spawn_task = tasks[#tasks - 1]
old_spawn_task.callback()
assert(#created == 1 and created[1].name == "old_enemy",
    "normal wave enemy was not spawned for cleanup test")
local unrelated = make_unit("challenge_enemy")

now = 60
local started = event_bus.request(events.WAVE_EARLY_FINAL_REQUEST, {})
assert(started and started.ok == true and started.final_wave == 30,
    "1-minute early final request failed")
assert(created[1].removed == true, "normal wave enemy was not silently removed")
assert(unrelated.removed == false, "untracked challenge enemy was incorrectly removed")

local duplicate = event_bus.request(events.WAVE_EARLY_FINAL_REQUEST, {})
assert(duplicate and duplicate.ok == false,
    "early final service was not limited to one use")

local final_tasks = {}
for _, task in ipairs(tasks) do
    if not task.every and task ~= old_spawn_task then
        final_tasks[#final_tasks + 1] = task
    end
end
table.sort(final_tasks, function(a, b) return a.delay < b.delay end)
for _, task in ipairs(final_tasks) do task.callback() end
assert(stale_old_spawn_task ~= nil, "test did not capture old generation task")
local old_count = 0
for _, unit in ipairs(created) do
    if unit.name == "old_enemy" then old_count = old_count + 1 end
end
assert(old_count == 1, "stale normal-wave generation task was not invalidated")

local final_units = {}
for _, unit in ipairs(created) do
    if unit.name == "final_enemy" then final_units[#final_units + 1] = unit end
end
assert(#final_units == 2, "wave 30 was not generated completely")
assert(winner_calls == 0, "victory settled before wave 30 was cleared")

-- Legacy shared-channel test fixture: both active players receive the
-- server-authored boss/clear events, with clear emitted only after all kills.
require("systems/player_context_service").active_player_ids = function() return { 0, 1 } end
local archive_boss, archive_clear = {}, {}
local keep_archive = test_mode == "archive"
local pending_archive = test_mode == "pending"
local challenge_begin_calls = 0
if keep_archive then
    event_bus.handle_request("archive.challenge_begin", function(payload)
        assert(payload.difficulty_id == test_difficulty and #payload.player_ids == 2)
        challenge_begin_calls = challenge_begin_calls + 1
        return { ok = true, keep_running = true }
    end)
end
local boss_records = {}
event_bus.subscribe("archive.wave_boss_killed", function(payload)
    boss_records[payload.player_id]=(boss_records[payload.player_id] or 0)+1
end)
event_bus.subscribe("archive.final_boss_killed", function(payload)
    assert(payload.difficulty_id == test_difficulty)
    archive_boss[payload.player_id] = (archive_boss[payload.player_id] or 0) + 1
end)
event_bus.subscribe("archive.final_wave_cleared", function(payload)
    archive_clear[payload.player_id] = (archive_clear[payload.player_id] or 0) + 1
end)

for index, unit in ipairs(final_units) do
    unit.alive = false
    event_bus.emit(events.ENGINE_ENTITY_KILLED, { victim = unit })
    assert(winner_calls == (index == #final_units and not keep_archive
        and not pending_archive and 1 or 0),
        "victory settlement timing is incorrect")
    assert((archive_clear[0] or 0) == (index == #final_units and 1 or 0))
end
event_bus.emit(events.ENGINE_ENTITY_KILLED, { victim = final_units[2] })
assert(winner_calls == ((keep_archive or pending_archive) and 0 or 1),
    "victory settlement was not idempotent")
assert(challenge_begin_calls == (keep_archive and 1 or 0), "archive phase transition/dedup")
local settled_state = event_bus.request(events.WAVE_STATE_GET_REQUEST, {})
assert(settled_state.post_clear_frozen == true, "post-clear gameplay was not frozen")
if pending_archive then
    assert(settled_state.status == "archive_challenges_pending")
    local retry = nil
    for _, task in ipairs(tasks) do
        if task.key == "archive_challenge_begin_retry" then retry = task end
    end
    assert(retry and retry.every, "N3 archive challenge retry was not scheduled")
end
assert(archive_clear[0] == 1 and archive_clear[1] == 1, "archive clear recipients/dedup")
assert((archive_boss[0] or 0) == 0 and (archive_boss[1] or 0) == 0,
    "mainline bosses never grant shadow archive rewards")
assert(boss_records[0]==2 and boss_records[1]==2,"each of two shared-channel bosses records once per owner")

print("WAVE_EARLY_FINAL_PASS")
