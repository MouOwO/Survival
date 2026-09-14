package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

local tasks = {}
package.loaded["core/scheduler"] = {
    cancel = function() end,
    every = function(_, callback, key) tasks[key] = callback end,
}
package.loaded["config/resources_config"] = {
    initial_wood = 100, initial_gold = 50,
    initial_population = 0, initial_max_population = 10,
}
package.loaded["systems/player_profile_service"] = {
    get_profile = function() return { save = { gameplay_stats = {} } } end,
}
PlayerResource = { GetTeam = function() return 2 end }

local bus = require("core/event_bus")
local events = require("core/events")
bus.reset()
local phase_guard = require("systems/gameplay_phase_guard")
phase_guard.reset()
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST, function()
    return { ok = true, totals = {
        initial_wood = 10, initial_gold = 5, initial_population_cap = 10,
        wood_per_second = 2, gold_per_second = 3,
    } }
end)

package.loaded["systems/resource_system"] = nil
local resources = require("systems/resource_system")
resources.init()
bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = 0 })
local before = bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 })
assert(before.wood == 10 and before.gold == 55)
assert(bus.request(events.RESOURCE_ADD_REQUEST,
    { player_id = 0, wood = 7, gold = 9 }).ok)
local locked = bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 })

phase_guard.set_post_clear_frozen(true)
for _, request in ipairs({
    { events.RESOURCE_ADD_REQUEST, { player_id = 0, wood = 100, gold = 100 } },
    { events.RESOURCE_TRY_SPEND_REQUEST, { player_id = 0, wood = 1, gold = 1 } },
    { events.RESOURCE_RELEASE_POP_REQUEST, { player_id = 0, population = 1 } },
    { events.RESOURCE_DEBUG_SET_REQUEST, { player_id = 0, amount = 999 } },
}) do
    local result = bus.request(request[1], request[2])
    assert(result.ok == false and result.error == "post_clear_frozen")
end
assert(tasks["resource_income:0"]() == true)
bus.emit(events.PERMANENT_REWARD_EFFECTS_CHANGED, {
    player_id = 0, totals = { initial_wood = 999 },
})
local after = bus.request(events.RESOURCE_GET_REQUEST, { player_id = 0 })
assert(after.wood == locked.wood and after.gold == locked.gold
    and after.population == locked.population and after.max_population == locked.max_population)

print("POST_CLEAR_FREEZE_PASS: resources, income and profile deltas remain fixed")
