package.path = "./scripts/vscripts/?.lua;" .. package.path
local calls, pending_reads, pending_finishes = {}, {}, {}
local account, session, profile_loaded = "100", "onboarding_fixture_001", true
local provider = {}
function provider.resolve_account_id() return account end
function provider.onboarding_state(payload, success, failure)
    calls[#calls+1] = {kind="state",payload=payload}
    pending_reads[#pending_reads+1] = {success=success,failure=failure}
end
function provider.onboarding_finish(payload, success, failure)
    calls[#calls+1] = {kind="finish",payload=payload}
    pending_finishes[#pending_finishes+1] = {success=success,failure=failure}
end
package.loaded["systems/player_profile_service"] = {
    get_provider=function() return provider end,
    is_loaded_for_account=function(_, id) return profile_loaded and id==account end,
}
package.loaded["systems/match_setup_service"] = {get_session_id=function() return session end}
local M = require("systems/onboarding_persistence")
local function receipt(status, id, match)
    return {ok=true,account_id=id or account,match_session_id=match or session,version=1,
        required=status=="required",status=status}
end
local outcomes = {}
local function receive(value) outcomes[#outcomes+1] = value end

assert(not M.get(0).loaded and M.get(0).status=="pending")
M.ensure(0,receive)
M.ensure(0,receive)
assert(#calls==1 and #outcomes==0,"concurrent reads must share one authoritative request")
pending_reads[1].success(receipt("required"))
assert(#outcomes==2 and outcomes[1].ok and outcomes[1].error==nil)
assert(M.get(0).loaded and M.get(0).required,"new account must enter required state")
M.ensure(0,receive)
assert(#calls==1 and #outcomes==3,"loaded account metadata must be cached in the same match")

local dispatch = M.finish(0,"skipped",receive)
assert(dispatch.pending==true,"an unfinished HTTP request must not be returned as durable success")
assert(#pending_finishes==1 and M.get(0).required,"skip is not saved until the backend confirms it")
pending_finishes[1].failure("network_timeout")
assert(not outcomes[#outcomes].ok and outcomes[#outcomes].error=="network_timeout" and M.get(0).required)
M.finish(0,"skipped",receive)
M.finish(0,"completed",receive)
assert(#pending_finishes==2,"concurrent finish clicks must share one transaction")
pending_finishes[2].success(receipt("skipped"))
assert(not M.get(0).required and M.get(0).status=="skipped" and outcomes[#outcomes].ok)
local before = #calls
M.finish(0,"completed",receive)
assert(#calls==before and M.get(0).status=="skipped","a durable terminal result cannot regress")

session="onboarding_fixture_002"
assert(not M.get(0).loaded,"a new match must load account metadata instead of reusing stale local data")
M.ensure(0,receive)
pending_reads[#pending_reads].success(receipt("skipped"))
assert(M.get(0).status=="skipped" and not M.get(0).required,"skip must survive another match")

M.init()
M.ensure(0,receive)
local stale = pending_reads[#pending_reads]
account="200"
assert(not M.get(0).loaded)
stale.success(receipt("completed","100"))
assert(not outcomes[#outcomes].ok and outcomes[#outcomes].error=="account_binding_changed")
assert(not M.get(0).loaded,"a previous account response must never unlock a replacement account")
M.ensure(0,receive)
pending_reads[#pending_reads].success(receipt("legacy"))
assert(M.get(0).loaded and not M.get(0).required and M.get(0).status=="legacy")

M.init()
M.ensure(0,receive)
pending_reads[#pending_reads].success(receipt("required","other_account"))
assert(not M.get(0).loaded and not outcomes[#outcomes].ok)
M.ensure(0,receive)
pending_reads[#pending_reads].success(receipt("required"))
M.finish(0,"completed",receive)
pending_finishes[#pending_finishes].success(receipt("required"))
assert(not outcomes[#outcomes].ok and M.get(0).required,"non-terminal acknowledgement is not a saved completion")
M.finish(0,"completed",receive)
pending_finishes[#pending_finishes].success(receipt("completed"))
assert(outcomes[#outcomes].ok and M.get(0).status=="completed")

M.finish(0,"required",receive)
assert(not outcomes[#outcomes].ok and outcomes[#outcomes].error=="onboarding_outcome_invalid")
profile_loaded=false
assert(not M.get(0).loaded)
M.ensure(0,receive)
assert(not outcomes[#outcomes].ok and outcomes[#outcomes].error=="profile_not_loaded")
M.ensure(nil,receive)
assert(not outcomes[#outcomes].ok and outcomes[#outcomes].error=="player_id_invalid")
print("test_onboarding_persistence: PASS (authority, retries, terminal states, pure metadata, account/session guards)")
