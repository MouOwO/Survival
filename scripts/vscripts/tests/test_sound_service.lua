package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local now = 0
local unit_events = {}
local position_events = {}
local stopped_events = {}
local precached = {}

GameRules = { GetGameTime = function() return now end }
EmitSoundOnLocationWithCaster = function(position, event, source)
    position_events[#position_events + 1] = {
        position = position, event = event, source = source,
    }
end
PrecacheResource = function(kind, resource, context)
    assert(kind == "soundfile" and context == "sound_test_context")
    precached[#precached + 1] = resource
end

local unit = {
    IsNull = function() return false end,
    entindex = function() return 77 end,
    EmitSound = function(_, event) unit_events[#unit_events + 1] = event end,
    StopSound = function(_, event) stopped_events[#stopped_events + 1] = event end,
}
local second_unit = {
    IsNull = function() return false end,
    entindex = function() return 78 end,
    EmitSound = function(_, event) unit_events[#unit_events + 1] = event end,
    StopSound = function(_, event) stopped_events[#stopped_events + 1] = event end,
}
local tree = {
    IsNull = function() return false end,
    entindex = function() return 701 end,
    EmitSound = function(_, event) unit_events[#unit_events + 1] = event end,
}
local second_tree = {
    IsNull = function() return false end,
    entindex = function() return 702 end,
    EmitSound = function(_, event) unit_events[#unit_events + 1] = event end,
}
local unavailable_same_key = {
    IsNull = function() return false end,
    entindex = function() return 77 end,
}

package.loaded["core/sound_service"] = nil
local building_sound_definitions = require(
    "config/generated/building_sound_definitions"
)
local sound_definitions = require("config/generated/hero_skill_sound_definitions")
local tower_sound_definitions = require(
    "config/generated/tower_skill_sound_definitions"
)
local worker_sound_definitions = require(
    "config/generated/worker_sound_definitions"
)
sound_definitions.by_id.test_attached_loop = {
    cue_id = "test_attached_loop",
    sound_event = "Test.AttachedLoop",
    playback_mode = "loop",
    attach_scope = "unit",
    enabled = true,
}
local sounds = require("core/sound_service")
sounds.init()

local expected_resources = {}
for _, source in ipairs({
    building_sound_definitions, sound_definitions, tower_sound_definitions,
    worker_sound_definitions,
}) do
    for _, row in ipairs(source.rows or {}) do
        local resources = row.sound_resources or { row.sound_resource }
        if row.enabled ~= false then
            for _, resource in ipairs(resources) do
                if resource and resource ~= "" then
                    expected_resources[resource] = true
                end
            end
        end
    end
end
local expected_precache_count = 0
for _ in pairs(expected_resources) do
    expected_precache_count = expected_precache_count + 1
end
assert(sounds.precache("sound_test_context") == expected_precache_count,
    "shared sound resources were not deduplicated during precache")
local unique = {}
for _, resource in ipairs(precached) do
    assert(not unique[resource], "duplicate sound resource was precached")
    unique[resource] = true
end

local position = { x = 10, y = 20, z = 30 }
assert(sounds.play("hero_flame_main_impact", {
    source = unit, position = position,
}) == true, "position cue did not play")
assert(#position_events == 1
        and position_events[1].event == "Ability.LightStrikeArray"
        and position_events[1].source == unit,
    "position cue used the wrong event or source")
assert(sounds.play("hero_flame_main_impact", {
    source = unit, position = position,
}) == false, "cue cooldown did not suppress an immediate replay")
assert(sounds.play("hero_flame_main_impact", {
    source = second_unit, position = position,
}) == true, "one caster's cooldown incorrectly suppressed another caster")

now = 1
assert(sounds.play("hero_blade_launch", { unit = unit, source = unit }) == true,
    "unit cue did not play")
assert(unit_events[#unit_events] == "Hero_Magnataur.ShockWave.Cast",
    "unit cue used the wrong event")

now = 2
assert(sounds.play("hero_arcane_impact", {
    source = unit, position = position,
}) == true)
now = 2.12
assert(sounds.play("hero_arcane_impact", {
    source = unit, position = position,
}) == true)
now = 2.24
assert(sounds.play("hero_arcane_impact", {
    source = unit, position = position,
}) == false, "arcane impact concurrency cap was not enforced")
now = 2.31
assert(sounds.play("hero_arcane_impact", {
    source = unit, position = position,
}) == true, "expired concurrency slot was not released")

now = 3
for index = 1, 4 do
    assert(sounds.play("hero_echo_slash_launch", {
        source = unit, position = position,
    }) == true, "echo slash window rejected an allowed cue")
    now = now + 0.08
end
assert(sounds.play("hero_echo_slash_launch", {
    source = unit, position = position,
}) == false, "time-window play limit was not enforced")

now = 4
sounds.reset()
assert(sounds.play("hero_echo_slash_launch", {
    source = unit, position = position,
}) == true)
now = 4.08
assert(sounds.play("hero_echo_slash_launch", {
    source = unavailable_same_key,
}) == false, "missing emitter unexpectedly played a cue")
for index = 1, 3 do
    now = now + 0.08
    assert(sounds.play("hero_echo_slash_launch", {
        source = unit, position = position,
    }) == true, "failed emission consumed a time-window slot")
end
now = now + 0.08
assert(sounds.play("hero_echo_slash_launch", {
    source = unit, position = position,
}) == false, "failed emission erased prior time-window history")

assert(not sounds.start_loop("hero_frost_launch", "oneshot_loop", unit),
    "oneshot cue was incorrectly accepted as a loop")
assert(not sounds.play("test_attached_loop", { unit = unit }),
    "loop cue was incorrectly accepted by one-shot playback")
assert(sounds.start_loop("test_attached_loop", "test_loop", unit),
    "attached loop lifecycle did not start")
assert(sounds._snapshot_for_test().active_loops == 1)
assert(sounds.stop_loop("test_loop"), "attached loop lifecycle did not stop")
assert(stopped_events[#stopped_events] == "Test.AttachedLoop")
assert(sounds._snapshot_for_test().active_loops == 0)

sounds.start_loop("test_attached_loop", "reset_loop", unit)
sounds.reset()
assert(sounds._snapshot_for_test().active_loops == 0,
    "reset left an active loop behind")
assert(sounds.play("hero_echo_slash_launch", {
    source = unit, position = position,
}) == true, "reset did not clear one-shot limiter state")
assert(sounds.play("unknown", { unit = unit }) == false,
    "unknown cue unexpectedly played")

now = 4.5
sounds.reset()
local tower_cue = assert(sounds.get("tower_magic_finger"),
    "tower sound definitions were not merged into the shared service")
assert(tower_cue.sound_event == "Hero_Lion.FingerOfDeath")
assert(sounds.play("tower_magic_finger", {
    source = unit, position = position,
}) == true, "tower position cue did not play through the shared service")
assert(position_events[#position_events].event == "Hero_Lion.FingerOfDeath")
assert(sounds.get("tower_machine_gun") == nil,
    "disabled machine-gun sound policy unexpectedly resolved as a cue")

now = 4.75
sounds.reset()
local before_layers = #unit_events
assert(sounds.play("building_construction_complete", {
    unit = unit, source = unit, limiter_scope = "team:2",
}) == true, "building completion cue did not play")
assert(#unit_events == before_layers + 1
        and unit_events[before_layers + 1] == "DOTA_Item.Buckler.Activate",
    "building completion cue was not reduced to its soft single layer")
assert(sounds.play("building_construction_complete", {
    unit = second_unit, source = second_unit, limiter_scope = "team:2",
}) == false, "team-level limiter did not suppress a second building")
assert(sounds.play("building_construction_complete", {
    unit = second_unit, source = second_unit, limiter_scope = "team:3",
}) == true, "one team's building limiter suppressed another team")

now = 4.9
sounds.reset()
assert(sounds.play("tower_basic_attack", {
    unit = unit, source = unit,
}) == true and unit_events[#unit_events] == "Creep_Good_Range.Attack",
    "tower attack did not play its native ranged launch event")
assert(sounds.play("tower_basic_attack", {
    unit = unit, source = unit,
}) == false, "tower entity cooldown did not suppress a dense attack sound")
assert(sounds.play("tower_basic_attack", {
    unit = second_unit, source = second_unit,
}) == true, "one tower's attack limiter suppressed another tower")

now = 4.95
sounds.reset()
assert(sounds.play("building_wall_damage", {
    unit = unit, source = unit,
}) == true and unit_events[#unit_events] == "Building_Generic.PartialDestruction",
    "wall damage did not play its native building hit event")
assert(sounds.play("building_wall_damage", {
    unit = unit, source = unit,
}) == false, "wall entity cooldown did not suppress dense damage sounds")
assert(sounds.play("building_wall_damage", {
    unit = second_unit, source = second_unit,
}) == true, "one wall's damage limiter suppressed another wall")

now = 5
sounds.reset()
local worker_cue = assert(sounds.get("worker_lumberjack_tree_impact"),
    "worker sound definitions were not merged into the shared service")
assert(worker_cue.sound_event == "Hero_Tiny_Tree.Impact")
assert(sounds.play("worker_lumberjack_tree_impact", {
    unit = tree, source = tree,
}) == true, "first lumberjack tree impact did not play")
assert(unit_events[#unit_events] == "Hero_Tiny_Tree.Impact",
    "lumberjack tree impact used the wrong native event")
now = 5.05
assert(sounds.play("worker_lumberjack_tree_impact", {
    unit = tree, source = tree,
}) == false, "tree-level cooldown did not suppress a dense impact")
now = 5.12
assert(sounds.play("worker_lumberjack_tree_impact", {
    unit = tree, source = tree,
}) == true, "second allowed tree impact was suppressed")
now = 5.24
assert(sounds.play("worker_lumberjack_tree_impact", {
    unit = tree, source = tree,
}) == false, "tree-level concurrency cap was not enforced")
assert(sounds.play("worker_lumberjack_tree_impact", {
    unit = second_tree, source = second_tree,
}) == true, "one tree's limiter incorrectly suppressed another tree")

print("SOUND_SERVICE_PASS")