-- Run from the repository root: lua tools/test_archive_retry_snapshot.lua
-- Uses the real archive service/projectors; no game process or backend needed.
package.path = "scripts/vscripts/?.lua;" .. package.path

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local original_modules = {}
for name in pairs(package.loaded) do original_modules[name] = true end

local function run_case()
    -- Each repeat gets fresh real services, clocks, subscriptions and page
    -- caches. Stale module references must not mask a changed wire snapshot.
    local unload = {}
    for name in pairs(package.loaded) do
        if not original_modules[name] then unload[#unload + 1] = name end
    end
    for _, name in ipairs(unload) do package.loaded[name] = nil end
    local stats = require("config/generated/player_gameplay_stats")
    local profiles, tasks, listeners, packets = {}, {}, {}, {}
    local reads, submits, writes = 0, 0, 0
    local day_time = 1700000000
    for id = 0, 3 do
        local profile = {revision=1, save={gameplay_stats={}, content_inventory={}}, entitlements={}}
        for _, row in ipairs(stats.rows) do profile.save.gameplay_stats[row.field_id] = row.default_value end
        profiles[id] = profile
    end
    profiles[0].entitlements.archive_pass = {active=true, expires_at=day_time + 10}
    package.loaded["core/scheduler"] = {
        every=function(_, callback, key) tasks[key] = callback end,
        after=function(_, callback, key) tasks[key] = callback end,
        cancel=function(key) tasks[key] = nil end,
    }
    package.loaded["systems/player_profile_service"] = {
        get_account_profile=function(id) reads = reads + 1; return copy(profiles[id]) end,
        get_profile=function() error("archive must use the account view, not the combat projection") end,
        get_provider=function() return {persist_save=function() end} end,
        update_save_sections=function() writes = writes + 1; error("remote retry must not settle locally") end,
    }
    package.loaded["systems/archive_http_adapter"] = {enabled=function() return false end}
    GameRules = {GetGameTime=function() return 0 end, IsCheatMode=function() return false end}
    IsInToolsMode = function() return true end
    RandomInt = function(minimum) return minimum end
    PlayerResource = {
        GetPlayer=function(_, id) return profiles[id] and id end,
        IsValidPlayerID=function(_, id) return profiles[id] ~= nil end,
    }
    CustomGameEventManager = {
        RegisterListener=function(_, name, callback) listeners[name] = callback end,
        Send_ServerToPlayer=function(_, id, name, data)
            packets[#packets + 1] = {id=id, name=name, data=copy(data)}
        end,
    }
    local archive = require("systems/archive_service")
    archive.init()
    archive.set_clock(function() return day_time end)
    local result_kind, first_ids = "retry", {}
    archive.set_provider({submit=function(id, command, done)
        submits = submits + 1
        if first_ids[id] then assert(first_ids[id] == command.id, "retry changed the command id")
        else first_ids[id] = command.id end
        if result_kind == "success" then done({ok=true})
        else done({ok=false, error="account_id_unresolved"}) end
    end})
    local stages = {}
    local function collect(name)
        stages[name], packets = packets, {}
        return stages[name]
    end
    for id = 0, 3 do assert(archive.record_boss(id, "fixture_boss").ok ~= false) end
    assert(#collect("initial") > 0, "initial snapshots were not published")
    reads, submits = 0, 0
    local retry = assert(tasks.archive_retry)
    for _ = 1, 34 do retry() end
    assert(reads == 136, "expected one account snapshot per player/retry, got " .. reads)
    assert(submits == 136, "remote retry count changed: " .. submits)
    assert(#collect("unchanged") == 0, "unchanged snapshots must stay suppressed")
    for id = 0, 3 do assert(archive.has_pending(id), "transient failure must remain queued") end

    -- A time-sensitive entitlement expires without any profile revision change.
    day_time = day_time + 11
    retry()
    assert(#collect("expiry") > 0, "expiry must publish a fresh delta")
    assert(profiles[0].revision == 1 and archive.snapshot(0, "boss").has_pass == 0)

    -- Extensions may mutate their private argument, never another category's
    -- batch input or the authoritative account. Only clear may change here.
    archive.register_category("clear", function(profile)
        profile.save.content_inventory.lottery_attribute_crystal = 987
        return {{id="custom", name="custom", count=1}}
    end)
    retry()
    local custom = collect("custom")
    assert(#custom > 0, "custom projector did not publish")
    for _, packet in ipairs(custom) do
        assert(packet.data.category_id == "clear", "custom projector contaminated another page")
    end
    for id = 0, 3 do
        assert(profiles[id].save.content_inventory.lottery_attribute_crystal == nil,
            "custom projector mutated the authoritative account")
        assert(#archive.snapshot(id, "points").rows == 0, "custom projector contaminated points")
    end
    retry()
    assert(#collect("custom_unchanged") == 0, "extension created a spurious retry delta")

    -- No cross-callback revision cache: real changes while pending still show.
    profiles[0].revision = profiles[0].revision + 1
    profiles[0].save.content_inventory.lottery_attribute_crystal = 3
    retry()
    assert(#collect("revision") > 0, "pending retry hid a new profile revision")
    local found = false
    for _, row in ipairs(archive.snapshot(0, "points").rows) do
        if row.id == "lottery_attribute_crystal" then assert(row.count == 3); found = true end
    end
    assert(found, "updated inventory was absent from the points page")
    assert(profiles[1].revision == 1 and #archive.snapshot(1, "points").rows == 0,
        "another player's account was changed")

    result_kind = "success"
    retry()
    assert(#collect("success") > 0, "confirmed success must publish pending=0")
    for id = 0, 3 do assert(not archive.has_pending(id), "success did not drain the queue") end
    reads, submits = 0, 0
    retry()
    assert(reads == 0 and submits == 0 and #packets == 0, "drained queues must do no retry work")
    assert(writes == 0, "remote retry wrote local account data")
    return stages
end

local first, second = run_case(), run_case()
assert(equal(first, second), "repeat changed packet data, chunking, sequences or deltas")
print("PASS archive_retry_snapshot: 2 repeats, 4 players x 34 retries, reads=136 submits=136 each; packets and isolation stable")
