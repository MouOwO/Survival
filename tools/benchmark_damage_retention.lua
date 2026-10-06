-- Offline process only: lua tools/benchmark_damage_retention.lua
-- Uses the production repository, with successful pending-record consumption.
assert(not GameRules, "Run in a standalone Lua process, not in the game")
package.path = "scripts/vscripts/?.lua;" .. package.path
local time = 0
GameRules = { GetGameTime = function() return time end }
local repository = require("combat/damage_transaction_repository")
repository.init({ maximum_recursion_depth = 6 })
local attacker, victim = {}, {}
collectgarbage("collect")
local baseline = collectgarbage("count")
for i = 1, 60000 do
    time = i / 10
    local record = repository.create({ transaction_id = "retention_probe:" .. i,
        attacker = attacker, victim = victim, source_kind = "tower" })
    repository.mark_submitted(record)
    assert(repository.consume_pending(attacker, victim) == record)
    if i == 10000 or i == 30000 or i == 60000 then
        -- Collection is confined to this offline benchmark. Live capture never collects.
        collectgarbage("collect")
        print(string.format("DAMAGE_RETENTION processed=%d retained=%d heap_delta_kib=%.1f simulated_seconds=%.1f",
            i, repository.count(), collectgarbage("count") - baseline, time))
    end
end
