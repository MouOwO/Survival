package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local calls = {}
package.loaded["core/sound_service"] = {
    play = function(cue_id, options)
        calls[#calls + 1] = { cue_id = cue_id, options = options }
        return true
    end,
}

package.loaded["systems/building_sound_service"] = nil
local building_sounds = require("systems/building_sound_service")
local unit = {
    IsNull = function() return false end,
}

assert(building_sounds.construction_started(unit, 2))
assert(calls[#calls].cue_id == "building_construction_start"
        and calls[#calls].options.limiter_scope == "team:2",
    "construction start did not use the team-scoped central cue")
assert(building_sounds.construction_completed(unit, 2))
assert(calls[#calls].cue_id == "building_construction_complete",
    "construction completion resolved the wrong cue")
assert(building_sounds.wall_damaged(unit))
assert(calls[#calls].cue_id == "building_wall_damage"
        and calls[#calls].options.limiter_scope == nil,
    "wall damage did not use the unit-scoped combat cue")

for _, building_id in ipairs({ "wall", "main_city", "hero_altar" }) do
    building_sounds.upgrade_completed({
        unit = unit, team = 2, building_id = building_id,
    })
    assert(calls[#calls].cue_id == "building_structure_upgrade_complete",
        building_id .. " did not resolve the heavy structure upgrade cue")
end
for _, building_id in ipairs({ "building_farm", "gold_mine" }) do
    building_sounds.upgrade_completed({
        unit = unit, team = 2, building_id = building_id,
    })
    assert(calls[#calls].cue_id == "building_standard_upgrade_complete",
        building_id .. " did not resolve the standard upgrade cue")
end

building_sounds.upgrade_completed({
    unit = unit, team = 2, building_id = "arrow_tower",
})
assert(calls[#calls].cue_id == "tower_base_upgrade_complete",
    "base arrow tower upgrade resolved the wrong cue")

local route_names = {
    class_1 = "death",
    class_2 = "mystery",
    class_3 = "lightning",
    class_4 = "machine_gun",
    class_5 = "multi",
    class_6 = "frost",
    class_7 = "magic",
}
for class_id, route_name in pairs(route_names) do
    building_sounds.upgrade_completed({
        unit = unit, team = 2, building_id = "arrow_tower",
        tower_class = class_id,
    })
    assert(calls[#calls].cue_id == "tower_" .. route_name .. "_upgrade_complete",
        class_id .. " ordinary upgrade resolved the wrong cue")
    building_sounds.upgrade_completed({
        unit = unit, team = 2, building_id = "arrow_tower",
        tower_class = class_id, stage_changed = true,
    })
    assert(calls[#calls].cue_id
            == "tower_" .. route_name .. "_major_upgrade_complete",
        class_id .. " stage transition resolved the wrong cue")
    building_sounds.upgrade_completed({
        unit = unit, team = 2, building_id = "arrow_tower",
        tower_class = class_id, class_changed = true,
    })
    assert(calls[#calls].cue_id
            == "tower_" .. route_name .. "_major_upgrade_complete",
        class_id .. " class transition resolved the wrong cue")
end

local function read(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local content = handle:read("*a")
    handle:close()
    return content
end

local building_source = read("scripts/vscripts/systems/building_system.lua")
local construction_start = assert(building_source:find(
    "building_sound.construction_started(unit, check.team)", 1, true
), "construction start sound is not wired")
local scheduler_start = assert(building_source:find(
    'end, "construct_building_"', 1, true
), "construction scheduler is missing")
assert(construction_start > scheduler_start,
    "construction start sound must follow successful task creation")
local completion_sound = assert(building_source:find(
    "building_sound.construction_completed(unit, state.team)", 1, true
), "construction completion sound is not wired")
local created_event = assert(building_source:find(
    "event_bus.emit(events.BUILDING_CREATED, data)", 1, true
), "authoritative building-created event is missing")
assert(completion_sound > created_event,
    "construction completion sound must follow authoritative registration")
assert(building_source:find(
    'state.building_id == "wall"', 1, true
), "recovered walls do not receive their damage-sound modifier")
assert(building_source:find(
    'check.definition.id == "wall"', 1, true
), "new walls do not receive their damage-sound modifier")

local tower_source = read(
    "scripts/vscripts/modifiers/modifier_tower_attack_effects.lua"
)
local attack_validation = assert(tower_source:find(
    "if not valid(primary)", 1, true
), "tower attacks no longer validate their target")
local attack_sound = assert(tower_source:find(
    'play_tower_sound("tower_basic_attack", caster, caster)', 1, true
), "tower basic attack sound is not wired")
assert(attack_sound > attack_validation,
    "tower attack sound must follow authoritative target validation")

local upgrade_source = read("scripts/vscripts/systems/building_upgrade_system.lua")
assert(upgrade_source:find("play_upgrade_sound(state)", 1, true),
    "normal building upgrade sounds are not wired")
assert(upgrade_source:find(
    "play_upgrade_sound(state, { stage_changed = stage_changed })", 1, true
), "tower stage transitions are not wired")
assert(upgrade_source:find(
    "play_upgrade_sound(state, { class_changed = true })", 1, true
), "tower class transitions are not wired")

local mine_source = read("scripts/vscripts/systems/gold_mine_system.lua")
local mine_sound = assert(mine_source:find(
    "building_sound.upgrade_completed({", 1, true
), "gold mine level sound is not wired")
local mine_apply = assert(mine_source:find(
    "apply_level_stats(state)", 1, true
), "gold mine authoritative level application is missing")
assert(mine_sound > mine_apply,
    "gold mine sound must follow authoritative level application")

print("BUILDING_SOUND_INTEGRATION_PASS")