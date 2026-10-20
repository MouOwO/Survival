package.path='scripts/vscripts/?.lua;'..package.path
local decoder=require('core/json_decoder')
package.loaded['config/generated/fishing_system_rules']={rows={{enabled=true,api_base_url='https://example.invalid'}}}
local selected=false
package.loaded['systems/match_setup_service']={is_mode_selected=function()return selected end,
    get_session_id=function()return 'authenticated_session' end,get_mode=function()return 'standard' end}
Convars={GetStr=function(_,name)return name=='survival_fishing_api_token' and 'test-token' or '' end}
local requests={}
CreateHTTPRequestScriptVM=function(method,url)
    local request={method=method,url=url}
    function request:SetHTTPRequestHeaderValue(name,value)self[name]=value end
    function request:SetHTTPRequestRawPostBody(_,body)self.body=decoder.decode(body)end
    function request:SetHTTPRequestAbsoluteTimeoutMS(value)self.timeout=value end
    function request:Send(done)requests[#requests+1]=self;done({StatusCode=200,Body='{"ok":true}'})end
    return request
end
local provider=require('systems/player_profile_providers/http_fishing_provider')
provider.init()
local result,error
provider.lottery_catalog({md5='local'},function(value)result=value end,function(value)error=value end)
assert(result.ok and not error and #requests==1)
assert(requests[1].url=='https://example.invalid/v1/lottery/catalog' and requests[1].Authorization=='Bearer test-token')
assert(requests[1].body.md5=='local' and requests[1].body.match_session_id=='authenticated_session')
provider.lottery_snapshot({},function()assert(false)end,function(value)error=value end)
assert(error=='mode_not_selected' and #requests==1,'only public metadata bypasses the mode gate')
selected=true;error=nil
provider.lottery_snapshot({},function(value)result=value end,function(value)error=value end)
assert(result.ok and not error and #requests==2)
print('LOTTERY_CATALOG_PROVIDER_PASS: early-public-metadata/Bearer/session/private-mode-gate')
