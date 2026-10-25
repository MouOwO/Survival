package.path = "scripts/vscripts/?.lua;" .. package.path

local tools, server, mode = true, true, "standard"
local session = "offline_onboarding_session_1"
local values = {survival_offline_logic_test="1",survival_offline_onboarding_test="0"}
local identities = {[0]=885195478, [1]=123456789}
local http_calls, file_calls = 0, 0
Convars = {
    RegisterConvar=function(_, key, value) if values[key] == nil then values[key] = value end end,
    GetStr=function(_, key) return values[key] or "" end,
}
IsServer = function() return server end
IsInToolsMode = function() return tools end
PlayerResource = {
    IsValidPlayerID=function(_, id) return identities[id] ~= nil end,
    IsFakeClient=function() return false end,
    GetPlayer=function(_, id)
        if identities[id] ~= nil then return {GetPlayerID=function() return id end} end
    end,
    GetSteamAccountID=function(_, id) return identities[id] end,
}
CreateHTTPRequestScriptVM=function() http_calls=http_calls+1;error("offline onboarding made HTTP request") end
package.loaded["core/logger"] = {info=function() end,warn=function() end}
package.loaded["core/test_access_policy"] = {
    allowed=function(id) return id==0 or id==1 end,
    enforce=function(id) return id==0 or id==1 end,
}
package.loaded["systems/player_web_auth"] = {enabled=function() return false end}
package.loaded["systems/match_setup_service"] = {
    get_session_id=function() return session end,
    get_mode=function() return mode end,
    get_profile_mode=function() return mode end,
    is_mode_selected=function() return mode ~= nil end,
}
local offline = require("debug/offline_logic_test")
local profiles = require("systems/player_profile_service")
local persistence = require("systems/onboarding_persistence")
assert(offline.configure())
profiles.init(assert(offline.profile_options()))
local provider = assert(profiles.get_provider())
local account = assert(provider.resolve_account_id(0))
local other = assert(provider.resolve_account_id(1))
assert(account ~= other)
assert(provider.resolve_account_id(2) == nil, "offline entry policy remains active")

local original_open = io.open
io.open=function() file_calls=file_calls+1;error("offline onboarding touched a fixture file") end
local function request(method, payload, expected_error)
    local result, reason, callbacks
    callbacks=0
    provider[method](payload, function(value) result=value;callbacks=callbacks+1 end,
        function(value) reason=value;callbacks=callbacks+1 end)
    assert(callbacks==1, "exactly one receipt or failure is returned")
    if expected_error then
        assert(reason==expected_error and result==nil, tostring(reason))
        return
    end
    assert(reason==nil and result and result.ok)
    assert(result.account_id==payload.account_id and result.match_session_id==session)
    assert(result.version==1 and result.required==(result.status=="required"))
    return result
end
local function read(id) return request("onboarding_state", {account_id=id}) end
local function finish(id, outcome)
    return request("onboarding_finish", {account_id=id, outcome=outcome})
end

assert(read(account).status=="legacy" and not read(account).required,
    "ordinary offline QA must not be forced into the onboarding preview")
request("onboarding_finish", {account_id=account,outcome="completed"}, "offline_onboarding_not_enabled")
assert(read(account).status=="legacy", "ordinary offline finish does not manufacture terminal metadata")
values.survival_offline_onboarding_test="1"
assert(read(account).status=="legacy", "changing a convar cannot enable a different launch mode")
-- Simulate a fresh server launch. The helper deliberately latches its first
-- configuration rather than permitting runtime convar changes to enable it.
package.loaded["debug/offline_onboarding_test"]=nil
assert(offline.configure())
require("core/event_bus").reset()
profiles.init(assert(offline.profile_options()))
provider=assert(profiles.get_provider())
account=assert(provider.resolve_account_id(0))
other=assert(provider.resolve_account_id(1))
identities[2]=0
local no_steam=assert(provider.resolve_account_id(2))
assert(no_steam=="offline-player-2" and read(no_steam).status=="required",
    "a real offline human without Steam receives only a match-local identity")
assert(finish(no_steam,"skipped").status=="skipped")
identities[2]=222222222
local arrived=assert(provider.resolve_account_id(2))
assert(arrived=="222222222" and read(arrived).status=="required"
    and read(no_steam).status=="skipped", "Steam arriving later creates a separately bound account")

request("onboarding_state", {}, "offline_account_unavailable")
request("onboarding_state", {account_id="unknown"}, "offline_account_unavailable")
request("onboarding_state", {account_id=tonumber(account)}, "offline_account_unavailable")
request("onboarding_state", {account_id=account,match_session_id="another_session"}, "match_profile_mismatch")
request("onboarding_finish", {account_id=account,outcome="required"}, "onboarding_outcome_invalid")
request("onboarding_finish", nil, "onboarding_outcome_invalid")
assert(read(account).status=="required" and read(other).status=="required")
local exposed = read(account)
exposed.status, exposed.required, exposed.account_id = "completed", false, other
assert(read(account).status=="required", "callers cannot mutate private metadata by changing a receipt")

assert(profiles.authenticate_player(0,"offline_onboarding_test").ok)
assert(profiles.load_player(0).ok)
persistence.init()
local loaded, saved
local dispatch = persistence.ensure(0,function(value) loaded=value end)
assert(dispatch.ok and not dispatch.pending and loaded.ok and loaded.loaded and loaded.required)
dispatch = persistence.finish(0,"completed",function(value) saved=value end)
assert(dispatch.ok and not dispatch.pending and saved.ok and saved.status=="completed")
assert(not persistence.get(0).required and read(account).status=="completed")
assert(finish(account,"skipped").status=="completed", "first terminal result wins across repeated/contradictory calls")
assert(finish(other,"skipped").status=="skipped")
assert(finish(other,"completed").status=="skipped", "skipped is also terminal")

mode = "pure"
assert(read(account).status=="completed", "mode changes cannot reset account metadata in the same session")
assert(profiles.load_player(0).ok)
assert(not persistence.get(0).required)
identities[0] = 111111111
local rebound = assert(provider.resolve_account_id(0))
assert(rebound~=account and read(rebound).status=="required")
assert(read(account).status=="completed", "a replacement account never overwrites the previous account")
assert(not persistence.get(0).loaded, "persistence refuses the old loaded profile after account replacement")

session = "offline_onboarding_session_2"
request("onboarding_state", {account_id=account}, "offline_account_unavailable")
identities[0] = tonumber(account)
assert(provider.resolve_account_id(0)==account)
assert(read(account).status=="required", "next match always begins a fresh guide without cloud first-login data")
assert(profiles.authenticate_player(0,"new_offline_match").ok and profiles.load_player(0).ok)
loaded=nil
persistence.ensure(0,function(value) loaded=value end)
assert(loaded and loaded.ok and loaded.required, "persistence follows the newly bound match receipt")
assert(finish(account,"skipped").status=="skipped")
provider.init()
assert(provider.resolve_account_id(0)==account and read(account).status=="required", "provider reset clears only memory")

tools = false
assert(not pcall(provider.onboarding_state,{account_id=account},function() end,error))
assert(not pcall(provider.onboarding_finish,{account_id=account,outcome="completed"},function() end,error))
assert(not pcall(provider.onboarding_finish,{account_id=account,outcome="invalid"},function() end,error))
tools = true
assert(http_calls==0 and file_calls==0, "no onboarding path reads/writes files or contacts cloud APIs")
io.open=original_open
print("OFFLINE_ONBOARDING_PROVIDER_PASS: guarded memory-only receipts, real account/session binding, persistence integration, terminal first-winner, mode sharing, next-match reset, no HTTP/files")
