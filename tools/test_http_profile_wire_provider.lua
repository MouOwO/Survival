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
local applied,apply_error
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
    apply_snapshot=function(_,snapshot)
        if apply_error then return{ok=false,error=apply_error}end
        applies=applies+1;applied=snapshot;return{ok=true}
    end,
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
    assert(requests[#requests].body.response_capabilities.archive_profile_refs_v2==true)
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
local function v2(revision)
    return{ok=true,profile={account_id=account,revision=revision,save={tokens=9},
        account_profile={account_id=account},progression={},daily_limits={day_key='synthetic-day',
            rows={{key='daily_test',earned=2,limit=10,remaining=8,capped=0}}}},_http_profile_refs={v=2,m=928}}
end
submit(function(value)result=value end)
requests[5].complete({StatusCode=200,Body=encode(v2(12))})
assert(result.ok and result.lottery_profile_applied and applies==2 and reads==1 and #requests==5)
assert(applied.account_profile.save.tokens==9 and applied.account_profile.save~=applied.save)
assert(applied.daily_limits.by_key.daily_test.remaining==8)
assert(applied.daily_limits.rows[1]~=applied.daily_limits.by_key.daily_test)
assert(applied.progression.daily_limits.by_key.daily_test.earned==2)
-- An older receipt still follows normal profile revision validation after v2 decoding.
apply_error='snapshot_revision_stale'
submit(function(value)result=value end)
requests[6].complete({StatusCode=200,Body=encode(v2(11))})
assert(result.ok and not result.lottery_profile_applied and applies==2 and applied.revision==12)
apply_error=nil
-- A real v2 row failure releases the pending mutation before exactly one read.
submit(function(value)completed=completed+1;result=value end)
local broken=v2(13)
broken.profile.daily_limits.rows[2]=broken.profile.daily_limits.rows[1]
requests[7].complete({StatusCode=200,Body=encode(broken)})
assert(not result.ok and result.terminal and reads==2 and applies==2 and #requests==7)
submit(function(value)result=value end)
session='fixture-session-003'
requests[8].complete({StatusCode=200,Body=encode(broken)})
assert(result.terminal and reads==2 and applies==2 and #requests==8)
print('HTTP_PROFILE_WIRE_PROVIDER_PASS v1/v2/daily-rebuild/single-read-recovery/no-mutation-retry/stale-revision/stale-world/legacy-scope')
