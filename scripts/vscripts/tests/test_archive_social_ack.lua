package.path = "scripts/vscripts/?.lua;" .. package.path
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local stats = require("config/generated/player_gameplay_stats")
local profiles, writes, fail_write = {}, 0, false
local tasks, listeners, packets = {}, {}, {}
package.loaded["core/scheduler"] = {
    every = function(_, fn, key) tasks[key] = fn end,
    after = function(_, fn, key) tasks[key] = fn end,
    cancel = function(key) tasks[key] = nil end,
}
package.loaded["systems/player_profile_service"] = {
    get_profile = function(id) return copy(profiles[id]) end,
    get_provider = function() return {persist_save=function() end} end,
    update_save_sections = function(id, sections)
        if fail_write then return {ok=false,error="disk_failed"} end
        for key, value in pairs(sections) do profiles[id].save[key] = copy(value) end
        profiles[id].revision = profiles[id].revision + 1
        writes = writes + 1
        return {ok=true}
    end,
}
local function new_profile(tickets)
    local profile = {revision=1,save={archive={social_tickets={yitie=tickets}},gameplay_stats={},content_inventory={}},entitlements={}}
    for _, row in ipairs(stats.rows) do profile.save.gameplay_stats[row.field_id] = row.default_value end
    return profile
end
profiles[0], profiles[1] = new_profile(30), new_profile(0)
local time = 0
GameRules = {GetGameTime=function() return time end,IsCheatMode=function() return false end}
RandomInt = function(a) return a end
PlayerResource = {GetPlayer=function(_, id) return id end,IsValidPlayerID=function(_, id) return id >= 0 and id <= 2 end}
CustomGameEventManager = {
    RegisterListener=function(_, name, fn) listeners[name] = fn end,
    Send_ServerToPlayer=function(_, id, name, data) packets[#packets+1] = {id=id,name=name,data=copy(data)} end,
}
local archive = require("systems/archive_service")
archive.init()
local function acks(request)
    local result = {}
    for _, packet in ipairs(packets) do
        if packet.name == "survival_archive_social_result" and packet.data.request_id == request then result[#result+1] = packet end
    end
    return result
end
local function latest(request)
    local results = acks(request); assert(#results > 0, "missing correlated ACK: "..request); return results[#results].data
end
local function final(request, ok, pool)
    local ack = latest(request)
    assert(ack.pool_id == (pool or "friend") and ack.request_id == request)
    assert(ack.ok == ok and ack.terminal == true and ack.pending == false)
    return ack
end
local function waiting(request)
    local ack = latest(request)
    assert(ack.ok == false and ack.terminal == false and ack.pending == true)
    return ack
end
local function emit(id, pool, request, advance)
    time = time + (advance or 1)
    listeners.survival_archive_social_draw(nil,{PlayerID=id,pool_id=pool,request_id=request})
end
emit(0,"friend","local_success")
assert(final("local_success",true).revision == 2, "success ACK identifies the committed profile version")
assert(archive.snapshot(0,"friend").revision == latest("local_success").revision)
assert(#acks("local_success") == 2, "one acceptance and one completion ACK")
assert(profiles[0].save.archive.social_tickets.yitie == 29 and writes == 1)
local before_writes = writes
emit(0,"friend","local_success")
assert(final("local_success",true).duplicate == true)
assert(writes == before_writes and profiles[0].save.archive.social_tickets.yitie == 29, "same request never charges twice")
emit(0,"wife","invalid_pool")
final("invalid_pool",false,"wife")
assert(#acks("invalid_pool") == 1 and not archive.has_pending(0), "invalid intent rejected immediately")
emit(0,"friend","bad request")
final("bad request",false)
emit(2,"friend","not_ready")
final("not_ready",false)
assert(not archive.has_pending(2), "unloaded profile rejection must not later grant")
emit(1,"friend","no_tickets")
final("no_tickets",false)
assert(not archive.has_pending(1) and writes == before_writes)
emit(0,"friend","rate_limited",0)
-- Player 0's preceding event was two seconds ago; this first call is accepted.
final("rate_limited",true)
local charged = profiles[0].save.archive.social_tickets.yitie
emit(0,"friend","rate_rejected",0)
final("rate_rejected",false)
assert(profiles[0].save.archive.social_tickets.yitie == charged)

fail_write = true
emit(0,"friend","retry_local")
assert(waiting("retry_local").error == "disk_failed")
assert(archive.has_pending(0) and profiles[0].save.archive.social_tickets.yitie == charged)
emit(0,"friend","retry_local",0)
waiting("retry_local")
assert(archive.has_pending(0), "same pending request cannot be released by the rate guard")
fail_write = false
archive._test.flush(0)
final("retry_local",true)
assert(profiles[0].save.archive.social_tickets.yitie == charged-1)

local submitted = {}
archive.set_provider({submit=function(id, command, done)
    submitted[#submitted+1] = {player=id,command=copy(command),done=done}
end})
emit(0,"friend","remote_retry")
waiting("remote_retry")
assert(#submitted == 1 and submitted[1].command.id:match(":social_draw:remote_retry$"))
for key in pairs(submitted[1].command) do
    assert(key == "id" or key == "kind" or key == "pool_id", "ACK metadata must not change the strict backend command/fingerprint")
end
local command_id = submitted[1].command.id
emit(0,"friend","remote_retry",0)
waiting("remote_retry")
assert(#submitted == 1, "duplicate pending intent does not submit another transaction")
local timeout = tasks["archive_remote_timeout:0"]
assert(timeout); timeout()
assert(waiting("remote_retry").error == "archive_provider_timeout")
archive._test.flush(0)
assert(#submitted == 2 and submitted[2].command.id == command_id, "provider retry keeps transaction identity")
local ack_count = #acks("remote_retry")
submitted[1].done({ok=true})
assert(#acks("remote_retry") == ack_count and archive.has_pending(0), "late stale callback cannot finalize a newer attempt")
local authoritative = require("systems/archive_settlement").settle(copy(profiles[0]),submitted[2].command,false)
assert(authoritative.ok)
profiles[0].save.archive, profiles[0].save.gameplay_stats = authoritative.archive, authoritative.gameplay_stats
profiles[0].revision = profiles[0].revision + 1
submitted[2].done({ok=true})
assert(final("remote_retry",true).revision == profiles[0].revision, "remote ACK follows authoritative snapshot application")
assert(not archive.has_pending(0) and profiles[0].save.archive.social_tickets.yitie == charged-2)
ack_count = #acks("remote_retry")
submitted[2].done({ok=true})
assert(#acks("remote_retry") == ack_count, "provider duplicate completion is ignored")
emit(0,"friend","remote_denied")
waiting("remote_denied")
submitted[3].done({ok=false,terminal=true,error="backend_rejected"})
assert(final("remote_denied",false).error == "backend_rejected")
assert(not archive.has_pending(0))

archive.set_provider({submit=function(_, _, done) done({ok=true}) end})
emit(0,"friend","remote_sync")
final("remote_sync",true)
assert(#acks("remote_sync") == 2, "a synchronous provider cannot emit pending after final ACK")
archive.begin_finalization()
emit(0,"friend","finalizing")
final("finalizing",false)
assert(#acks("finalizing") == 1 and not archive.has_pending(0))
print("archive social ACK: success, rejection, deduplication, pending retry and asynchronous completion passed")
