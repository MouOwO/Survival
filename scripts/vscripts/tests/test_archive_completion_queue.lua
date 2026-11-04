package.path = "scripts/vscripts/?.lua;" .. package.path
require("tests/development_release_profile")
package.path = "scripts/vscripts/?.lua;" .. package.path
local function copy(v)
    if type(v) ~= "table" then return v end
    local r = {}; for k, x in pairs(v) do r[k] = copy(x) end; return r
end
local stats = require("config/generated/player_gameplay_stats")
local achievements = require("config/generated/archive_achievements")
local shadow = require("config/generated/archive_shadow_items")
local function assert_formal_ids(name, definitions, key)
    local ids, count = {}, 0
    for id, row in pairs(definitions.by_id) do
        assert(row[key] == id, "formal index identity mismatch: " .. tostring(id))
        ids[id], count = true, count + 1
    end
    assert(count > 0 and #definitions.rows == count, name .. " matches the complete formal catalogue")
    for _, row in ipairs(definitions.rows) do
        assert(ids[row[key]], "unexpected generated definition: " .. tostring(row[key]))
        ids[row[key]] = nil
    end
    assert(next(ids) == nil, "each formal identity appears exactly once")
end
assert_formal_ids("archive_achievements", achievements, "achievement_id")
assert_formal_ids("archive_shadow_items", shadow, "item_id")
for _, list in ipairs({ achievements.rows, shadow.rows }) do
    for _, row in ipairs(list) do
        local fields, values = row.effect_ids or {}, row.effect_values or {}
        assert(#fields == #values)
        assert(row.reward_mode == "counter" and #fields == 0 or row.reward_mode ~= "counter" and #fields > 0,
            "counter-only milestones have no invented reward; every reward has configured effects")
        for i, field in ipairs(fields) do
            assert(stats.by_id[field], field)
            assert(tonumber(values[i]) > 0)
        end
    end
end
local profiles, writes, fail, persistable = {}, 0, false, true
local bus = require("core/event_bus")
local events = require("core/events")
local tasks, listeners, packets = {}, {}, {}
package.loaded["core/scheduler"] = {
    every = function(_, cb, key) tasks[key] = cb end,
    after = function(_, cb, key) tasks[key] = cb end,
    cancel = function(key) tasks[key] = nil end,
}
local function new_profile()
    local p = { revision = 1, save = { gameplay_stats = {}, content_inventory = {} }, entitlements = {} }
    for _, row in ipairs(stats.rows) do p.save.gameplay_stats[row.field_id] = row.default_value end
    return p
end
profiles[0], profiles[1] = new_profile(), new_profile()
local provider = { persist_save = function() end }
package.loaded["systems/player_profile_service"] = {
    get_profile = function(id) return copy(profiles[id]) end,
    get_provider = function() return persistable and provider or {} end,
    update_save_sections = function(id, replacements)
        if fail then return { ok = false, error = "disk_failed" } end
        for k, v in pairs(replacements) do profiles[id].save[k] = copy(v) end
        profiles[id].revision = profiles[id].revision + 1; writes = writes + 1
        bus.emit(events.PLAYER_PROFILE_CHANGED, { player_id = id })
        return { ok = true }
    end,
}
local tools_mode, time, rolls = true, 0, 0
GameRules = { GetGameTime = function() return time end, IsCheatMode = function() return false end }
IsInToolsMode = function() return tools_mode end
DoUniqueString = function() return "test_match" end
RandomInt = function(a, b) rolls = rolls + 1; return a end
-- This fixture tests grants/quotas using the first two pool entries. Shared
-- event randomness itself is covered with real seeds in the cooperative tests.
require("systems/archive_cooperative_reward_policy").local_seed = function() return 1 end
PlayerResource = { GetPlayer = function(_, id) return id end,
    IsValidPlayerID = function(_, id) return id == 0 or id == 1 end }
CustomGameEventManager = {
    RegisterListener = function(_, name, fn) listeners[name] = fn end,
    Send_ServerToPlayer = function(_, id, name, data) packets[#packets + 1] = { id = id, data = copy(data) } end,
}
local archive = require("systems/archive_service")
-- Real completion path: a claim queued behind an HTTP operation must start on
-- the next scheduler turn, without waiting for archive_retry's two seconds.
bus.reset();tasks={};archive.init();profiles[0],profiles[1]=new_profile(),new_profile()
local wake_requests={}
archive.set_provider({submit=function(id,command,done)
    wake_requests[#wake_requests+1]={player=id,command=command,done=done}
end})
local function run_ready(id)
    local key="archive_ready:"..id;local callback=tasks[key]
    assert(callback,"queued explicit intent needs an immediate completion wake")
    tasks[key]=nil;callback()
end
archive.daily_claim(0,100)
for day=101,228 do archive.daily_claim(0,day) end
archive.daily_claim(0,101) -- Same queued ID does not add a second ready node.
assert(#wake_requests==1,"busy account only sends its active operation")
bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0})
assert(#wake_requests==1,"synchronous profile event still sees busy operation")
local queue
for index=1,100 do
    local name,value=debug.getupvalue(archive._test.flush,index)
    if not name then break end
    if name=="pending" then queue=value[0];break end
end
assert(queue,"measure the actual production pending map")
local original_pairs,pending_scans=pairs,0
pairs=function(value)
    if value==queue then pending_scans=pending_scans+1 end
    return original_pairs(value)
end
wake_requests[1].done({ok=true})
for index=2,129 do
    run_ready(0)
    assert(#wake_requests==index and wake_requests[index].command.target_day==99+index,
        "FIFO ready head sends exactly one new claim per completed operation")
    local done=wake_requests[index].done
    done({ok=true});done({ok=true}) -- Late duplicate callback must be inert.
end
pairs=original_pairs
assert(pending_scans==0,"128 completion wakes must not rescan the pending map")
assert(not archive.has_pending(0) and not tasks["archive_ready:0"],"drained ready queue schedules no idle wake")
print("ARCHIVE_READY_COMPLETION_PASS: 128 queued claims, 128 wakes, zero pending scans, no retry tick, no duplicate submits")

-- A failed purchase stays an uncertain durable receipt. The completion wake
-- may send a different already-authorized claim, never replay the purchase.
archive.work_upgrade(0,"work_01",0)
local failed_purchase=wake_requests[#wake_requests]
archive.daily_claim(0,300)
archive.daily_claim(1,400)
local other_player=wake_requests[#wake_requests]
assert(other_player.player==1,"one account's queue does not block another")
failed_purchase.done({ok=false,error="temporary_network_failure"})
local count=#wake_requests
run_ready(0)
assert(#wake_requests==count+1 and wake_requests[#wake_requests].command.kind=="daily_claim",
    "ready completion cannot replay a failed purchase")
wake_requests[#wake_requests].done({ok=true});other_player.done({ok=true})
assert(archive.has_pending(0) and not tasks["archive_ready:0"],"failed receipt remains without automatic completion retry")

-- Preserve the existing explicit purchase priority among never-started work.
bus.reset();tasks={};archive.init()
archive.daily_claim(0,500);local active=wake_requests[#wake_requests]
archive.daily_claim(0,501);archive.work_upgrade(0,"work_01",0)
active.done({ok=true});run_ready(0)
assert(wake_requests[#wake_requests].command.kind=="work_upgrade","queued explicit purchase keeps priority")
wake_requests[#wake_requests].done({ok=false,terminal=true,error="synthetic_rejection"});run_ready(0)
assert(wake_requests[#wake_requests].command.target_day==501,"terminal rejection wakes the next authorized claim")
wake_requests[#wake_requests].done({ok=true})

-- The callback and an old HTTP completion cannot submit after world reset,
-- including when somebody retained their raw closures outside scheduler.cancel.
archive.daily_claim(0,600);local old_active=wake_requests[#wake_requests]
archive.daily_claim(0,601);old_active.done({ok=true})
local stale_wake=tasks["archive_ready:0"]
assert(stale_wake)
bus.reset();tasks={};archive.init()
local before_stale=#wake_requests
stale_wake();old_active.done({ok=true})
assert(#wake_requests==before_stale and not archive.has_pending(0),"old world callbacks are inert")
print("ARCHIVE_READY_BOUNDARIES_PASS: failed payment not replayed, account isolation, purchase priority, terminal rejection, world reset")
