package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local tasks = {}
local applied = {}
local cleaned = {}
local visual_failure_mode = nil
local game_time = 0
local next_task_id = 0

package.loaded["core/scheduler"] = {
    cancel = function(task_id)
        for _, task in ipairs(tasks) do
            if task.task_id == task_id then task.cancelled = true end
        end
    end,
    every = function(interval, callback, task_id)
        next_task_id = next_task_id + 1
        local id = task_id or ("repeat_" .. tostring(next_task_id))
        tasks[#tasks + 1] = {
            run_at = game_time + interval,
            callback = callback,
            task_id = id,
            repeat_interval = interval,
        }
        return id
    end,
    after = function(delay, callback, task_id)
        next_task_id = next_task_id + 1
        local id = task_id or ("task_" .. tostring(next_task_id))
        tasks[#tasks + 1] = {
            run_at = game_time + delay,
            callback = callback,
            task_id = id,
        }
        return id
    end,
    task_count = function() return #tasks end,
}
package.loaded["core/team_alignment"] = { enforce = function() end }
package.loaded["systems/asset_preload_service"] = {
    STATE = { READY = "ready", FAILED = "failed", RETIRED = "retired" },
    queue = function() return true, "ready" end,
    status = function() return { status = "ready" } end,
    resources_for_models = function() return {} end,
    queue_resources = function() return true, "ready", 0, 0 end,
}
package.loaded["systems/monster_spawn_marker"] = {
    find = function()
        return { GetAbsOrigin = function() return Vector(0, 0, 0) end }
    end,
}
package.loaded["config/armor_balance"] = { from_war3 = function(value) return value / 3 end }
package.loaded["config/generated/monster_spawn_points"] = { rows = {} }
package.loaded["config/generated/wave_definitions"] = { rows = {} }
package.loaded["config/generated/monster_archetypes"] = { by_id = {
    test = {
        unit_name = "test_enemy",
        model_path = "models/test/original.vmdl",
        model_scale = 2,
        move_speed = 270,
        attack_range = 128,
        movement_type = "ground",
        attack_type = "melee",
        passive_skill_ids = {},
    },
} }
package.loaded["config/difficulty_config"] = {
    default_id = "N1",
    initial_wave_delay = 30,
    get = function(id) return id == "N1" and { difficulty_id = id } or nil end,
    client_options = function() return {} end,
}
local rows = {
    { archetype_id = "test", monster_count = 2, spawn_interval = 1,
        member_role = "normal", health = 101, attack = 11, war3_armor = 9,
        attack_speed = 1, is_boss = false },
    { archetype_id = "test", monster_count = 1, spawn_interval = 1,
        member_role = "wave_leader", health = 202, attack = 22, war3_armor = 12,
        attack_speed = 1, is_boss = false },
    { archetype_id = "test", monster_count = 1, spawn_interval = 1,
        member_role = "assault_boss", health = 303, attack = 33, war3_armor = 15,
        attack_speed = 1, is_boss = true },
}
package.loaded["systems/wave_difficulty_builder"] = {
    build = function()
        return { total_waves = 5, waves = { [5] = rows } }
    end,
}
package.loaded["config/wave_timing_config"] = {
    initial_delay_seconds = 30,
    formal_wave_preload_lead_seconds = 4,
    dev_wave_preload_timeout_seconds = 3,
    interval_after_wave = function() return 90 end,
}
package.loaded["config/monster_visual_config"] = {
    resources_for_wave = function() return {} end,
    resolve = function(wave_number, member_role, normal_index)
        assert(wave_number == 5)
        return {
            visual_asset_id = member_role,
            visual_role = member_role,
            model_path = "models/test/" .. member_role .. ".vmdl",
            model_scale = normal_index or 10,
        }
    end,
}
package.loaded["systems/monster_visual_service"] = {
    queue_wave = function() return true end,
    active_state_count = function() return 0 end,
    apply = function(unit, resolved)
        if visual_failure_mode == "return" then
            visual_failure_mode = nil
            return false, "simulated_visual_failure"
        end
        if visual_failure_mode == "throw" then
            visual_failure_mode = nil
            error("simulated_visual_exception")
        end
        applied[#applied + 1] = {
            unit = unit,
            role = resolved.visual_role,
            scale = resolved.model_scale,
        }
        unit:SetModel(resolved.model_path)
        unit:SetOriginalModel(resolved.model_path)
        unit:SetModelScale(resolved.model_scale)
        return true
    end,
    cleanup = function(unit) cleaned[unit] = true end,
}

DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_UNIT_CAP_RANGED_ATTACK = 1
DOTA_UNIT_CAP_MELEE_ATTACK = 2
DOTA_UNIT_CAP_MOVE_FLY = 3
DOTA_UNIT_CAP_MOVE_GROUND = 4
GameRules = { GetGameTime = function() return game_time end }

