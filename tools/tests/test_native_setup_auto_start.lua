package.path="scripts/vscripts/?.lua;"..package.path
local clock,state,players,world,expected,auto,delay,assignments,thinkers,remaining,remaining_calls
DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP=2
DOTA_GAMERULES_STATE_HERO_SELECTION=3
DOTA_CONNECTION_STATE_CONNECTED=2
DOTA_TEAM_GOODGUYS=2;DOTA_TEAM_SPECTATOR=1;DOTA_MAX_TEAM_PLAYERS=24
IsServer=function()return true end
Time=function()return clock end
package.loaded["core/scheduler"]={cancel=function()end}
package.loaded["core/event_bus"]={}
package.loaded["core/test_access_policy"]={enforce=function(id)return players[id] and not players[id].denied end}
local function fixture()
    clock,state,players,expected,auto,delay,assignments,thinkers,remaining,remaining_calls=0,1,{},2,nil,nil,{},{},nil,{}
    world={SetContextThink=function(_,name,callback)thinkers[name]=callback end}
    GameRules={GetGameModeEntity=function()return world end,State_Get=function()return state end,
        GetCustomGamePlayerCount=function()return expected end,
        EnableCustomGameSetupAutoLaunch=function(_,value)auto=value end,
        SetCustomGameSetupAutoLaunchDelay=function(_,value)delay=value end,
        SetCustomGameSetupRemainingTime=function(_,value)
            assert(value==1 or value==-1);remaining=value;remaining_calls[#remaining_calls+1]=value
        end,
        FinishCustomGameSetup=function()error("never force or bypass Valve setup")end,
        GetGameTime=function()error("native setup clock must not depend on frozen GameTime")end}
    PlayerResource={IsValidPlayerID=function(_,id)return players[id]~=nil end,
        IsFakeClient=function(_,id)return players[id].fake or false end,
        GetTeam=function(_,id)return players[id].team or 5 end,
        GetCustomTeamAssignment=function(_,id)return players[id].team or 5 end,
        GetPlayer=function(_,id)return players[id].entity end,
        GetSteamAccountID=function(_,id)return players[id].account end,
        GetConnectionState=function(_,id)return players[id].connection end,
        SetCustomTeamAssignment=function(_,id,team)
            assert(team==2);players[id].team=team;assignments[#assignments+1]=id
        end}
    package.loaded["systems/multiplayer_player_service"]=nil
    package.loaded["systems/native_setup_auto_start"]=nil
    local service=require("systems/native_setup_auto_start")
    assert(service.init() and auto==false and delay==1 and remaining==-1)
    return service
end
local function player(id,connected)
    players[id]={entity=connected and {} or nil,account=885195478+id,connection=connected and 2 or 0}
end
local service=fixture()
player(0,true);clock=1000;service.tick()
assert(auto==false and #assignments==0,"native loading must finish before team setup")
state=2;service.tick()
assert(auto==false and service.snapshot().status=="waiting_lobby_roster","player0 cannot launch a two-person lobby")
player(7,false);clock=10000;service.tick()
assert(auto==false and service.snapshot().status=="waiting_connection","a late, slow second human is never timed out")
players[7].entity={};players[7].connection=2
service.tick();assert(auto==false and players[0].team==2 and players[7].team==2)
clock=clock+0.9;service.tick();assert(auto==false)
clock=clock+0.2;service.tick();assert(auto==true and remaining==1)
local armed_calls=#remaining_calls
for tick=1,30 do clock=clock+0.1;service.tick() end
assert(#remaining_calls==armed_calls,"stable think ticks must not restart the native countdown")
assert(#assignments==2,"non-contiguous real player slots share the co-op team")
-- A new arrival during Valve's countdown cancels auto-launch until the full
-- roster settles again; no fixed one-player shortcut or timeout is used.
expected=3;player(4,false);service.tick();assert(auto==false and remaining==-1)
local cancelled_calls=#remaining_calls
clock=clock+600;service.tick();assert(auto==false and players[4].team==nil and #remaining_calls==cancelled_calls)
players[4].entity={};players[4].connection=2;service.tick()
clock=clock+1.1;service.tick();assert(auto==true and remaining==1 and players[4].team==2)
local old_think=thinkers.SurvivalNativeSetupAutoStart
state=3;assert(service.tick()==nil)
local count=#assignments
players[9]={entity={},account=42,connection=2};assert(service.tick()==nil and #assignments==count)
world={SetContextThink=function(_,name,callback)thinkers[name]=callback end};state=2;players[9]=nil
assert(service.init());auto=false;assert(old_think()==nil and auto==false,"old worlds cannot launch a new match")

service=fixture();state=2;expected=1
player(0,true);player(5,true);players[5].fake=true
player(8,true);players[8].team=1
service.tick();clock=2;service.tick()
assert(auto==true and #assignments==1 and assignments[1]==0,"bots and spectators never become playing humans")
players[0].connection=3;service.tick();assert(auto==false and remaining==-1,"disconnect during countdown must hold setup")
clock=clock+1000;service.tick();assert(auto==false)
players[0].connection=2;players[0].entity={};service.tick();clock=clock+2;service.tick();assert(auto==true)
assert(service.init() and auto==true,"same-world repeated init cannot duplicate or reset the active controller")

-- The live Valve probe had no GetCustomGamePlayerCount API. Known slow human
-- slots still block the countdown; no fixed one-player shortcut is introduced.
service=fixture();state=2;GameRules.GetCustomGamePlayerCount=nil
player(0,true);player(7,false);service.tick();clock=1000;service.tick()
assert(auto==false and remaining==-1 and service.snapshot().status=="waiting_connection")
players[7].entity={};players[7].connection=2;service.tick();clock=clock+2;service.tick()
assert(auto==true and remaining==1)

service=fixture();GameRules.SetCustomGameSetupRemainingTime=nil
local before_missing=#remaining_calls
local ready,reason=service.init()
assert(not ready and reason=="native_remaining_time_api_missing" and auto==false
    and #remaining_calls==before_missing,"missing countdown API fails closed without arming half a roster")
print("NATIVE_SETUP_AUTO_START_PASS: actual multiplayer assignment; two-person/late non-contiguous roster; slow/reconnected players; single native countdown/cancellation; missing native-count/countdown API; bots/spectators; frozen clock and old-world guards")
