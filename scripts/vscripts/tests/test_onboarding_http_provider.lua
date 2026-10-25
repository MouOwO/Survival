package.path = "./scripts/vscripts/?.lua;" .. package.path
local decoder = require("core/json_decoder")
local encoder = require("core/json_encoder")
local session, mode, calls, read_only = "onboarding_http_fixture_001", "pure", {}, false
package.loaded["config/generated/fishing_system_rules"] = {rows={{enabled=true,api_base_url="http://fixture.invalid"}}}
package.loaded["debug/mode_unlock_test"] = {is_enabled=function() return read_only end}
package.loaded["systems/workshop_connection"] = {
    resolve=function(url) return url,"fixture-only-token" end,
    failure=function() return "fixture_request_failed" end,
}
package.loaded["systems/player_web_auth"] = {enabled=function() return false end}
package.loaded["systems/match_setup_service"] = {
    get_session_id=function() return session end,
    get_profile_mode=function() return mode end,
    get_mode=function() return mode end,
    is_mode_selected=function() return true end,
}
Convars = {GetStr=function() return "1" end}
CreateHTTPRequestScriptVM = function(method,url)
    local call = {method=method,url=url};calls[#calls+1]=call
    return {
        SetHTTPRequestHeaderValue=function() end,
        SetHTTPRequestRawPostBody=function(_,_,body) call.body=decoder.decode(body) end,
        SetHTTPRequestAbsoluteTimeoutMS=function() end,
        Send=function(_,callback)
            local outcome=call.body.command.outcome
            callback({StatusCode=200,Body=encoder.encode({ok=true,account_id=call.body.account_id,
                match_session_id=call.body.match_session_id,version=1,required=not outcome,status=outcome or "required"})})
        end,
    }
end
local provider = require("systems/player_profile_providers/http_fishing_provider")
provider.init()
local results,errors={},{}
local function success(value) results[#results+1]=value end
local function failure(value) errors[#errors+1]=value end
provider.onboarding_state({account_id="100"},success,failure)
assert(#calls==1 and #results==1 and #errors==0)
assert(calls[1].url=="http://fixture.invalid/v1/archive/command" and calls[1].method=="POST")
assert(calls[1].body.match_session_id==session and calls[1].body.account_id=="100")
assert(calls[1].body.command.id==session..":onboarding:state" and calls[1].body.command.version==1)
assert(calls[1].body.command.kind=="onboarding_state" and calls[1].body.command.outcome==nil)
assert(calls[1].body.config_hash==nil and calls[1].body.mode==nil,"account metadata must not inherit combat projection or reward configuration")
provider.onboarding_finish({account_id="100",outcome="skipped"},success,failure)
assert(calls[2].body.command.kind=="onboarding_finish" and calls[2].body.command.outcome=="skipped")
assert(calls[2].body.command.id==session..":onboarding:skipped" and results[2].status=="skipped")
read_only=true
provider.onboarding_state({account_id="100"},success,failure)
assert(#calls==2 and errors[1]=="mode_unlock_test_read_only","debug unlock fixtures cannot write account metadata")
print("test_onboarding_http_provider: PASS (authenticated existing route, pure account metadata, read-only guard)")
