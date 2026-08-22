package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

DOTA_UNIT_CAP_NO_ATTACK = 0
DOTA_UNIT_CAP_RANGED_ATTACK = 1
DOTA_TEAM_GOODGUYS = 2

local handlers = {}
package.preload["core/event_bus"] = function()
    return {
        handle_request = function(name, handler) handlers[name] = handler end,
        subscribe = function() end,
        request = function() return { ok = true } end,
        emit = function() end,
    }
end
package.preload["systems/technology_stat_manager"] = function()
    return { get = function() return { final = { lumberjack = {} } } end }
end

local worker_system = require("systems/worker_system")
local run = worker_system._run_batch_training_for_test

local next_id = 0
local result = run(2, function()
    next_id = next_id + 1
    return { ok = true, entindex = next_id }
end, function() error("successful batch rolled back") end)
assert(result.ok and result.count == 2
    and result.entindices[1] == 1 and result.entindices[2] == 2,
    "successful two-worker batch was not committed")

local attempts = 0
local rolled_back = {}
result = run(2, function()
    attempts = attempts + 1
    if attempts == 2 then return { ok = false, error = "worker_create_failed" } end
    return { ok = true, entindex = 11 }
end, function(entindex)
    rolled_back[#rolled_back + 1] = entindex
end)
assert(not result.ok and result.error == "worker_create_failed",
    "failed batch was reported as successful")
assert(#rolled_back == 1 and rolled_back[1] == 11,
    "failed batch did not roll back the first worker")

local reverse = {}
result = run(3, function()
    attempts = attempts + 1
    if attempts == 5 then return nil end
    return { ok = true, entindex = attempts }
end, function(entindex)
    reverse[#reverse + 1] = entindex
end)
assert(not result.ok and reverse[1] == 4 and reverse[2] == 3,
    "batch rollback order was not reverse creation order")

print("ROGUE_WORKER_BATCH_TRANSACTION_LUA51_PASS")