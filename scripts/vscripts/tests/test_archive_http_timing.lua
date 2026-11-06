package.path='scripts/vscripts/?.lua;'..package.path
local encode=require('core/json_encoder').encode
local decode=require('core/json_decoder').decode
local ordinary_print=print
local clock,requests,logs,applies=0,{},{},0
local fail_auth,throw_apply,throw_print=false,false,false
local account='983746512'
local private='private-token-and-response-DO-NOT-LOG'
local hash=string.rep('a',64)
GetSystemTimeMS=function()return clock end
print=function(line)
    if throw_print then error('synthetic-print-failure')end
    logs[#logs+1]=line
end
package.loaded['core/json_encoder']={encode=function(value)clock=clock+2;return encode(value)end}
package.loaded['core/json_decoder']={decode=function(value)clock=clock+3;return decode(value)end}
package.loaded['config/generated/fishing_system_rules']={rows={{enabled=true,api_base_url='https://example.invalid'}}}
package.loaded['config/generated/archive_http_bundle']={hash=hash}
package.loaded['debug/mode_unlock_test']={is_enabled=function()return false end}
package.loaded['systems/workshop_connection']={failure=function(body,fallback)return body and body.error or fallback end}
package.loaded['systems/player_web_auth']={enabled=function()return true end,
    resolve=function(_,_,success,failure)
        clock=clock+7
        if fail_auth then failure(private)else success('https://example.invalid',private)end
    end}
package.loaded['systems/match_setup_service']={is_mode_selected=function()return true end,
    get_session_id=function()return 'private-match-DO-NOT-LOG'end,get_mode=function()return 'standard'end}
PlayerResource={GetSteamAccountID=function()return tonumber(account)end}
Convars={GetStr=function()return '1'end}
CreateHTTPRequestScriptVM=function(method,url)
    local request={method=method,url=url,headers={}}
    function request:SetHTTPRequestHeaderValue(k,v)self.headers[k]=v end
    function request:SetHTTPRequestRawPostBody(_,body)self.raw=body;self.body=decode(body)end
    function request:SetHTTPRequestAbsoluteTimeoutMS(value)self.timeout=value end
    function request:Send(callback)self.complete=callback;requests[#requests+1]=self end
    return request
end
local provider=require('systems/player_profile_providers/http_fishing_provider')
provider.init()
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
    apply_snapshot=function(_,snapshot)
        applies=applies+1;clock=clock+41
        assert(snapshot.account_id==account)
        if throw_apply then error('synthetic-original-apply-error')end
        return {ok=true}
    end}
package.loaded['ui/compact_profile_context']={with=function(_,_,fn)return fn()end}
package.loaded['ui/compact_daily_projection']={command_changes=function()return {}end}
package.loaded['ui/compact_lottery_projection']={command_changes=function()return {}end}
local adapter=require('systems/archive_http_adapter')
local output
local command={id='private-command-DO-NOT-LOG',kind='lottery_draw',pool_id='map',count=10,request_id=private}
adapter.submit(0,command,function(result)clock=clock+9;output=result end,hash,true)
assert(#requests==1 and #logs==0,'no polling or premature completion log')
local request=requests[1]
assert(request.body.response_capabilities.lottery_committed_profile_v1==true)
assert(request.body.command.request_id==private and request.body.command.count==10)
assert(request.body.timing==nil and request.body.command.timing==nil,'diagnostics never enter durable/HTTP payload')
clock=clock+200
local body=encode({ok=true,terminal=true,profile={account_id=account},response={secret=private}})
request.complete({StatusCode=200,Body=body})
assert(output.ok and output.lottery_profile_applied and applies==1)
assert(#logs==1 and #logs[1]<=768)
local line=logs[1]
for _,text in ipairs({private,account,'private-command','private-match','account_id','Authorization'})do
    assert(not line:find(text,1,true),'private data leaked to timing')
end
for _,field in ipairs({'resolve_ms=7.000','encode_ms=2.000','http_ms=200.000','decode_ms=3.000',
    'callback_ms=50.000','profile_ms=41.000','total_ms=262.000','count=10','status=200','callback_error=0'})do
    assert(line:find(field,1,true),field..' missing: '..line)
end

-- Read-only profile/catalog operations and automatic reward events stay quiet.
local before_logs=#logs
provider.archive_submit({account_id=account,command={kind='boss_kill'}},function()end,function()assert(false)end)
requests[#requests].complete({StatusCode=200,Body='{"ok":true}'})
provider.fetch_snapshot(account,function()end,function()assert(false)end)
requests[#requests].complete({StatusCode=200,Body=encode({account_id=account,
    match_session_id='private-match-DO-NOT-LOG',mode='standard'})})
provider.lottery_catalog({account_id=account},function()end,function()assert(false)end)
requests[#requests].complete({StatusCode=200,Body='{"ok":true}'})
assert(#logs==before_logs)

-- Each actual attempt has its own record; no fixed delay or automatic retry.
local before_requests=#requests
local failure
provider.archive_submit({account_id=account,command={kind='daily_claim'}},function()assert(false)end,
    function(reason,status)failure={reason,status}end)
requests[#requests].complete({StatusCode=503,Body=encode({error=private})})
assert(failure[1]==private and failure[2]==503 and #requests==before_requests+1)
assert(#logs==before_logs+1 and logs[#logs]:find('status=503',1,true))
assert(not logs[#logs]:find(private,1,true))
fail_auth=true
provider.archive_submit({account_id=account,command={kind='lottery_draw',count=1}},function()assert(false)end,
    function(reason)failure=reason end)
assert(failure==private and #requests==before_requests+1 and #logs==before_logs+2)
assert(logs[#logs]:find('http_ms=0.000',1,true))
fail_auth=false

-- A failing local subscriber is measured once and its original error survives.
throw_apply=true
adapter.submit(0,command,function()assert(false)end,hash,true)
local ok,reason=pcall(requests[#requests].complete,{StatusCode=200,Body=body})
assert(not ok and tostring(reason):find('synthetic-original-apply-error',1,true))
assert(applies==2 and logs[#logs]:find('callback_error=1',1,true))
assert(not logs[#logs]:find('synthetic-original',1,true))
throw_apply=false

-- Output failure cannot change a committed result or cause a repeated apply.
throw_print=true
adapter.submit(0,command,function(result)output=result end,hash,true)
requests[#requests].complete({StatusCode=200,Body=body})
assert(output.ok and applies==3)
throw_print=false

-- Transport status is retained even when a 200 body cannot be decoded.
provider.archive_submit({account_id=account,command={kind='daily_claim'}},function()assert(false)end,
    function(reason)failure=reason end)
requests[#requests].complete({StatusCode=200,Body='not-json-'..private})
assert(failure=='http_json_invalid'and logs[#logs]:find('status=200',1,true))
assert(not logs[#logs]:find(private,1,true))

-- Interleaved responses own independent spans; no shared request timer.
provider.archive_submit({account_id=account,command={kind='daily_claim'}},function()end,function()assert(false)end)
local first=requests[#requests]
clock=clock+5
provider.archive_submit({account_id=account,command={kind='vip_claim'}},function()end,function()assert(false)end)
local second=requests[#requests]
clock=clock+20;second.complete({StatusCode=200,Body='{"ok":true}'})
assert(logs[#logs]:find('kind=vip_claim',1,true)and logs[#logs]:find('http_ms=20.000',1,true))
clock=clock+40;first.complete({StatusCode=200,Body='{"ok":true}'})
assert(logs[#logs]:find('kind=daily_claim',1,true)and logs[#logs]:find('http_ms=77.000',1,true))
print=ordinary_print
print('ARCHIVE_HTTP_TIMING_PASS: exact-boundaries/one-attempt/no-extra-http/no-private-data/capability-preserved/apply-once/error-preserved')
