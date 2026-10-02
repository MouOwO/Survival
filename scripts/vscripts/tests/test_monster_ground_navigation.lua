-- Run from the addon root with Lua 5.1+; all engine entities are isolated mocks.
package.path = "scripts/vscripts/?.lua;" .. package.path
DOTA_UNIT_CAP_MOVE_NONE, DOTA_UNIT_CAP_MOVE_GROUND, DOTA_UNIT_CAP_MOVE_FLY = 0, 1, 2
DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS, DOTA_TEAM_NEUTRALS = 2, 3, 4
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2

local navigation = require("systems/monster_navigation_policy")
local anti_air = require("systems/anti_air_rules")
local collision = require("systems/wave_monster_collision")
local hull = require("systems/monster_hull_scale")
local events = require("core/events")
local no_op = function() end
local created, emitted, next_index = {}, {}, 0
local marker = {
    IsNull = function() return false end,
    GetAbsOrigin = function() return { x = 64, y = 128, z = 32 } end,
    GetForwardVector = function() return { x = 0, y = 1, z = 0 } end,
    GetName = function() return "test_spawn" end,
}

local function unit_mock()
    next_index = next_index + 1
    local unit = {
        index = next_index, capability = DOTA_UNIT_CAP_MOVE_FLY,
        moves = 0, placements = 0, hull = 32, modifiers = {}, operation = 0,
    }
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:entindex() return self.index end
    function unit:GetAbsOrigin() return self.position or marker:GetAbsOrigin() end
    function unit:GetHullRadius() return self.hull end
    function unit:SetHullRadius(radius)
        self.operation = self.operation + 1
        self.last_hull_operation = self.operation
        self.hull = radius
    end
    function unit:SetMoveCapability(capability)
        self.moves = self.moves + 1
        assert(capability == DOTA_UNIT_CAP_MOVE_GROUND, "spawn restored flying navigation")
        self.capability = capability
    end
    function unit:SetModel(path)
        self.operation = self.operation + 1
        self.last_visual_operation = self.operation
        self.model = path
    end
    function unit:SetOriginalModel(path)
        self.operation = self.operation + 1
        self.last_visual_operation = self.operation
        self.original_model = path
    end
    function unit:SetModelScale(scale)
        self.operation = self.operation + 1
        self.last_visual_operation = self.operation
        self.scale = scale
    end
    function unit:HasModifier(name) return self.modifiers[name] ~= nil end
    function unit:AddNewModifier(_, _, name, params) self.modifiers[name] = params end
    function unit:FindAbilityByName() return nil end
    for _, method in ipairs({ "SetBaseMaxHealth", "SetMaxHealth", "SetHealth",
        "SetBaseDamageMin", "SetBaseDamageMax", "SetPhysicalArmorBaseValue",
        "SetBaseMoveSpeed", "SetBaseAttackTime", "Script_SetAttackRange",
        "SetAttackCapability", "SetAcquisitionRange", "SetForwardVector",
        "AddAbility" }) do unit[method] = no_op end
    return unit
end

