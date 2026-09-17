package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local game_time = 0
local queued_asset_ids = {}
local exact_resource_asset_ids = {}
local retire_calls = 0
local scheduled = {}

GameRules = {
    GetGameTime = function() return game_time end,
}

package.loaded["core/scheduler"] = {
    cancel = function(task_id) scheduled[task_id] = nil end,
    every = function(_, callback, task_id)
        scheduled[task_id] = callback
        return task_id
    end,
    after = function(_, callback, task_id)
        local id = task_id or ("task_" .. tostring(#scheduled + 1))
        scheduled[id] = callback
        return id
    end,
    task_count = function() return 0 end,
}
package.loaded["core/team_alignment"] = { enforce = function() end }
package.loaded["systems/monster_spawn_marker"] = { find = function() return nil end }
package.loaded["systems/monster_corpse_lifecycle_service"] = {
    track = function() end,
}
package.loaded["systems/monster_hull_scale"] = {
    apply = function() return true end,
    apply_all = function(_, multiplier) return true, { multiplier = multiplier } end,
}
package.loaded["systems/wave_monster_collision"] = {
    profile = function(row, definition)
        return {
            movement_type = row.movement_type_override
                or definition.movement_type or "ground",
            base_hull_radius = 10,
            no_unit_collision = false,
        }
    end,
}
package.loaded["systems/monster_visual_service"] = {
    queue_wave = function() return true end,
    cleanup = function() end,
    active_state_count = function() return 0 end,
}
package.loaded["config/monster_visual_config"] = {
    resolve = function() return nil end,
    resources_for_wave = function() return {} end,
}
package.loaded["systems/asset_preload_service"] = {
    STATE = {
        READY = "ready",
        FAILED = "failed",
        RETIRED = "retired",
    },
    queue = function(asset_id)
        queued_asset_ids[#queued_asset_ids + 1] = asset_id
        return true, "loading"
    end,
    status = function() return { status = "ready" } end,
    retire = function()
        retire_calls = retire_calls + 1
        return true
    end,
    resources_for_models = function(model_paths)
        local result = {}
        for _, path in ipairs(model_paths or {}) do
            result[#result + 1] = { resource_type = "model", path = path }
        end
        return result
    end,
    resources_for_assets = function(asset_ids, extra_resources)
        exact_resource_asset_ids = {}
        for _, asset_id in ipairs(asset_ids or {}) do
            exact_resource_asset_ids[#exact_resource_asset_ids + 1] = asset_id
        end
        return extra_resources or {}
    end,
    queue_resources = function(resources)
        return true, #resources > 0 and "queued" or "ready", #resources, 0
    end,
}

package.loaded["systems/wave_system"] = nil
local wave_system = require("systems/wave_system")
wave_system.init()

local DRAGON_FORM_MODEL = "models/items/dragon_knight/fireborn_dragon/fireborn_dragon.vmdl"
local DRAGON_KNIGHT_MODEL = "models/heroes/dragon_knight/dragon_knight.vmdl"

local w8_default_ids = wave_system._wave_default_wearable_asset_ids_for_test(8, {
    batches = { { archetype_id = "skeleton_bone" } },
})
assert(#w8_default_ids == 1
        and w8_default_ids[1] == "monster_wave_skeleton_bone",
    "formal W8 did not collect its exact CSV default wearable asset")
assert(#wave_system._wave_default_wearable_asset_ids_for_test(3, {
        batches = { { archetype_id = "skeleton_melee" } },
    }) == 0,
    "W1-W5 neutral visual range queued a default wearable asset")
assert(wave_system._queue_wave_assets_for_test(8),
    "formal W8 resource queue was rejected")
assert(#exact_resource_asset_ids == 1
        and exact_resource_asset_ids[1] == "monster_wave_skeleton_melee",
    "formal wave queue did not use exact asset-ID resource expansion")

local variant_ids = wave_system._wave_default_wearable_asset_ids_for_test(20, {
    batches = { { archetype_id = "orc_brown_large" }, { archetype_id = "orc_brown_small" } },
})
assert(#variant_ids == 2 and variant_ids[1] ~= variant_ids[2],
    "same-body Magnus variants lost their separate wearable preload bundles")

assert(wave_system.debug_spawn_wave(12), "monster12 debug wave was rejected")
local queued = {}
for _, asset_id in ipairs(queued_asset_ids) do queued[asset_id] = true end
assert(queued.monster_wave_dragon_red_small == true,
    "monster12 did not preload the approved dragon-form model")

local synthetic_wave = {
    batches = {
        {
            archetype_id = "dragon_red_small",
            member_role = "normal",
            monster_count = 1,
        },
    },
}
local paths = wave_system._wave_model_paths_for_test(synthetic_wave)
assert(#paths == 1 and paths[1] == DRAGON_FORM_MODEL,
    "shared wave model collector disagreed with spawn resolution")
assert(paths[1] ~= DRAGON_KNIGHT_MODEL,
    "base model leaked into the resolved wave resource list")

local formal_a = wave_system._acquire_wave_model_resources_for_test(
    12, synthetic_wave, 101, false
)
local formal_b = wave_system._acquire_wave_model_resources_for_test(
    13, synthetic_wave, 102, false
)
assert(wave_system._release_wave_model_resources_for_test(
        formal_a, "pending_guard") == false,
    "wave resources released while planned monsters were still pending")
formal_a.pending = 0
formal_a.alive = 1
formal_a.generation_completed = true
assert(wave_system._release_wave_model_resources_for_test(
        formal_a, "alive_guard") == false,
    "wave resources released while a session monster was still alive")
formal_a.alive = 0
local overlap = wave_system._resource_snapshot_for_test()
assert(overlap.leases[DRAGON_FORM_MODEL].session_count == 2,
    "overlapping waves did not share two independent model leases")

assert(wave_system._release_wave_model_resources_for_test(
        formal_a, "test_first_wave_finished") == true,
    "first overlapping wave session did not release")
local shared = wave_system._resource_snapshot_for_test()
assert(shared.leases[DRAGON_FORM_MODEL].session_count == 1,
    "first wave release dropped the shared model lease too early")

formal_b.pending = 0
formal_b.alive = 0
formal_b.generation_completed = true
assert(wave_system._release_wave_model_resources_for_test(
        formal_b, "test_second_wave_finished") == true,
    "second overlapping wave session did not release")
local formal_released = wave_system._resource_snapshot_for_test()
assert(formal_released.leases[DRAGON_FORM_MODEL] == nil,
    "last formal model lease remained after every session finished")

local dev_session = wave_system._acquire_wave_model_resources_for_test(
    12, synthetic_wave, 103, true
)
dev_session.pending = 0
dev_session.alive = 0
dev_session.generation_completed = true
assert(wave_system._release_wave_model_resources_for_test(
        dev_session, "test_dev_finished") == true,
    "dev wave session did not release its Lua identity")
local dev_released = wave_system._resource_snapshot_for_test()
assert(dev_released.session_count == 0,
    "dev wave session identity remained after cleanup")
assert(dev_released.leases[DRAGON_FORM_MODEL]
        and dev_released.leases[DRAGON_FORM_MODEL].dev_resident == true,
    "dev wave unexpectedly released its resident model lease")
assert(retire_calls == 0,
    "wave model lifecycle called asset_preload.retire()")

print("WAVE_MODEL_RESOURCE_LIFECYCLE_PASS")
