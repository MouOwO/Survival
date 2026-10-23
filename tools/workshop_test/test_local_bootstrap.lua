-- Exercise the exact installed apply script with safe engine/profile fixtures.
package.path="scripts/vscripts/?.lua;"..package.path
assert(arg[1],"Pass the installed local apply.lua path")
local tools, expected, token=true,1,string.rep("a",64)
local loaded, writes, auth_calls, ticks=0,0,0,0
local convars={survival_fishing_api_token=""}
IsServer=function() return true end
IsInToolsMode=function() return tools end
GetMapName=function() return "template_map" end
DOTA_MAX_TEAM_PLAYERS=4
Convars={GetStr=function(_,name) return convars[name] end,
    SetStr=function(_,name,value) convars[name]=value;writes=writes+1 end}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 end,
    IsFakeClient=function() return false end,GetTeam=function() return 2 end,
    GetPlayer=function() return {} end,GetSteamAccountID=function() return 885195478 end}
local marker={kind="WS4-LOCAL-1",proxy_port=18766}
package.loaded["config/ws4_local_launcher"]=marker
local pending=false
package.loaded["systems/player_profile_service"]={
    is_authenticated_for_account=function() return false end,
    is_loaded_for_account=function() return false end,
    is_authenticating=function() return pending end,
    authenticate_player=function() auth_calls=auth_calls+1;pending=true end}
package.loaded["systems/match_setup_service"]={is_mode_selected=function() return false end}
package.loaded["systems/startup_loading_service"]={
    snapshot=function() return {phase="waiting",admission_complete=false,profiles_ready=false} end,
    is_party_waiting=function() return false end,tick=function() ticks=ticks+1 end}
package.loaded["ws4_local_launcher/status"]=dofile("tools/workshop_test/local_status.lua")
LoadKeyValues=function(path)
    assert(path=="scripts/vscripts/ws4_local_launcher/session.kv")
    loaded=loaded+1;return {token=token,expected_players=tostring(expected)}
end
local last
local real_print=print
print=function(value) last=value end
local function apply() last=nil;dofile(arg[1]);assert(last) end
tools=false;apply()
assert(last:find("waiting_for_map",1,true) and loaded==0 and writes==0)
tools=true;marker.kind="wrong";apply()
assert(last:find("waiting_for_map",1,true) and loaded==0 and writes==0)
marker.kind="WS4-LOCAL-1";token="bad";apply()
assert(last:find("local_credential_missing",1,true) and writes==0 and auth_calls==0)
token=string.rep("a",64);expected=2;apply()
assert(last:find("waiting_for_players",1,true) and writes==0 and auth_calls==0)
expected=1;apply()
assert(last:find('"credential_applied":true',1,true) and auth_calls==1 and ticks==1)
assert(not last:find(token,1,true) and not last:find("885195478",1,true))
assert(convars.survival_archive_http_enabled=="1")
assert(last:find('"admission_complete":false',1,true) and last:find('"profiles_ready":false',1,true),
    "credential injection must not manufacture authentication, profile load or admission")
apply();assert(auth_calls==1,"an in-flight normal authentication must not be superseded")
print=real_print
print("WS4_LOCAL_BOOTSTRAP_PASS: Tools guard, marker, credential, party wait, normal authentication and closed admission")
