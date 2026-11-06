-- Actual isolated draft provider; HTTP calls captured and never sent.
package.path='scripts/vscripts/?.lua;'..package.path
local draft=arg[1] or 'scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua'
local json=require('core/json_encoder')
local decode=require('core/json_decoder')
local session,mode='synthetic-session-1',nil
local requests,errors,resolves={},{},0
local defer_resolve,pending_resolve=false,nil
local metadata,error_status,error_bytes
package.loaded['config/generated/fishing_system_rules']={rows={{enabled=true,api_base_url='https://example.invalid'}}}
package.loaded['debug/mode_unlock_test']={is_enabled=function()return false end}
package.loaded['systems/workshop_connection']={failure=function(body,fallback)return body and body.error or fallback end}
package.loaded['systems/player_web_auth']={enabled=function()return true end,
 resolve=function(_,_,success)resolves=resolves+1;if defer_resolve then pending_resolve=success
 else success('https://example.invalid','synthetic-token')end end,
 authorized_account=function()return '100','https://example.invalid','synthetic-token'end}
package.loaded['systems/match_setup_service']={is_mode_selected=function()return mode~=nil end,
 get_session_id=function()return session end,get_mode=function()return mode end,
 get_profile_mode=function()return mode=='rich'and'standard'or mode end}
Convars={GetStr=function()return '1'end}
CreateHTTPRequestScriptVM=function(_,url)
 local r={url=url};requests[#requests+1]=r
 return{SetHTTPRequestHeaderValue=function()end,SetHTTPRequestAbsoluteTimeoutMS=function()end,
 SetHTTPRequestRawPostBody=function(_,_,raw)r.body=decode.decode(raw)end,
 Send=function(_,done)r.done=done end}
end
local provider=assert(loadfile(draft))();provider.init()
local function catalog(account)
 provider.lottery_catalog(account and {account_id=account} or {},function(_,value)metadata=value end,
 function(error,status,bytes)errors[#errors+1]=error;error_status,error_bytes=status,bytes end)
end
catalog('100');assert(#requests==0 and errors[#errors]=='mode_not_selected')
mode='standard';catalog('100');assert(resolves==0,'pre-login catalog must not start auth resolution');catalog(nil)
assert(#requests==0 and errors[#errors]=='match_profile_not_ready')
provider.fetch_snapshot('100',function()end,function()error('login rejected')end)
assert(#requests==1)
requests[1].done({StatusCode=200,Body=json.encode({account_id='100',match_session_id=session,mode='standard'})})
catalog('100');assert(#requests==2 and requests[2].body.account_id=='100')
local body='{"ok":true,"http_status":403,"response_bytes":99999999}'
requests[2].done({StatusCode=200,Body=body})
assert(metadata.http_status==200 and metadata.response_bytes==#body,'metadata must come from HTTP, not decoded fields')
catalog('101');assert(#requests==2 and errors[#errors]=='match_profile_not_ready')
session='synthetic-session-2';catalog('100')
assert(#requests==2 and errors[#errors]=='match_profile_not_ready')
provider.init();catalog('100');assert(#requests==2)
for _,selected in ipairs({'pure','rich'})do
 mode=selected;session='synthetic-mode-'..selected
 provider.fetch_snapshot('100',function()end,function()error('mode login rejected')end)
 local request=requests[#requests]
 assert(request.body.mode==selected)
 request.done({StatusCode=200,Body=json.encode({account_id='100',match_session_id=session,
  mode=selected=='rich'and'standard'or selected,game_mode=selected})})
 local before=#requests;catalog('100');assert(#requests==before+1,'mode-specific catalog readiness')
 if selected=='pure'then
  local denied='{"error":"match_session_missing"}'
  requests[#requests].done({StatusCode=409,Body=denied})
  assert(errors[#errors]=='match_session_missing'and error_status==409 and error_bytes==#denied)
 end
end
defer_resolve=true;catalog('100');assert(pending_resolve)
local before=#requests;session='synthetic-after-async-auth';pending_resolve('https://example.invalid','synthetic-token')
assert(#requests==before and errors[#errors]=='match_session_changed','async auth cannot create old-world HTTP')
print('CATALOG_ADMISSION_PROVIDER_PASS pre_mode_http=0 pre_login_http=0 stale_session_http=0 other_account_http=0 pure_rich=pass async_auth_world=pass authenticated_transport=retained')
