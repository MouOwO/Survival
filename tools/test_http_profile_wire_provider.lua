-- Isolated provider/adapter integration; no live HTTP or player data.
package.path='scripts/vscripts/?.lua;'..package.path
local json=require('core/json_decoder')
local encode=require('core/json_encoder').encode
local requests,reads,applies,completed={},0,0,0
local session='fixture-session-001'
local account='100'
local hash=string.rep('a',64)
package.loaded['config/generated/fishing_system_rules']={rows={{enabled=true,api_base_url='https://example.invalid'}}}
package.loaded['config/generated/archive_http_bundle']={hash=hash}
package.loaded['debug/mode_unlock_test']={is_enabled=function()return false end}
package.loaded['systems/workshop_connection']={failure=function(body,fallback)return body and body.error or fallback end}
package.loaded['systems/player_web_auth']={enabled=function()return true end,
    resolve=function(_,_,success)success('https://example.invalid','fixture-token')end}
package.loaded['systems/match_setup_service']={is_mode_selected=function()return true end,
    get_session_id=function()return session end,get_mode=function()return 'standard'end}
PlayerResource={GetSteamAccountID=function()return tonumber(account)end}
Convars={GetStr=function()return '1'end}
CreateHTTPRequestScriptVM=function(method,url)
    local request={method=method,url=url}
    function request:SetHTTPRequestHeaderValue()end
    function request:SetHTTPRequestRawPostBody(_,body)self.body=json.decode(body)end
    function request:SetHTTPRequestAbsoluteTimeoutMS()end
    function request:Send(callback)self.complete=callback;requests[#requests+1]=self end
    return request
end
local provider=require('systems/player_profile_providers/http_fishing_provider');provider.init()
local applied
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
    apply_snapshot=function(_,snapshot)applies=applies+1;applied=snapshot;return{ok=true}end,
    refresh_player=function(_,reason)
        reads=reads+1;assert(completed==reads,'pending was not released before recovery')
        assert(reason=='http_profile_wire_recovery')
    end}
package.loaded['ui/compact_profile_context']={with=function(_,_,fn)return fn()end}
package.loaded['ui/compact_daily_projection']={command_changes=function()return{}end}
package.loaded['ui/compact_lottery_projection']={command_changes=function()return{}end}
local adapter=require('systems/archive_http_adapter')
local function submit(callback)
    adapter.submit(0,{id='fixture-operation',kind='lottery_draw',pool_id='map',count=10},callback,hash,true)
    assert(requests[#requests].body.response_capabilities.archive_profile_refs_v1==true)
    assert(requests[#requests].body.response_capabilities.lottery_committed_profile_v1==true)
end
local result
submit(function(value)result=value end)
requests[1].complete({StatusCode=200,Body=encode({ok=true,profile={account_id=account,save={tokens=7},
    account_profile={account_id=account}},_http_profile_refs={v=1,m=32}})})
assert(result.ok and applies==1 and reads==0 and #requests==1)
assert(applied.account_profile.save.tokens==7 and applied.account_profile.save~=applied.save)
-- A broken profile representation terminates the mutation and performs one read.
submit(function(value)completed=completed+1;result=value end)
requests[2].complete({StatusCode=200,Body=encode({ok=true,profile={account_id=account},_http_profile_refs={v=2,m=32}})})
assert(not result.ok and result.terminal and reads==1 and applies==1 and #requests==2)
-- A stale world's failure cannot read or apply state for the new world.
submit(function(value)result=value end)
session='fixture-session-002'
requests[3].complete({StatusCode=200,Body=encode({ok=true,profile={account_id=account},_http_profile_refs={v=2,m=32}})})
assert(result.terminal and reads==1 and applies==1 and #requests==3)
-- Legacy full replies remain valid; unrelated requests carry no new capability.
provider.fetch_snapshot(account,function()end,function()end)
assert(requests[4].body.response_capabilities==nil)
print('HTTP_PROFILE_WIRE_PROVIDER_PASS one-apply/single-read-recovery/no-mutation-retry/stale-world/legacy-scope')
