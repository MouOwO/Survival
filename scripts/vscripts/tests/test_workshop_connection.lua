package.path = "scripts/vscripts/?.lua;" .. package.path
local config = {enabled=true,base_url="https://pay.xiaofengnet.com/ws4",key_seed="test-public-seed"}
package.loaded["config/workshop_connection"] = config
local mode, dedicated, key = true, false, string.rep("a",64)
IsInToolsMode=function() return mode end
IsDedicatedServer=function() return dedicated end
GetDedicatedServerKeyV3=function(seed) assert(seed==config.key_seed) return key end
local connection=require("systems/workshop_connection")
local url,token,err=connection.resolve("http://127.0.0.1:8765","private-tools-token")
assert(url=="http://127.0.0.1:8765" and token=="private-tools-token" and not err)
mode=false
url,token,err=connection.resolve("http://127.0.0.1:8765","private-tools-token")
assert(url==config.base_url and token==key and not err,
    "a false generic server flag must not hide the actual Valve key result")
IsDedicatedServer=function() error("generic server flag must not be queried") end
url,token,err=connection.resolve("http://127.0.0.1:8765","")
assert(url==config.base_url and token==key and not err)
IsDedicatedServer=nil
url,token,err=connection.resolve("http://127.0.0.1:8765","")
assert(url==config.base_url and token==key and not err)
dedicated=true
url,token,err=connection.resolve("http://127.0.0.1:8765","")
assert(url==config.base_url and token==key and not err)
key="Invalid_NotOnDedicatedServer"
url,token,err=connection.resolve("http://127.0.0.1:8765","")
assert(not url and not token and err=="workshop_key_state_Invalid_NotOnDedicatedServer")
local native_key_function=GetDedicatedServerKeyV3
GetDedicatedServerKeyV3=nil
assert(select(3,connection.resolve("localhost",""))=="workshop_key_api_unavailable")
GetDedicatedServerKeyV3=function() error("must-never-publish-this-error") end
assert(select(3,connection.resolve("localhost",""))=="workshop_key_call_failed")
GetDedicatedServerKeyV3=native_key_function
key=""
assert(select(3,connection.resolve("localhost",""))=="workshop_key_empty")
key="Invalid_<untrusted>"
assert(select(3,connection.resolve("localhost",""))=="workshop_server_key_unavailable")
key=string.rep("b",64).."\n"
assert(select(3,connection.resolve("localhost",""))=="workshop_server_key_unavailable")
assert(connection.failure({error="workshop_server_pairing_required",pairing_fingerprint="0123456789abcdef"},"fallback")
 =="workshop_pairing_0123456789abcdef")
assert(connection.failure({error="workshop_server_pairing_required",pairing_fingerprint="<script>"},"fallback")
 =="workshop_server_pairing_required")
assert(connection.failure(nil,"fallback")=="fallback")
assert(connection.failure(nil,"http_status_0")=="workshop_backend_unreachable")
assert(connection.failure(nil,"http_status_403")=="workshop_backend_rejected")
mode=true
assert(connection.failure(nil,"http_status_403")=="http_status_403")
mode=false
key=string.rep("c",64)
package.loaded["systems/match_setup_service"]={get_session_id=function() return "workshop-session-123" end,
    is_mode_selected=function() return false end}
Convars={GetStr=function() return "" end}
local request,error_code
CreateHTTPRequestScriptVM=function(method,address)
    assert(method=="POST")
    request={url=address}
    function request:SetHTTPRequestHeaderValue(name,value) self[name]=value end
    function request:SetHTTPRequestRawPostBody(_,body) self.body=body end
    function request:SetHTTPRequestAbsoluteTimeoutMS() end
    function request:Send(callback)
        callback({StatusCode=403,Body='{"error":"workshop_server_pairing_required","pairing_fingerprint":"0123456789abcdef"}'})
    end
    return request
end
local provider=require("systems/player_profile_providers/http_fishing_provider")
provider.init()
provider.authenticate("885195478",function() error("Unpaired server must never authenticate") end,
    function(code) error_code=code end)
assert(request.url==config.base_url.."/v1/session/authenticate")
assert(request.Authorization=="Bearer "..key)
assert(error_code=="workshop_pairing_0123456789abcdef")
request=nil
key="Invalid_NotOnDedicatedServer"
provider.authenticate("885195478",function() error("Invalid key must never authenticate") end,
    function(code) error_code=code end)
assert(request==nil and error_code=="workshop_key_state_Invalid_NotOnDedicatedServer",
    "local/unofficial sentinel must never become an HTTP credential")
print("workshop connection checks passed")
