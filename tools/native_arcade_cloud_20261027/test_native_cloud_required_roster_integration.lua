-- Actual roster + automatic setup modules; no Dota, HTTP, orders or file writes.
local file=assert(io.open("tools/native_arcade_cloud_20261027/test_native_cloud_roster.lua","rb"))
local source=file:read("*a");file:close()
local ending=assert(source:find("local function group(",1,true))
local scenario=[[
local e,s,p=fixture()
s.option="";s.profile.native_cloud_roster_required=true
s.valid[5],s.players[5]=false,nil
local current,enabled,remaining,armed,think=0,nil,nil,0,nil
e.Time=function()return current end
e.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP=2;e.DOTA_MAX_TEAM_PLAYERS=24
e.GameRules.State_Get=function()return 2 end
e.GameRules.EnableCustomGameSetupAutoLaunch=function(_,value)enabled=value end
e.GameRules.SetCustomGameSetupRemainingTime=function(_,value)remaining=value;if value==1 then armed=armed+1 end end
e.GameRules.SetCustomGameSetupAutoLaunchDelay=function()end
e.PlayerResource.GetPlayerCount=function()return 1 end
assert(e.GameRules.GetCustomGamePlayerCount~=nil)
e.GameRules.GetCustomGamePlayerCount=nil -- actual unavailable API cannot help
s.mode.SetContextThink=function(_,name,callback)think=callback end
local original_require=e.require
e.require=function(name)
    if name=="systems/native_cloud_roster" then return p end
    if name=="config/generated/multiplayer_rules" then return {by_id={default_multiplayer={max_players=4}}} end
    if name=="systems/multiplayer_player_service" then
        return {assign_to_survival_team=function()return true end,mark_connected=function()end}
    end
    return original_require(name)
end
local automatic=load("scripts/vscripts/systems/native_setup_auto_start.lua",e)
assert(automatic.init())
for index=1,120 do current=current+0.1;think() end
local complete,reason=p.complete_roster()
assert(not complete and reason=="native_roster_option_required")
assert(enabled==false and remaining==-1 and armed==0)
assert(automatic.snapshot().status=="waiting_expected_roster")
print("PASS actual required roster + automatic setup: lost option and host-only resource remain blocked for 12 seconds")
]]
assert(loadstring(source:sub(1,ending-1)..scenario,"required_native_roster_integration"))()
