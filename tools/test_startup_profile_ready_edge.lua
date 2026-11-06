-- Actual startup module and existing lifecycle fixture; no real HTTP/native IO.
-- Do not manually run its thinker after profile completion: that hid the bug.
local f=assert(io.open("scripts/vscripts/tests/test_startup_loading_service.lua","rb"))
local source=f:read("*a"); f:close()
local boundary=assert(source:find("-- Browser approval remains",1,true))
local fixture=source:sub(1,boundary-1)
local cases=[=[

local function admitted_fixture(count)
    local service=fixture(count)
    for _,request in ipairs(requests) do success(request,{n5=1,n6=1}) end
    assets_done()
    for id=0,count-1 do ui(service,id) end
    service.tick()
    assert_admitted(service)
    return service
end

do
    local service=admitted_fixture(4)
    local released=0
    service.gameplay_gate(function() released=released+1 end)
    select_mode(service,"standard")
    assert(#profile_requests==4 and not service.snapshot().profiles_ready)
    local reads=0
    local original_loaded=modules.profiles.is_loaded_for_account
    modules.profiles.is_loaded_for_account=function(...) reads=reads+1 return original_loaded(...) end
    local prior=#history
    for n=1,4 do
        profile_success(profile_requests[n])
        assert(service.snapshot().profiles_ready==(n==4))
        assert(service.is_gameplay_ready()==(n==4))
    end
    assert(released==1 and #profile_requests==4 and #history-prior==4)
    local done_reads,done_publications=reads,#history
    for n=1,100 do profile_requests[4].success({ok=true}) end
    assert(reads==done_reads and #history==done_publications and released==1)
    print("ASYNC_4_PLAYERS_PASS: no thinker advancement, completion_publications=4 duplicate100_reads=0 duplicate100_publications=0 scans="..done_reads)
end
do
    local service=admitted_fixture(4)
    local original_load=modules.profiles.load_player
    modules.profiles.load_player=function(...)
        original_load(...)
        profile_success(profile_requests[#profile_requests])
        return {ok=true,pending=false}
    end
    select_mode(service,"standard")
    assert(service.is_gameplay_ready() and service.snapshot().profiles_ready and #profile_requests==4)
    local seen_ready=false
    for _,state in ipairs(history) do
        if state.profiles_ready then seen_ready=true end
        assert(not seen_ready or state.profiles_ready,"outer synchronous tick must not overwrite ready")
    end
    print("SYNC_4_PLAYERS_PASS: one load each, coalesced followup, no true-to-false overwrite")
end
do
    local service=admitted_fixture(1)
    select_mode(service,"standard")
    profile_pending[0]=false
    profile_requests[1].failure("profile_load_failed")
    assert(not service.is_gameplay_ready() and service.snapshot().setup.error=="profile_load_failed")
    assert(#profile_requests==1)
    for n=1,100 do profile_requests[1].failure("profile_load_failed") end
    assert(#profile_requests==1)
    time=4 service.tick() assert(#profile_requests==1)
    time=5 service.tick() assert(#profile_requests==2)
    profile_success(profile_requests[2])
    assert(service.snapshot().profiles_ready)
    print("FAILURE_RETRY_PASS: existing five-second deadline, no recursive requests")
end
do
    local service=admitted_fixture(1)
    select_mode(service,"standard")
    local old=profile_requests[1]
    humans[0].account=9999
    local prior=#history
    old.success({ok=true})
    assert(#history==prior and not service.is_gameplay_ready())
    print("ACCOUNT_REUSE_PASS: wrong current owner cannot advance or publish")
end
do
    local service=admitted_fixture(1)
    select_mode(service,"standard")
    local old=profile_requests[1]
    service.init({})
    local prior=#history
    old.success({ok=true}) old.failure("profile_load_failed")
    assert(#history==prior and not service.is_gameplay_ready())
    print("OLD_EPOCH_PASS: old success/failure cannot advance replacement world")
end
do
    local service=admitted_fixture(1)
    select_mode(service,"standard")
    local before_publish=CustomNetTables.SetTableValue
    CustomNetTables.SetTableValue=function() error("fixture one-off native publish failure") end
    local ok=pcall(function() profile_success(profile_requests[1]) end)
    assert(not ok)
    CustomNetTables.SetTableValue=before_publish
    service.tick()
    assert(service.snapshot().profiles_ready and service.is_gameplay_ready())
    print("ERROR_UNWIND_PASS: failed native publication does not leave reentry guard set")
end

]=]
assert(loadstring(fixture..cases,"startup_profile_ready_edge"))()
