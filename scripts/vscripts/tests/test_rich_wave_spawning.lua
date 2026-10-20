-- Reuse only the engine fixture, then run the public production spawn pipeline.
-- This is an offline Lua 5.1 integration test; it never opens a native client,
-- installs an account overlay, makes HTTP requests, or bypasses a live gate.
local file = assert(io.open("scripts/vscripts/tests/test_wave_population_endgame.lua", "rb"))
local source = file:read("*a"); file:close()
local boundary = assert(source:find("-- The real rules admit", 1, true))
local cases = [=[
IsInToolsMode = function() return true end
package.loaded["systems/player_context_service"].max_players = function() return 4 end
package.loaded["config/asset_catalog"].for_model = function(path)
    return { asset_id = "fixture_model:" .. path }
end
local preload = package.loaded["systems/asset_preload_service"]
preload.STATE = {READY = "ready", FAILED = "failed", RETIRED = "retired"}
preload.queue = function() return true end
preload.status = function() return {status = preload.STATE.READY} end
package.loaded["systems/monster_visual_service"].queue_wave = noop

local rich_marker_reads, rich_route_reads = 0, 0
local original_find = Entities.FindByName
local function rich_position(id)
    return Vector(500 + (id % 2 - .5) * 192, -900 + (math.floor(id / 2) - .5) * 192, 96)
end
package.loaded["config/mode_spawn_config"] = {map_name="fixture",modes={rich={
    bounds={min_x=-10000,max_x=10000,min_y=-10000,max_y=10000},monster_markers={
        [0]="mode_rich_monster_0_spawn",[1]="mode_rich_monster_1_spawn",
        [2]="mode_rich_monster_2_spawn",[3]="mode_rich_monster_3_spawn"}}}}
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end}
local mode_spawns=require("systems/mode_spawn_service")
local resolve_wave=mode_spawns.wave_marker
mode_spawns.wave_marker=function(id)
    rich_route_reads = rich_route_reads + 1
    assert(type(id) == "number" and id >= 0 and id <= 3)
    return resolve_wave(id)
end
Entities.FindByName = function(self, previous, name)
    local id=tonumber(name:match("^mode_rich_monster_(%d+)_spawn$"))
    if id then
        rich_marker_reads = rich_marker_reads + 1
        if not markers_ready then return nil end
        return { IsNull = function() return false end,
            GetAbsOrigin = function() return rich_position(id) end }
    end
    return original_find(self, previous, name)
end

-- Record values written by production apply_stats, rather than merely reading
-- the builder's plan. The engine-double setters retain their actual inputs.
local original_create = CreateUnitByName
CreateUnitByName = function(name, position, ...)
    local value = original_create(name, position, ...)
    value.position=position
    function value:GetAbsOrigin() return self.position end
    value.applied = { position = {x = position.x, y = position.y, z = position.z} }
    function value:GetUnitName() return self.name end
    local setters = { SetBaseMaxHealth = "base_health", SetMaxHealth = "max_health",
        SetHealth = "health", SetBaseDamageMin = "damage_min", SetBaseDamageMax = "damage_max",
        SetPhysicalArmorBaseValue = "native_armor", SetModel = "model",
        SetOriginalModel = "original_model", SetModelScale = "model_scale" }
    for method, field in pairs(setters) do
        local key = field
        value[method] = function(self, argument) self.applied[key] = argument end
    end
    return value
end

local original_rows = require("config/generated/wave_definitions").rows
local archetypes = require("config/generated/monster_archetypes").by_id
local preserved = {"archetype_id", "member_role", "movement_type_override",
    "model_scale_multiplier", "attack_speed", "spawn_interval", "spawn_order",
    "is_boss", "boss_warning", "enabled"}
local original_n1 = {}
for _, row in ipairs(original_rows) do
    if row.difficulty_id == "N1" then original_n1[row.wave_id] = row end
end
local function expected_model(row)
    local definition = assert(archetypes[row.archetype_id])
    local movement = row.movement_type_override or definition.movement_type or "ground"
    if (row.member_role == nil or row.member_role == "normal") and movement == "flying"
        and type(definition.normal_flying_model_path) == "string"
        and definition.normal_flying_model_path ~= "" then
        return definition.normal_flying_model_path
    end
    return definition.model_path
end
local expected = {
    [1] = { normal = {7, 700, 6} },
    [10] = { normal = {5602, 49000, 105}, wave_leader = {5602, 49000, 105},
        assault_boss = {54777, 560035, 1644} },
    [20] = { normal = {77002, 770000, 390}, wave_leader = {77002, 770000, 390},
        assault_boss = {402502, 11025035, 2994} },
    [24] = { wave_leader = {560002, 21000000, 900},
        stitcher_large = {140002, 2100000, 450}, stitcher_small = {140002, 2100000, 450},
        humanoid_red_sword = {161002, 2100000, 465},
        flying_black_bone = {63002, 2450000, 435} },
    [25] = { normal = {182002, 3500000, 480}, wave_leader = {182002, 3500000, 480},
        assault_boss = {700002, 21000030, 2994} },
}
local function key(role, model, attack, health, armor, scale)
    return table.concat({role, model, attack, health, armor, scale}, "|")
end
local function finish_preload_and_spawns()
    clock = 100
    assert(scheduled.dev_wave_preload, "Production preload timer is required")()
    scheduled.dev_wave_preload = nil
    local callbacks = {}
    for id, callback in pairs(scheduled) do
        if type(id) == "number" then
            callbacks[#callbacks + 1] = callback
            scheduled[id] = nil
        end
    end
    for _, callback in ipairs(callbacks) do callback() end
end

local total_verified = 0
for _, number in ipairs({1, 10, 20, 24, 25}) do
    -- restart resets the real event bus/wave service and fixture engine state;
    -- no previous world's pending callbacks, population or units are reused.
    restart("N1", true, {0, 1, 2, 3}, "rich")
    rich_marker_reads, rich_route_reads = 0, 0
    local batches = assert(upvalue("waves")[number]).batches
    local planned_keys, seen_keys, per_owner, spawn_events = {}, {}, {}, 0
    local one_owner_plan, expected_roles = 0, {}
    for _, row in ipairs(batches) do
        local baseline = assert(original_n1[row.wave_id], "Original N1 model batch must survive")
        for _, field in ipairs(preserved) do
            assert(row[field] == baseline[field], "Rich spawn changed model/role contract: " .. field)
        end
        local role = row.member_role or "normal"
        local stats = assert((role ~= "normal" and expected[number][role])
            or expected[number][row.archetype_id] or expected[number][role],
            "Unreviewed attribute group in W" .. number .. ": " .. row.archetype_id)
        assert(row.attack == stats[1] and row.health == stats[2] and row.war3_armor == stats[3],
            "Builder did not route reviewed rich stats into production W" .. number .. "/" .. row.batch_id)
        if number == 10 or number == 20 then
            if role == "assault_boss" then
                assert(row.rich_stats_estimated == true and row.rich_stats_source == "boss_interpolation"
                    and row.rich_estimation_method == "linear_between_bosses",
                    "Interpolated boss must remain labeled as an estimate")
            end
        end
        local definition = assert(archetypes[row.archetype_id])
        local scale = (definition.model_scale or 1) * (row.model_scale_multiplier or 1)
        local bundle = key(role, expected_model(row), stats[1], stats[2], stats[3], scale)
        planned_keys[bundle] = (planned_keys[bundle] or 0) + row.monster_count * 4
        expected_roles[role] = (expected_roles[role] or 0) + row.monster_count
        one_owner_plan = one_owner_plan + row.monster_count
    end
    assert(one_owner_plan == 60, "Exactly 60 includes ordinary, leader and assault boss")
    local role_counts, spawn_errors = {}, {}
    local function observe_spawn(payload)
        local value, role = payload.unit, payload.member_role
        assert(payload.monster_source == "wave" and payload.wave_number == number,
            "Only formal production births are accepted")
        assert(value.survival_is_wave_monster and not value.survival_is_challenge_monster,
            "Birth must retain formal wave provenance")
        assert(payload.player_id >= 0 and payload.player_id <= 3
            and value.survival_player_id == payload.player_id, "Birth must retain immutable channel ownership")
        assert(value.survival_monster_role == role and value.survival_is_boss == (role == "assault_boss"))
        local actual = value.applied
        assert(actual.base_health == actual.max_health and actual.health == actual.max_health)
        assert(actual.damage_min == actual.damage_max)
        assert(actual.native_armor == 0, "War3 armor must not become native Dota armor")
        assert(value.survival_base_war3_armor == value.survival_war3_armor
            and value.survival_effective_war3_armor == value.survival_base_war3_armor)
        assert(actual.original_model == actual.model, "Original/current model contracts must agree")
        local position = rich_position(payload.player_id)
        assert(actual.position.x == position.x and actual.position.y == position.y,
            "A formal rich birth must use that owner's rich region route")
        local bundle = key(role, actual.model, actual.damage_min, actual.max_health,
            value.survival_base_war3_armor, actual.model_scale)
        assert(planned_keys[bundle], "Production setters produced an unplanned model/stat/role combination")
        seen_keys[bundle] = (seen_keys[bundle] or 0) + 1
        per_owner[payload.player_id] = (per_owner[payload.player_id] or 0) + 1
        role_counts[role] = (role_counts[role] or 0) + 1
        spawn_events = spawn_events + 1
    end
    local subscription = bus.subscribe(events.MONSTER_SPAWNED, function(payload)
        local ok, reason = pcall(observe_spawn, payload)
        if not ok then spawn_errors[#spawn_errors + 1] = reason end
    end)
    assert(wave.debug_spawn_wave_for_players(number, {0, 1, 2, 3}))
    finish_preload_and_spawns()
    bus.unsubscribe(subscription)
    assert(#spawn_errors == 0, "Production birth verification failed: " .. tostring(spawn_errors[1]))
    local state = upvalue("state")
    assert(state.planned == 240 and state.spawned == 240 and state.pending == 0
        and state.failed_spawn == 0 and #created == 240 and spawn_events == 240,
        "Four-player production scheduling must finish all 240 births without failure")
    assert(rich_marker_reads >= 4 and rich_route_reads >= 4, "Rich marker and region routing were bypassed")
    for id = 0, 3 do assert(per_owner[id] == 60, "Each owner receives precisely 60 births") end
    for bundle, count in pairs(planned_keys) do assert(seen_keys[bundle] == count, "Model/stat group population changed") end
    for role, count in pairs(expected_roles) do assert(role_counts[role] == count * 4, "Special member count changed") end
    local resources = wave._resource_snapshot_for_test()
    local session_count = 0
    for _, session in pairs(resources.sessions) do
        session_count = session_count + 1
        assert(session.planned == 240 and session.alive == 240 and session.pending == 0)
    end
    assert(session_count == 1, "Each isolated wave owns exactly one resource session")
    assert(#winners == 0 and #finalized == 0 and #granted == 0,
        "Spawn integration must not settle a match or grant account rewards")
    total_verified = total_verified + spawn_events
end
-- Engine clear-space must not place a successful wave birth on another
-- continent, even when its configured central marker was valid.
restart("N1",true,{0,1,2,3},"rich")
local ordinary_clear_space=FindClearSpaceForUnit
FindClearSpaceForUnit=function(value) value.position=Vector(0,30000,32) end
assert(wave.debug_spawn_wave_for_players(1,{0,1,2,3}))
finish_preload_and_spawns()
FindClearSpaceForUnit=ordinary_clear_space
local rejected_state=upvalue("state")
assert(rejected_state.failed_spawn==240 and rejected_state.spawned==0 and rejected_state.alive==0)
for _,value in ipairs(created) do
    assert(value.removed and value.survival_wave_cleanup,"out-of-mode native placement must be removed without registering an enemy")
end
print("RICH_WAVE_SPAWNING_PASS: 5 isolated production waves, " .. total_verified
    .. " births, 60 per owner, rich routes, estimated bosses, W24 groups, preserved models/roles and custom armor")
]=]
assert(loadstring(source:sub(1, boundary - 1) .. cases, "test_rich_wave_spawning"))()
