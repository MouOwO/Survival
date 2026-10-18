package.path = "scripts/vscripts/?.lua;" .. package.path
local profiles = require("config/challenge_combat_profile_config")
local generated = require("config/generated/rich_monster_profiles")
local ordinary = require("config/generated/challenge_combat_profiles")
local members = require("config/generated/encounter_members").rows
local encounters = require("config/generated/monster_encounters").rows

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local before, ordinary_before = copy(generated), copy(ordinary)
local ids = {}
for _, member in ipairs(members) do ids[#ids + 1] = member.member_id end
for _, encounter in ipairs(encounters) do
    if encounter.encounter_type == "rebirth_boss" then ids[#ids + 1] = encounter.encounter_id end
end
assert(#ids == 30, "the existing four rooms and all wilderness members must be covered")
for _, difficulty in ipairs({"N2", "N3"}) do
    for _, id in ipairs(ids) do
        local legacy = assert(profiles.resolve(id, difficulty))
        local expected = assert(generated.difficulties[difficulty].encounters[id])
        local rich, reason = profiles.resolve(id, difficulty, "rich")
        assert(rich and not reason, tostring(reason))
        for _, field in ipairs({"health", "attack", "war3_armor"}) do
            assert(rich[field] == expected[field], "rich values must be final, with no extra multiplier")
        end
        assert(rich.health > 0 and rich.attack >= 0 and rich.war3_armor >= 0)
        rich.health = -1
        if rich.field_sources then rich.field_sources.test_mutation = true end
        assert(equal(generated, before), "returned rich metadata must not mutate its source")
        assert(profiles.resolve(id, difficulty, "rich").health == expected.health)
        for _, mode in ipairs({"standard", "pure", "fishing"}) do
            assert(profiles.resolve(id, difficulty, mode) == legacy, mode .. " profiles changed")
        end
    end
end
for _, difficulty in ipairs({"N1", "N4", "N5", "N6", "N10"}) do
    assert(profiles.resolve("practice_wood", difficulty, "rich")
        == profiles.resolve("practice_wood", difficulty), "other rich difficulties must retain their profiles")
end
local missing, reason = profiles.resolve("practice_wood", "N999", "rich")
assert(not missing and reason == "challenge_combat_profile_missing:practice_wood:N999")
missing, reason = profiles.resolve("unconfigured_monster", "N2", "rich")
assert(missing == nil and reason == nil, "unconfigured members retain ordinary archetype fallback")
assert(equal(ordinary, ordinary_before), "rich lookup must not change shared ordinary tables")

-- Reuse only engine doubles from an existing appearance integration fixture.
-- Production spawn closures and the real profile resolver run below.
local file = assert(io.open("tools/test_monster_appearance_spawn_paths.lua", "rb"))
local fixture = file:read("*a"); file:close()
local boundary = assert(fixture:find('deps["systems/wave_spawn_routing"]=load_service', 1, true))
local cases = [=[
local profiles = require("config/challenge_combat_profile_config")
local actual_members = require("config/generated/encounter_members").rows
local actual_encounters = require("config/generated/monster_encounters")
deps["config/challenge_combat_profile_config"] = profiles
deps["config/generated/monster_archetypes"] = require("config/generated/monster_archetypes")
deps["config/generated/monster_encounters"] = actual_encounters
deps["config/generated/monster_spawn_points"] = require("config/generated/monster_spawn_points")
deps["config/generated/encounter_members"] = require("config/generated/encounter_members")
deps["config/generated/challenge_definitions"] = require("config/generated/challenge_definitions")
deps["systems/destination_validation_service"] = {validate = function() return true end}
local projection = require("combat/endless_stat_projection")
deps["combat/endless_stat_projection"] = projection
local hero = {IsNull = function() return false end, IsAlive = function() return true end,
    entindex = function() return 99999 end, SetAbsOrigin = no_op, Stop = no_op}
local selected_mode, selected_difficulty = "rich", "N2"
local snapshots = 0
deps["core/event_bus"].request = function(name)
    if name == events.WAVE_STATE_GET_REQUEST then
        snapshots = snapshots + 1
        return {ok = true, difficulty_id = selected_difficulty, game_mode = selected_mode}
    end
    if name == events.HERO_SUMMON_GET_REQUEST then return {unit = hero} end
    if name == events.CONTENT_INVENTORY_GET_REQUEST then return {snapshot = {counts = {}}} end
end
env.RandomInt = function(low) return low end
env.DoUniqueString = function(value) return value .. ":fixture" end
env.FindUnitsInRadius = function() return {} end
env.DOTA_UNIT_TARGET_HERO, env.DOTA_UNIT_TARGET_BASIC = 1, 2
deps["systems/player_room_locations"].resolve = function()
    return {entry_target_name = "test_spawn", home_target_name = "test_spawn",
        spawn_target_names = {"test_spawn", "test_spawn_2"}}
end
local create = env.CreateUnitByName
env.CreateUnitByName = function(...)
    local value = create(...)
    value.applied = {}
    for method, key in pairs({SetBaseMaxHealth = "base_health", SetMaxHealth = "max_health",
        SetHealth = "health", SetBaseDamageMin = "attack_min", SetBaseDamageMax = "attack_max",
        SetPhysicalArmorBaseValue = "native_armor", SetBaseAttackTime = "bat"}) do
        local field = key
        value[method] = function(self, argument) self.applied[field] = argument end
    end
    function value:GetHealth() return self.applied.health end
    function value:GetMaxHealth() return self.applied.max_health end
    return value
end
local resolve_calls = {}
deps["config/challenge_combat_profile_config"] = {resolve = function(id, difficulty, mode)
    resolve_calls[#resolve_calls + 1] = {id = id, difficulty = difficulty, mode = mode}
    return profiles.resolve(id, difficulty, mode)
end}
local function check(value, id, difficulty, mode)
    local expected = assert(profiles.resolve(id, difficulty, mode))
    local health_scale = value.survival_endless_health_scale or 1
    local attack_scale = value.survival_endless_attack_scale or 1
    local function close(a, b) return math.abs(a - b) <= math.max(0.000001, math.abs(b) * 1e-14) end
    assert(close(value.applied.base_health * health_scale, expected.health)
        and close(value.applied.max_health * health_scale, expected.health)
        and close(value.applied.health * health_scale, expected.health), id .. " logical maximum/current health was lost")
    assert(close(value.applied.attack_min * attack_scale, expected.attack)
        and close(value.applied.attack_max * attack_scale, expected.attack),
        id .. " final attack was multiplied or lost")
    assert(close(tonumber(projection.for_ui(value, value:GetMaxHealth(), "health")), expected.health)
        and close(tonumber(projection.for_ui(value, value.applied.attack_min, "attack")), expected.attack),
        "shared UI projection must restore exact authored stats")
    if mode == "rich" and (expected.health > 100000000 or expected.attack > 100000000) then
        assert(value.applied.max_health <= 100000000.000001 and value.applied.attack_min <= 100000000.000001,
            "large rich values must use existing bounded native projection")
        assert(value.survival_endless_health == expected.health and value.survival_endless_attack == expected.attack)
    else
        assert(value.survival_endless_health_scale == nil and value.survival_endless_attack_scale == nil,
            "ordinary mode and small rich monsters must keep their existing native stats")
    end
    assert(value.applied.native_armor == 0 and value.survival_base_war3_armor == expected.war3_armor
        and value.survival_effective_war3_armor == expected.war3_armor,
        id .. " custom armor must be applied once")
    local called = resolve_calls[#resolve_calls]
    assert(called.id == id and called.difficulty == difficulty and called.mode == mode,
        "production resolver must receive the authoritative mode/difficulty pair")
end
local count, real_n3_rebirth10 = 0, nil
for _, difficulty in ipairs({"N2", "N3"}) do
    for _, mode in ipairs({"rich", "standard"}) do
        selected_difficulty, selected_mode = difficulty, mode
        local wilderness = load_service("monster_spawn_service")
        local start = find_function(wilderness, "start_encounter")
        for _, definition in ipairs(actual_encounters.rows) do
            if definition.encounter_type == "rebirth_boss" then
                local before = snapshots
                local result = start({encounter_id = definition.encounter_id, player_id = 0,
                    game_mode = "untrusted_client_mode", difficulty_id = "N999"})
                assert(result.ok, tostring(result.error))
                assert(snapshots == before + 1, "rebirth spawn must use one selection snapshot")
                check(created[#created], definition.encounter_id, difficulty, mode)
                if definition.encounter_id == "encounter_rebirth_10" and difficulty == "N3" and mode == "rich" then
                    local value = created[#created]
                    real_n3_rebirth10 = {logical = value.survival_endless_health,
                        native = value.applied.max_health, scale = value.survival_endless_health_scale}
                end
                count = count + 1
            end
        end
        local rooms = load_service("challenge_session_service")
        local spawn_member = find_function(rooms, "spawn_member")
        for _, member in ipairs(actual_members) do
            local staged = member.encounter_id == "encounter_challenge_11"
            local session = {player_id = 0, team = 2, difficulty_id = difficulty, game_mode = mode,
                challenge = {challenge_id = staged and "challenge_11" or "test_challenge"},
                encounter_id = member.encounter_id, encounter = {}, monsters = {}, monster_count = 0}
            -- A session's respawns keep its own snapshot even if global state
            -- changes. Staged ten-sin creation uses the same member function.
            selected_mode, selected_difficulty = "fishing", "N1"
            local value, reason = spawn_member(session, member)
            assert(value, tostring(reason))
            check(value, member.member_id, difficulty, mode)
            assert((value.survival_challenge_11_staged == true) == staged)
            count = count + 1
        end
        -- The public room entry path captures one selection for validation
        -- and every initial birth, ignoring client-supplied mode/difficulty.
        for index = 1, 10 do
            selected_mode, selected_difficulty = mode, difficulty
            local before, first = snapshots, #created + 1
            local encounter_id = string.format("encounter_challenge_%02d", index)
            local result = rooms.start({player_id = 0, team = 2, encounter_id = encounter_id,
                teleport_hero = false, game_mode = "untrusted_client_mode", difficulty_id = "N999"})
            assert(result.ok, tostring(result.error))
            assert(snapshots == before + 1, "room entry must read one authoritative selection snapshot")
            local member
            for _, candidate in ipairs(actual_members) do
                if candidate.encounter_id == encounter_id then member = candidate; break end
            end
            assert(#created >= first, "public room entry must create its configured monsters")
            for index = first, #created do check(created[index], member.member_id, difficulty, mode) end
            count = count + #created - first + 1
        end
        selected_mode, selected_difficulty = mode, difficulty
        local first, before = #created + 1, snapshots
        find_function(rooms, "prepare_after_hero_summoned")({player_id = 0, team = 2})
        assert(snapshots == before + 1 and #created - first + 1 == 10,
            "ten-sin staging must use one authoritative selection for all ten bosses")
        for index = first, #created do
            local id = string.format("boss_ten_sin_%02d", index - first + 1)
            local expected = assert(profiles.resolve(id, difficulty, mode))
            assert(math.abs(created[index].applied.health * (created[index].survival_endless_health_scale or 1)
                    - expected.health) < 0.001
                and math.abs(created[index].applied.attack_min * (created[index].survival_endless_attack_scale or 1)
                    - expected.attack) < 0.001
                and created[index].survival_war3_armor == expected.war3_armor,
                "ten-sin staging lost its selected rich/ordinary profile")
        end
        count = count + 10
    end
end
assert(count == 452, "all member, public room, rebirth and staged births must reach actual setters")
-- Force values above the native signed-integer limit through both real birth
-- paths. The existing shared projection owns damage/UI recovery and keeps
-- source data, kill bookkeeping and configured rewards unchanged.
local rich_source = require("config/generated/rich_monster_profiles").difficulties.N3.encounters
local original_rebirth, original_practice = rich_source.encounter_rebirth_10, rich_source.practice_greater_attribute
local huge = {health = 3000000001, attack = 1000000007, war3_armor = 1234,
    estimated = true, estimation_method = "large_native_boundary_fixture"}
rich_source.encounter_rebirth_10, rich_source.practice_greater_attribute = huge, huge
selected_mode, selected_difficulty = "rich", "N3"
local wilderness = load_service("monster_spawn_service")
local result = find_function(wilderness, "start_encounter")({encounter_id = "encounter_rebirth_10", player_id = 0})
assert(result.ok, tostring(result.error))
local rebirth_unit = created[#created]
check(rebirth_unit, "encounter_rebirth_10", "N3", "rich")
local reentry = find_function(wilderness, "reenter_encounter")({encounter_id = "encounter_rebirth_10", player_id = 0})
assert(reentry.ok and tonumber(reentry.boss_health) == huge.health,
    "rebirth reentry must return logical current health")
local rooms = load_service("challenge_session_service")
local member
for _, row in ipairs(actual_members) do if row.member_id == "practice_greater_attribute" then member = row end end
local session = {player_id = 0, team = 2, difficulty_id = "N3", game_mode = "rich",
    challenge = {challenge_id = "test_challenge"}, encounter_id = member.encounter_id,
    encounter = {}, monsters = {}, monster_count = 0}
local practice_unit = assert(find_function(rooms, "spawn_member")(session, member))
check(practice_unit, member.member_id, "N3", "rich")
for _, value in ipairs({rebirth_unit, practice_unit}) do
    local logical_hit = 1500000000.5
    assert(math.abs(projection.incoming(value, logical_hit) / value:GetMaxHealth() - 0.5) < 1e-12,
        "logical half-health damage must remove half native health")
    assert(math.abs(projection.outgoing(value, value.applied.attack_min, true) - huge.attack) < 0.001,
        "basic attack must recover logical damage once")
    assert(projection.outgoing(value, 123, false) == 123, "logical spell damage must not be scaled twice")
end
local killed, completed = {}, {}
deps["systems/monster_hero_visual_service"].on_death = no_op
deps["systems/challenge_monster_visual_service"].on_death = no_op
deps["core/event_bus"].emit = function(name, payload)
    if name == events.MONSTER_KILLED then killed[#killed + 1] = payload end
    if name == events.MONSTER_ENCOUNTER_COMPLETED then completed[#completed + 1] = payload end
end
local on_rebirth_killed = find_function(wilderness, "on_entity_killed")
on_rebirth_killed({victim = rebirth_unit, attacker = hero})
on_rebirth_killed({victim = rebirth_unit, attacker = hero})
assert(#killed == 1 and #completed == 1
    and completed[1].reward_profile_id == actual_encounters.by_id.encounter_rebirth_10.reward_profile_id,
    "projected rebirth death must retain its configured reward and settle once")
local clock, pending = 0, nil
env.GameRules = {GetGameTime = function() return clock end}
deps["core/scheduler"].after = function(delay, callback) assert(delay == 1); pending = callback end
session.status, session.spawn_mode, session.killed_members = "active", "maintain_count", 0
session.members, session.stage = {member}, 1
find_function(rooms, "set_session")(session)
local on_practice_killed = find_function(rooms, "on_killed")
on_practice_killed({victim = practice_unit, attacker = hero})
on_practice_killed({victim = practice_unit, attacker = hero})
assert(#killed == 2 and session.killed_members == 1 and session.monster_count == 0
    and killed[2].reward_profile_id == member.reward_profile_id and pending,
    "projected practice death must grant its existing kill reward once and retain its respawn job")
clock, selected_mode, selected_difficulty = 1, "fishing", "N1"
pending()
check(created[#created], member.member_id, "N3", "rich")
assert(session.monster_count == 1 and session.respawn_count == 0,
    "projected respawn must keep the original rich selection and consume its own death ticket")
rich_source.encounter_rebirth_10, rich_source.practice_greater_attribute = original_rebirth, original_practice
assert(real_n3_rebirth10 and real_n3_rebirth10.logical > 2147483647
    and real_n3_rebirth10.native <= 100000000.000001,
    "the real generated N3 final rebirth profile must safely cross the native integer health boundary")
print(string.format("RICH_N3_REBIRTH10_REAL_BOUNDARY_PASS logical_health=%.0f native_health=%.0f scale=%.17g",
    real_n3_rebirth10.logical, real_n3_rebirth10.native, real_n3_rebirth10.scale))
print("RICH_MONSTER_SPAWNING_PASS: 455 production births, public entries/staging, native large-stat boundaries, reward/kill idempotence and original-profile respawn")
]=]
assert(loadstring(fixture:sub(1, boundary - 1) .. cases, "test_rich_monster_spawn"))()
print("RICH_MONSTER_PROFILES_PASS: all 30 members across N2/N3, other modes/difficulties, immutable provenance")