local vector_mt = { __add = function(a, b)
    return Vector(a.x + b.x, a.y + b.y, a.z + b.z)
end }
function Vector(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector_mt)
end
RandomVector = function() return Vector(0, 0, 0) end
GetGroundHeight = function() return 0 end

local units = {}
CreateUnitByName = function()
    local unit = { index = #units + 1, alive = true }
    function unit:IsNull() return false end
    function unit:IsAlive() return self.alive end
    function unit:entindex() return self.index end
    function unit:SetBaseMaxHealth(value) self.base_max_health = value end
    function unit:SetMaxHealth(value) self.max_health = value end
    function unit:SetHealth(value) self.health = value end
    function unit:SetBaseDamageMin(value) self.damage_min = value end
    function unit:SetBaseDamageMax(value) self.damage_max = value end
    function unit:SetPhysicalArmorBaseValue(value) self.armor = value end
    function unit:SetBaseMoveSpeed(value) self.move_speed = value end
    function unit:SetBaseAttackTime(value) self.bat = value end
    function unit:HasModifier() return false end
    function unit:AddNewModifier() end
    function unit:Script_SetAttackRange(value) self.attack_range = value end
    function unit:SetAttackCapability(value) self.attack_capability = value end
    function unit:SetMoveCapability(value) self.move_capability = value end
    function unit:SetModelScale(value) self.model_scale = value end
    function unit:SetModel(value) self.model = value end
    function unit:SetOriginalModel(value) self.original_model = value end
    function unit:FindAbilityByName() return nil end
    units[#units + 1] = unit
    return unit
end

local event_bus = require("core/event_bus")
local events = require("core/events")
event_bus.reset()
package.loaded["systems/wave_system"] = nil
local wave_system = require("systems/wave_system")
wave_system.init()
assert(wave_system.debug_spawn_wave(5))

local function run_next_task()
    local selected_index = nil
    local selected_task = nil
    for index, task in ipairs(tasks) do
        if not task.cancelled and (not selected_task
                or task.run_at < selected_task.run_at) then
            selected_index = index
            selected_task = task
        end
    end
    if not selected_task then return false end
    table.remove(tasks, selected_index)
    game_time = selected_task.run_at
    local result = selected_task.callback()
    if type(result) == "number" and result >= 0 then
        selected_task.run_at = game_time + result
        tasks[#tasks + 1] = selected_task
    elseif result == true and selected_task.repeat_interval then
        selected_task.run_at = game_time + selected_task.repeat_interval
        tasks[#tasks + 1] = selected_task
    end
    return true
end

local function run_until(predicate, limit)
    for _ = 1, limit or 1000 do
        if predicate() then return true end
        if not run_next_task() then break end
    end
    return predicate()
end

assert(run_until(function() return #units == 4 end),
    "debug preload and spawn tasks did not finish")

assert(#units == 4 and #applied == 4, "wave 5 visual was not applied per instance")
assert(applied[1].role == "normal" and applied[1].scale == 1)
assert(applied[2].role == "normal" and applied[2].scale == 2)
assert(applied[3].role == "wave_leader" and applied[3].scale == 10)
assert(applied[4].role == "assault_boss" and applied[4].scale == 10)
assert(units[1].health == 101 and units[1].damage_min == 11 and units[1].armor == 3)
assert(units[3].health == 202 and units[3].damage_min == 22 and units[3].armor == 4)
assert(units[4].health == 303 and units[4].damage_min == 33 and units[4].armor == 5)
assert(units[1].move_speed == 270 and units[1].attack_range == 128
    and units[1].attack_capability == DOTA_UNIT_CAP_MELEE_ATTACK
    and units[1].move_capability == DOTA_UNIT_CAP_MOVE_GROUND,
    "visual application changed combat or movement behavior")

local function spawn_first_of_new_debug_wave(failure_mode)
    visual_failure_mode = failure_mode
    local previous_unit_count = #units
    assert(wave_system.debug_spawn_wave(5))
    assert(run_until(function() return #units == previous_unit_count + 1 end),
        "debug wave did not spawn its first monster after preload")
    assert(#units == previous_unit_count + 1, "visual failure blocked monster spawn")
    local unit = units[#units]
    assert(unit.health == 101 and unit.damage_min == 11 and unit.armor == 3,
        "visual failure changed combat stats")
end

spawn_first_of_new_debug_wave("return")
spawn_first_of_new_debug_wave("throw")

units[4].alive = false
event_bus.emit(events.ENGINE_ENTITY_KILLED, { victim = units[4] })
assert(cleaned[units[4]] == true, "wave death did not clean visual state")

print("WAVE_MONSTER_VISUAL_INTEGRATION_PASS")