package.path = "scripts/vscripts/?.lua;" .. package.path

package.loaded["core/logger"] = { info = function() end, warn = function() end }
package.loaded["core/scheduler"] = {
    after = function() error("startup must not wait for game time") end,
}
GameRules = { GetGameTime = function() return 0 end }
local wall_time = 0
Time = function() return wall_time end
CreateUnitByName = function() error("preloading must not create combat units") end
CreateUnitByNameAsync = CreateUnitByName
SpawnEntityFromTableSynchronous = CreateUnitByName

local catalog = require("config/asset_catalog")
local visual = require("config/monster_visual_config")
local archetypes = require("config/generated/monster_archetypes")
local encounters = require("config/generated/monster_encounters")
local members = require("config/generated/encounter_members")
local archive = require("config/generated/archive_challenge_definitions")
local wave_rows = require("config/generated/wave_definitions")
local difficulties = require("config/difficulty_config")
local builder = require("systems/wave_difficulty_builder")
local spawn_sequence = require("systems/wave_spawn_sequence")

local function new_session(options)
    wall_time = 0
    options = options or {}
    local requests, static = {}, {}
    local context = {}
    PrecacheResource = function(kind, path, actual_context)
        assert(actual_context == context, "static preload needs the real engine context")
        local key = kind .. ":" .. path
        static[key] = (static[key] or 0) + 1
        if options.fail_static == path then return false end
    end
    PrecacheUnitByNameAsync = function(name, callback, player)
        assert(player == -1)
        if options.fail_async then error("engine preload unavailable") end
        requests[#requests + 1] = { name = name, callback = callback }
    end
    package.loaded["systems/asset_preload_service"] = nil
    package.loaded["systems/startup_asset_preload_service"] = nil
    local preload = require("systems/asset_preload_service")
    local startup = require("systems/startup_asset_preload_service")
    preload.retire = function() error("startup must not retire resources") end
    if options.existing_precache then
        preload.precache_initial(context)
        preload.precache_group(context, "monster_default_wearables")
        preload.precache_group(context, "challenge_visuals")
    end
    local ok, ready, failed = startup.precache(context)
    preload.init()
    return startup, preload, requests, static, ok, ready, failed
end

local startup, preload, requests, static = new_session()
local before = startup.snapshot()
assert(before.total > 0 and before.ready > 0 and not before.complete)
local pending = startup.init()
assert(#requests > 0 and pending.ready < pending.total and pending.failed == 0,
    "requests=" .. #requests .. " total=" .. pending.total .. " ready=" .. pending.ready
        .. " failed=" .. pending.failed .. " error=" .. tostring(pending.error))
assert(not pending.complete, "queue acceptance is not engine completion")
assert(pending.progress == 100 * pending.ready / pending.total)
local count = #requests
startup.init()
assert(#requests == count, "repeat init must not duplicate requests")

-- Re-enter through a new observer while the shared preload service is loading.
-- queue_resources returns "ready" when it queues nothing new, including this
-- case where all resources are only loading. Never trust that return as done.
local original_queue = preload.queue_resources
preload.queue_resources = function(resources, options)
    local ok, status, queued, failed = original_queue(resources, options)
    assert(ok and status == "ready" and queued == 0 and failed == 0)
    return ok, status, queued, failed
end
package.loaded["systems/startup_asset_preload_service"] = nil
local second_observer = require("systems/startup_asset_preload_service")
assert(not second_observer.init().complete)
preload.queue_resources = original_queue
local snapshot = startup.snapshot()
assert(snapshot.ready == pending.ready and not snapshot.complete)
requests[1].callback()
assert(startup.snapshot().ready > pending.ready, "an actual callback advances progress")
for _, request in ipairs(requests) do request.callback() end
local complete = startup.snapshot()
assert(complete.complete and complete.ready == complete.total)
assert(complete.failed == 0 and complete.progress == 100 and complete.error == nil)
for _, times in pairs(static) do assert(times == 1, "static resources deduplicated") end

-- Ensure every async proxy dispatched by the real current configuration exists
-- in the shipped unit KV, rather than inventing generic proxy names.
local file = assert(io.open("scripts/npc/npc_units_custom.txt", "rb"))
local unit_kv = file:read("*a")
file:close()
for _, request in ipairs(requests) do
    assert(request.name:match("^npc_dota_hero_")
        or unit_kv:find('"' .. request.name .. '"', 1, true),
        "missing unit proxy: " .. request.name)
end

local function resource_ready(kind, path)
    if type(path) == "string" and path ~= "" then
        assert(preload.resource_status(kind, path) == "ready", "missing " .. kind .. ":" .. path)
    end
end
local function asset_ready(id)
    if type(id) ~= "string" or id == "" then return end
    for _, resource in ipairs(preload.resources_for_assets({ id })) do
        resource_ready(resource.resource_type, resource.path)
    end
end
local function definition_ready(definition, allow_wearables)
    resource_ready("model", definition.model_path)
    resource_ready("particle", definition.projectile_model)
    if definition.model_asset_id then asset_ready(definition.model_asset_id)
    elseif allow_wearables then asset_ready(definition.default_wearable_asset_id) end
end

-- All difficulties, normal members, mixed members, leaders and assault bosses.
for _, difficulty in ipairs(difficulties.rows) do
    if difficulty.enabled ~= false then
        local built = assert(builder.build(wave_rows.rows, difficulty.difficulty_id))
        for number = 1, math.min(10, built.total_waves) do
            for _, row in ipairs(built.waves[number]) do
                local definition = assert(archetypes.by_id[row.archetype_id])
                if spawn_sequence.is_normal(row)
                    and (row.movement_type_override or definition.movement_type) == "flying"
                    and definition.normal_flying_model_path then
                    resource_ready("model", definition.normal_flying_model_path)
                else resource_ready("model", definition.model_path) end
                resource_ready("particle", definition.projectile_model)
                if number >= 6 then asset_ready(definition.default_wearable_asset_id) end
            end
        end
    end
end
for number = 1, 10 do
    for _, resource in ipairs(visual.resources_for_wave(number)) do
        resource_ready(resource.resource_type, resource.path)
    end
end
-- Regression: absent support must not truncate subsequent mini-boss slots.
resource_ready("model", visual.asset("vis_kobold_foreman").model_path)
resource_ready("model", visual.asset("vis_alpha_wolf").model_path)
resource_ready("model", visual.asset("vis_centaur_conqueror").model_path)

local enabled_encounters = {}
for _, encounter in ipairs(encounters.rows) do
    if encounter.enabled ~= false then
        enabled_encounters[encounter.encounter_id] = true
        if encounter.archetype_id then definition_ready(archetypes.by_id[encounter.archetype_id], true) end
    end
end
for _, member in ipairs(members.rows) do
    if member.enabled ~= false and enabled_encounters[member.encounter_id] then
        definition_ready(archetypes.by_id[member.archetype_id], true)
    end
end
for _, definition in ipairs(archive.rows) do
    if definition.enabled ~= false then definition_ready(definition, true) end
end

-- A direct model whose callback has not fired never becomes ready, regardless
-- of stopped game time or repeated reads of the snapshot.
startup, preload, requests = new_session()
startup.init()
local hanging = startup.snapshot()
for _ = 1, 5 do
    local current = startup.snapshot()
    assert(not current.complete and current.ready == hanging.ready)
end

-- Engine errors are terminal failures, never interpreted as successfully ready.
startup, preload, requests = new_session({ fail_async = true })
local failed_async = startup.init()
assert(failed_async.failed > 0 and not failed_async.complete and failed_async.error)
assert(failed_async.progress == 100 * failed_async.ready / failed_async.total)
assert(failed_async.progress < 100, "failed work never increases successful load progress")

-- Explicit false is a failed synchronous resource load. That failure survives
-- asset_preload.init and remains closed even when all other callbacks finish.
local static_path = "particles/units/heroes/hero_morphling/morphling_base_attack.vpcf"
startup, preload, requests, static = new_session({ fail_static = static_path })
assert(static["particle:" .. static_path], "real challenge projectile is covered")
startup.init()
for _, request in ipairs(requests) do request.callback() end
local failed_static = startup.snapshot()
assert(failed_static.failed > 0 and not failed_static.complete and failed_static.error)
assert(preload.resource_status("particle", static_path) == "failed")
wall_time = 6
local reload = startup.retry()
assert(not reload.ok and reload.error == "startup_assets_require_map_reload")

-- A failed attachment prevents its whole async bundle from reporting ready,
-- including remaining model keys that the bundle has not visited yet.
local rebirth = assert(archetypes.by_id.rebirth_boss_01)
local costume = assert(catalog.resolve(rebirth.default_wearable_asset_id))
local attachment = assert(costume.components[1]).model_path
startup, preload, requests = new_session({ fail_static = attachment })
startup.init()
for _, request in ipairs(requests) do request.callback() end
local failed_bundle = startup.snapshot()
assert(failed_bundle.failed > 0 and not failed_bundle.complete and failed_bundle.error)

-- Match addon_game_mode's existing synchronous precache order. Already loaded
-- resources survive init and coexist with newly requested wave visual proxies.
startup, preload, requests = new_session({ existing_precache = true })
startup.init()
for _, request in ipairs(requests) do request.callback() end
assert(startup.snapshot().complete and startup.snapshot().total == complete.total)

-- Real-time deadline expires while GameTime remains zero. A UI retry starts
-- new engine requests, retains every completed resource, and is rate limited.
startup, preload, requests = new_session()
startup.init()
local old_count = #requests
requests[1].callback()
local preserved = startup.snapshot().ready
wall_time = 91
local timed_out = startup.snapshot()
assert(timed_out.failed > 0 and timed_out.error:find("startup_resource_timeout:", 1, true))
assert(not timed_out.complete and timed_out.ready == preserved)
assert(timed_out.progress == 100 * preserved / timed_out.total, "timeout is not progress")
local retried = startup.retry()
assert(retried.ok and #requests > old_count and startup.snapshot().ready == preserved)
local retried_count = #requests
assert(startup.retry().error == "startup_assets_retry_throttled")
assert(#requests == retried_count, "throttled retry sends no engine requests")
for index = 2, old_count do requests[index].callback() end
assert(startup.snapshot().ready == preserved, "stale callbacks cannot finish the replacement attempt")
for index = old_count + 1, #requests do requests[index].callback() end
assert(startup.snapshot().complete and startup.snapshot().failed == 0)
assert(startup.retry().complete and #requests == retried_count, "success is not reloaded")

-- Immediate engine failure can also recover after the API becomes available.
local transient = { fail_async = true }
startup, preload, requests = new_session(transient)
assert(startup.init().failed > 0)
assert(startup.retry().error == "startup_assets_retry_throttled")
transient.fail_async = false
wall_time = 6
assert(startup.retry().ok)
for _, request in ipairs(requests) do request.callback() end
assert(startup.snapshot().complete and not startup.snapshot().error)

startup, preload, requests = new_session()
startup.init()
wall_time = 6
assert(startup.retry().error == "startup_assets_still_loading")

-- Reuse the SAME modules across map lifetimes, as tools reloads can do. Old
-- completed/initial states, failure messages, cooldowns and late callbacks must
-- not replace actual work in the new engine Precache context.
startup, preload, requests = new_session({ existing_precache = true })
startup.init()
for _, request in ipairs(requests) do request.callback() end
assert(startup.snapshot().complete)
local function begin_next_map(fail_path)
    wall_time = 0
    local new_context, fresh_static = {}, {}
    PrecacheResource = function(kind, path, actual_context)
        assert(actual_context == new_context)
        fresh_static[kind .. ":" .. path] = true
        if path == fail_path then return false end
    end
    preload.precache_initial(new_context)
    preload.precache_group(new_context, "monster_default_wearables")
    preload.precache_group(new_context, "challenge_visuals")
    startup.precache(new_context)
    preload.init()
    assert(not startup.snapshot().complete, "new map is not already started")
    return fresh_static
end
local previous_count = #requests
local fresh_static = begin_next_map(static_path)
assert(fresh_static["particle:" .. static_path], "static work is not reused from old context")
assert(startup.init().failed > 0)
assert(#requests > previous_count, "new startup redispatches engine async requests")
local second_ready = startup.snapshot().ready
for index = 1, previous_count do requests[index].callback() end
assert(startup.snapshot().ready == second_ready, "old map callbacks cannot finish new work")
for index = previous_count + 1, #requests do requests[index].callback() end
assert(not startup.snapshot().complete)
wall_time = 6
assert(startup.retry().error == "startup_assets_require_map_reload")
previous_count = #requests
begin_next_map(nil)
assert(not startup.snapshot().error, "map reload clears prior failure and cooldown")
startup.init()
for index = previous_count + 1, #requests do requests[index].callback() end
assert(startup.snapshot().complete and startup.snapshot().progress == 100)

-- Disabled encounters and wave 11+ must not accidentally expand the startup
-- scope. A broken enabled source, however, must block instead of disappearing.
encounters.rows[#encounters.rows + 1] = {
    encounter_id = "disabled_startup_test", enabled = false, archetype_id = "missing_disabled",
}
members.rows[#members.rows + 1] = {
    encounter_id = "disabled_startup_test", enabled = true, archetype_id = "missing_disabled",
}
wave_rows.rows[#wave_rows.rows + 1] = {
    wave_id = "startup_later_wave_test", difficulty_id = "N1", wave_number = 11,
    spawn_order = 999, archetype_id = "missing_later_wave", enabled = true,
}
startup, preload, requests = new_session()
assert(startup.snapshot().total == complete.total and not startup.snapshot().error)
table.remove(wave_rows.rows)
table.remove(members.rows)
table.remove(encounters.rows)
encounters.rows[#encounters.rows + 1] = {
    encounter_id = "enabled_startup_test", enabled = true, archetype_id = "missing_enabled",
}
startup, preload, requests = new_session()
startup.init()
for _, request in ipairs(requests) do request.callback() end
local invalid = startup.snapshot()
assert(not invalid.complete and invalid.error == "startup_archetype_missing:missing_enabled")
table.remove(encounters.rows)

print("test_startup_asset_preload_service: PASS resources=" .. complete.total
    .. " async_requests=" .. count)
