-- Exercise the real profile service, rather than only its memory provider.
package.path="scripts/vscripts/?.lua;"..package.path
local mode,session=nil,"session_native_profile_first"
local counters={http=0,files=0}
local values={sv_cheats="0"}
Convars={GetStr=function(_,key) return values[key] or "" end,
    RegisterConvar=function(_,key,value) if values[key]==nil then values[key]=value end end}
IsServer=function() return true end
IsInToolsMode=function() return false end
GetMapName=function() return "template_map" end
DisconnectClient=function() error("unexpected tester kick") end
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    GetSteamAccountID=function(_,id) return ({[0]=885195478,[1]=463897428})[id] or 0 end,
    IsFakeClient=function() return false end}
CreateHTTPRequestScriptVM=function() counters.http=counters.http+1;error("cloud reached") end
CreateHTTPRequest=CreateHTTPRequestScriptVM
package.loaded["core/logger"]={info=function() end,warn=function() end}
package.loaded["systems/match_setup_service"]={get_session_id=function() return session end,
    get_mode=function() return mode end,get_profile_mode=function() return mode end,
    is_mode_selected=function() return mode~=nil end}
require("config/session_multiplayer_test").enabled=true
require("config/player_web_auth").enabled=false
require("config/release_profile").channel="production"
local memory=require("systems/session_multiplayer_test")
local profiles=require("systems/player_profile_service")
assert(memory.configure())
local options=assert(memory.profile_options())
local original_open=io.open
io.open=function() counters.files=counters.files+1;error("file reached") end
profiles.init(options)
local provider=assert(profiles.get_provider())
for id=0,1 do
    assert(provider.resolve_account_id(id))
    assert(profiles.authenticate_player(id,"native_entry").ok)
    assert(profiles.load_player(id).error=="mode_not_selected")
end
mode="standard"
assert(profiles.load_player(0).ok and profiles.load_player(1).ok)
assert(profiles.get_profile(0).match_session_id==session)
assert(profiles.get_profile(0).match_session_id~="injected_fixture")
assert(profiles.update_save_section(0,"content_inventory",{test_probe=17},"native_test").ok)
assert(profiles.refresh_player(0).ok and profiles.refresh_player(1).ok)
assert(profiles.get_profile(0).save.content_inventory.test_probe==17)
assert(profiles.get_profile(1).save.content_inventory.test_probe==nil)
local old=profiles.get_profile(0)
session,mode="session_native_profile_second",nil
assert(profiles.get_profile(0)==nil and not profiles.is_authenticated_for_account(0,"885195478"))
assert(provider.resolve_account_id(0)=="885195478")
assert(profiles.authenticate_player(0,"next_match").ok)
mode="pure"
assert(profiles.load_player(0).ok)
assert(profiles.get_profile(0).save.content_inventory.test_probe==nil)
assert(profiles.apply_snapshot(0,old).error=="match_profile_mismatch")
assert(not pcall(profiles.init,{provider={},session_multiplayer_test=true}))
values.sv_cheats="1"
assert(not pcall(profiles.init,options))
assert(counters.http==0 and counters.files==0)
io.open=original_open
print("SESSION_MULTIPLAYER_PROFILES_PASS: real profile integration, two users, session binding, no cloud/files, forged provider/cheats denied")
