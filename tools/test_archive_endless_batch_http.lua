-- Real game HTTP provider/adapter with native transport callbacks replaced.
package.path="scripts/vscripts/?.lua;"..package.path
local encode=require("core/json_encoder").encode
local decode=require("core/json_decoder").decode
local requests,applications,provider={},0,nil
package.loaded["config/generated/fishing_system_rules"]={rows={{enabled=true,api_base_url="http://fixture.local"}}}
package.loaded["systems/match_setup_service"]={is_mode_selected=function() return true end,get_session_id=function() return "fixture_match_001" end}
Convars={GetStr=function(_,name) return name=="survival_fishing_api_token" and "fixture-only-not-a-real-token" or "1" end}
PlayerResource={GetSteamAccountID=function() return 100 end}
CreateHTTPRequestScriptVM=function(method,url)
    local request={method=method,path=url:gsub("http://fixture.local","")}
    requests[#requests+1]=request
    function request:SetHTTPRequestHeaderValue() end
    function request:SetHTTPRequestAbsoluteTimeoutMS() end
    function request:SetHTTPRequestRawPostBody(_,body) self.payload=decode(body) end
    function request:Send(callback) self.callback=callback end
    return request
end
package.loaded["systems/player_profile_service"]={
    get_provider=function() return provider end,
    apply_snapshot=function(_,profile,reason)
        assert(reason=="archive_endless_batch" and profile.account_id=="100")
        applications=applications+1;return {ok=true}
    end,
}
provider=require("systems/player_profile_providers/http_fishing_provider")
local adapter=require("systems/archive_http_adapter")
local commands={{id="fixture:endless:1",kind="endless",wave=1,difficulty=10},
    {id="fixture:endless:2",kind="endless",wave=2,difficulty=10},
    {id="fixture:endless:3",kind="endless",wave=3,difficulty=10}}
local received
local function response(request,status,body) request.callback({StatusCode=status,Body=encode(body)}) end
local function submit() adapter.submit_endless_batch(0,commands,function(result) received=result end) end
local function setup() requests,applications,received={},0,nil;provider.init() end

setup();submit()
assert(#requests==1 and requests[1].path=="/v1/archive/config" and not received)
assert(requests[1].payload.account_id=="100" and requests[1].payload.match_session_id=="fixture_match_001",
    "capability reads must pass production's shared account/session gate")
response(requests[1],200,{capabilities={endless_batch=1,endless_batch_limit=32}})
assert(#requests==2 and requests[2].path=="/v1/archive/endless-batch")
assert(#requests[2].payload.commands==3 and requests[2].payload.match_session_id=="fixture_match_001")
response(requests[2],200,{ok=true,results={{id=commands[1].id,ok=true},{id=commands[2].id,ok=true},{id=commands[3].id,ok=true}},profile={account_id="100",revision=4}})
assert(received.ok and applications==1,"one batch applies only the final authoritative profile")
submit();assert(#requests==3 and requests[3].path=="/v1/archive/endless-batch","capability metadata is cached")
response(requests[3],500,{error="internal_error"})
assert(not received.ok and not received.terminal,"transport failures cannot acknowledge earned waves")

setup();submit();response(requests[1],200,{protocol=1})
for index=1,3 do
    local request=requests[index+1]
    assert(request.path=="/v1/archive/command" and request.payload.command.id==commands[index].id)
    response(request,200,{ok=true,profile={account_id="100",revision=index}})
end
assert(received.ok and #received.results==3 and applications==1,"old servers serially drain the full window and apply one final profile")

setup();submit();response(requests[1],200,{protocol=1})
response(requests[2],200,{ok=true,profile={account_id="100",revision=1}})
response(requests[3],503,{error="busy"})
assert(not received.ok and #received.results==1 and received.results[1].id==commands[1].id,
    "partial old-server success retains the exact successful receipt only")

setup();submit();response(requests[1],200,{capabilities={endless_batch=1}})
response(requests[2],404,{error="route_not_found"})
assert(requests[3].path=="/v1/archive/command","a stale advertised capability falls back to existing intents")
for index=1,3 do response(requests[index+2],200,{ok=true,profile={account_id="100",revision=index}}) end
assert(received.ok and applications==1)

setup();submit();response(requests[1],200,{capabilities={endless_batch=1}})
response(requests[2],200,{ok=true,results={{id=commands[1].id,ok=true}},profile={account_id="999",revision=1}})
assert(not received.ok and received.results==nil and applications==0,"account mismatch never acknowledges a batch")
print("ARCHIVE_ENDLESS_BATCH_HTTP_PASS: capability gate, one profile apply, final match identity, cached/new/stale capability, bounded legacy fallback, partial failure, account isolation")