local env = setmetatable({
    Entities = { FindByName = function() return marker end },
    GridNav = { IsBlocked = function() return false end,
        IsTraversable = function() return true end },
    PlayerResource = { IsValidPlayerID = function() return true end,
        GetSelectedHeroEntity = function() return nil end },
    GetGroundHeight = function() return 0 end,
    CreateUnitByName = function(unit_name, position, clear_space)
        assert(clear_space == false, "implicit placement could use a flying base unit")
        local unit = unit_mock()
        unit.unit_name = unit_name
        unit.position = position
        created[#created + 1] = unit
        return unit
    end,
    FindClearSpaceForUnit = function(unit, position)
        assert(unit.capability == DOTA_UNIT_CAP_MOVE_GROUND,
            "first placement must already use ground navigation")
        assert(unit.survival_navigation_type == "ground")
        if unit.survival_is_wave_monster or unit.survival_is_challenge_monster then
            assert(unit.modifiers.modifier_enemy_wall_ai.no_unit_collision
                == (unit.survival_is_challenge_monster and 1 or 0),
                "formal waves must collide; challenge monsters keep their policy")
            assert(unit.hull == unit.survival_monster_hull_radius,
                "the final hull must be applied before placement")
        end
        unit.placements = unit.placements + 1
        unit.placement_hull = unit.hull
        unit.position = position
    end,
}, { __index = _G })

local definitions, encounters, spawn_points = { by_id = {} }, { by_id = {} }, { by_id = {} }
local deps = {
    ["systems/player_context_service"] = { is_defeated = function() return false end },
    ["systems/monster_navigation_policy"] = navigation,
    ["systems/monster_hull_scale"] = hull,
    ["systems/wave_monster_collision"] = collision,
    ["systems/wave_spawn_sequence"] = require("systems/wave_spawn_sequence"),
    ["config/global_rules"] = require("config/global_rules"),
    ["config/generated/monster_archetypes"] = definitions,
    ["config/generated/monster_encounters"] = encounters,
    ["config/generated/monster_spawn_points"] = spawn_points,
    ["config/generated/archive_challenge_rules"] = { by_id = { default = {} } },
    ["config/challenge_runtime_rules"] = { apply = function(value) return value end },
    ["config/challenge_combat_profile_config"] = { resolve = function() return nil end },
    ["config/monster_visual_config"] = { resolve = function() return nil end },
    ["systems/monster_visual_service"] = { apply = no_op },
    ["config/difficulty_config"] = require("config/difficulty_config"),
    ["core/team_alignment"] = { enforce = no_op },
    ["systems/monster_corpse_lifecycle_service"] = { track = no_op },
    ["systems/monster_hero_visual_service"] = { apply = no_op },
    ["systems/challenge_monster_visual_service"] = { apply = no_op },
    ["systems/challenge_session_service"] = { handles = function() return false end },
    ["systems/player_room_locations"] = {
        resolve = function() return { home_target_name = "test_spawn" } end,
        marker_name = function(name) return name end,
    },
    ["core/events"] = events,
    ["core/event_bus"] = {
        emit = function(name, payload) emitted[#emitted + 1] = { name, payload } end,
        request = function(name)
            if name == events.WAVE_STATE_GET_REQUEST then
                return { ok = true, difficulty_id = "N1" }
            end
        end,
    },
}
env.require = function(name)
    return deps[name] or { rows = {}, by_id = {} }
end
local function load_service(name)
    local path = "scripts/vscripts/systems/" .. name .. ".lua"
    local chunk
    if setfenv then
        chunk = assert(loadfile(path))
        setfenv(chunk, env)
    else
        chunk = assert(loadfile(path, "t", env))
    end
    return chunk()
end

-- Exercise the actual private spawn functions without production test hooks or
-- scheduling a match. Dependencies and engine calls remain inside this sandbox.
local function find_function(module, wanted)
    local seen = {}
    local function visit(fn)
        if type(fn) ~= "function" or seen[fn] then return nil end
        seen[fn] = true
        for index = 1, math.huge do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if name == wanted then return value end
            if type(value) == "function" then
                local found = visit(value)
                if found then return found end
            end
        end
    end
    for _, fn in pairs(module) do
        local found = visit(fn)
        if found then return found end
    end
    error("spawn function not reachable: " .. wanted)
end
local function set_upvalue(fn, wanted, value)
    for index = 1, math.huge do
        local name = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, index, value); return end
    end
    error("missing fixture state: " .. wanted)
end
local function archetype(kind, scale)
    return { unit_name = "test_native_flying_unit", model_path = "boss.vmdl",
        normal_flying_model_path = "flying.vmdl", movement_type = kind,
        model_scale = scale or 1, health = 1000, attack = 10, attack_speed = 1,
        attack_type = "melee", enabled = true }
end
local function check(unit, definition, override, expected_model)
    assert(unit and unit.capability == DOTA_UNIT_CAP_MOVE_GROUND)
    assert(unit.moves == 1 and unit.placements == 1, "one ground placement per spawn")
    assert(unit.survival_movement_type == definition.movement_type)
    assert(unit.survival_movement_type_override == override)
    local flying = definition.movement_type == "flying" or override == "flying"
    assert(anti_air.is_flying(unit) == flying, "flying combat class changed")
    local tower = { IsNull = function() return false end, survival_tower_class = "class_7" }
    assert(anti_air.can_attack(tower, unit) == flying, "anti-air targeting changed")
    assert(unit.model == expected_model and unit.original_model == expected_model)
    assert(unit.scale == definition.model_scale, "visual size changed")
end

-- Every configured monster may retain its combat classification, independent
-- of a native unit's initial movement capability or visual scale.
for _, definition in ipairs(require("config/generated/monster_archetypes").rows) do
    local unit = unit_mock()
    unit.survival_movement_type = definition.movement_type
    local before = anti_air.is_flying(unit)
    navigation.apply(unit)
    assert(unit.capability == DOTA_UNIT_CAP_MOVE_GROUND and anti_air.is_flying(unit) == before)
end

local wave = load_service("wave_system")
local spawn_wave = find_function(wave, "spawn_one")
set_upvalue(spawn_wave, "monster_spawn_marker", marker)
set_upvalue(spawn_wave, "state", { pending = 4, spawned = 0, alive = 0 })
for _, case in ipairs({ { "ground", "normal" }, { "flying", "normal" },
    { "flying", "assault_boss" }, { "ground", "normal", "flying" } }) do
    local definition = archetype(case[1], case[2] == "assault_boss" and 4.5 or 1)
    definitions.by_id.test = definition
    spawn_wave({ archetype_id = "test", member_role = case[2], movement_type_override = case[3],
        health = 1000, attack = 10, attack_speed = 1 }, 0, 1, 1)
    local expected_model = case[2] == "normal" and (case[3] or case[1]) == "flying"
        and "flying.vmdl" or "boss.vmdl"
    check(created[#created], definition, case[3], expected_model)
    assert(created[#created].survival_wave_movement_type == (case[3] or case[1]))
    assert(created[#created].survival_wave_no_unit_collision == false)
    assert(created[#created].hull == require("config/global_rules").wave_ground_monster_hull_radius,
        "boss, ground and flying wave monsters share one collision radius")
end

-- Use every enabled production batch, including wave_leader and the actual
-- per-role neutral model replacements. Scale/model changes must never select a
-- larger native hull, restore flying navigation, or disable unit collisions.
local real_archetypes = require("config/generated/monster_archetypes")
local real_waves = require("config/generated/wave_definitions")
local real_visual_config = require("config/monster_visual_config")
local previous_definitions = definitions.by_id
definitions.by_id = real_archetypes.by_id
deps["config/monster_visual_config"].resolve = real_visual_config.resolve
local real_visual_service = load_service("monster_visual_service")
deps["systems/monster_visual_service"].apply = real_visual_service.apply
local configured_spawn_count, visual_swap_count, flying_spawn_count = 0, 0, 0
local role_counts = { normal = 0, wave_leader = 0, assault_boss = 0 }
for _, row in ipairs(real_waves.rows) do
    if row.enabled ~= false then
        local definition = assert(real_archetypes.by_id[row.archetype_id], row.wave_id)
        local expected_visual = real_visual_config.resolve(row.wave_number, row.member_role, 1)
        local previous_count = #created
        spawn_wave(row, 0, row.wave_number, 1)
        assert(#created == previous_count + 1, "production batch was not spawned: " .. row.wave_id)
        local unit = created[#created]
        assert(unit.unit_name == definition.unit_name
            and unit.survival_monster_role == row.member_role
            and unit.survival_is_boss == (row.member_role == "assault_boss"), row.wave_id)
        local movement = row.movement_type_override or definition.movement_type or "ground"
        local expected_model = definition.model_path
        if row.member_role == "normal" and movement == "flying"
            and definition.normal_flying_model_path and definition.normal_flying_model_path ~= "" then
            expected_model = definition.normal_flying_model_path
        end
        local expected_scale = (definition.model_scale or 1) * (row.model_scale_multiplier or 1)
        if expected_visual then
            expected_model, expected_scale = expected_visual.model_path, expected_visual.model_scale
            assert(unit.survival_monster_visual_asset_id == expected_visual.visual_asset_id,
                "production visual replacement was not applied: " .. row.wave_id)
            visual_swap_count = visual_swap_count + 1
        end
        assert(unit.model == expected_model and unit.original_model == expected_model, row.wave_id)
        assert(unit.scale == expected_scale, "production visual scale changed: " .. row.wave_id)
        assert(unit.hull == 32 and unit.survival_base_monster_hull_radius == 32
            and unit.survival_monster_hull_radius == 32 and unit.placement_hull == 32
            and unit.survival_monster_hull_multiplier == 1,
            "every formal wave role uses radius 32 before placement: " .. row.wave_id)
        assert(unit.last_hull_operation > unit.last_visual_operation,
            "final hull must be applied after the final model/scale: " .. row.wave_id)
        assert(unit.survival_wave_no_unit_collision == false
            and unit.modifiers.modifier_enemy_wall_ai.no_unit_collision == 0, row.wave_id)
        assert(unit.capability == DOTA_UNIT_CAP_MOVE_GROUND and unit.moves == 1
            and unit.placements == 1 and unit.survival_wave_movement_type == movement, row.wave_id)
        local combat_flying = definition.movement_type == "flying"
            or row.movement_type_override == "flying"
        assert(anti_air.is_flying(unit) == combat_flying,
            "existing anti-air classification changed: " .. row.wave_id)
        role_counts[row.member_role] = assert(role_counts[row.member_role], row.wave_id) + 1
        if movement == "flying" then flying_spawn_count = flying_spawn_count + 1 end
        configured_spawn_count = configured_spawn_count + 1
    end
end
assert(configured_spawn_count > 0 and visual_swap_count > 0 and flying_spawn_count > 0)
for role, count in pairs(role_counts) do assert(count > 0, "missing actual wave role: " .. role) end
definitions.by_id = previous_definitions
deps["config/monster_visual_config"].resolve = function() return nil end
deps["systems/monster_visual_service"].apply = no_op

set_upvalue(wave.spawn_challenge_monster, "wave_channels", { [0] = { marker = marker } })
for _, kind in ipairs({ "ground", "flying" }) do
    local definition = archetype(kind, 3)
    local unit = assert(wave.spawn_challenge_monster({ health = 200, attack = 2 }, definition, 0))
    check(unit, definition, nil, "boss.vmdl")
    assert(unit.hull == 0 and unit.survival_wave_no_unit_collision == true)
    assert(unit.modifiers.modifier_enemy_wall_ai.no_unit_collision == 1)
end

local session_service = load_service("challenge_session_service")
local spawn_member = find_function(session_service, "spawn_member")
for _, case in ipairs({ { "ground", "practice" }, { "flying", "practice" },
    { "ground", nil }, { "flying", nil }, { "ground", nil, "flying" } }) do
    local definition = archetype(case[1], case[2] and 1 or 4)
    definitions.by_id.test = definition
    local session = { player_id = 0, challenge = { challenge_id = "test_challenge" },
        encounter_id = "test_encounter", encounter = {}, monsters = {}, monster_count = 0 }
    local unit = assert(spawn_member(session, { archetype_id = "test", location_id = "test_room",
        member_id = "test_member", spawn_target_name = "test_spawn", collision_profile = case[2],
        movement_type_override = case[3] }))
    check(unit, definition, case[3], "boss.vmdl")
    if case[2] == "practice" then
        assert(unit.placement_hull == require("config/global_rules").practice_monster_hull_radius,
            "practice collision radius must still apply before placement")
    end
    local expected_hull = case[2] == "practice" and 12
        or ((case[3] or case[1]) == "flying" and 10 or 32)
    assert(unit.hull == expected_hull and unit.survival_monster_hull_radius == expected_hull,
        "challenge/practice collision policy changed")
    assert(session.monster_count == 1 and session.monsters[unit:entindex()] == unit)
end

local single_service = load_service("monster_spawn_service")
local spawn_single = find_function(single_service, "start_encounter")
spawn_points.by_id.test = { spawn_point_id = "test", hammer_target_name = "test_spawn" }
for index, kind in ipairs({ "ground", "flying" }) do
    local definition = archetype(kind, 5)
    definitions.by_id.test = definition
    local id = "encounter_rebirth_" .. index
    encounters.by_id[id] = { encounter_id = id, encounter_type = "rebirth_boss",
        spawn_point_id = "test", archetype_id = "test" }
    assert(spawn_single({ encounter_id = id, player_id = 0 }).ok)
    check(created[#created], definition, nil, "boss.vmdl")
    assert(created[#created].hull == (kind == "flying" and 10 or 32),
        "rebirth encounter collision policy changed")
end

assert(#created == 13 + configured_spawn_count, "all production spawn paths must be exercised")
print(string.format("MONSTER_GROUND_NAVIGATION_PASS: 13 policy scenarios + %d actual wave batches"
    .. " (normal=%d, wave_leader=%d, assault_boss=%d, flying=%d, visual_swaps=%d);"
    .. " shared radius32 after model swaps; challenge/practice policies preserved",
    configured_spawn_count, role_counts.normal, role_counts.wave_leader,
    role_counts.assault_boss, flying_spawn_count, visual_swap_count))
