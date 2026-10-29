-- Execute the real bootstrap listener with the real bus, without activating Dota.
package.path="scripts/vscripts/?.lua;"..package.path
local event_bus, events = require("core/event_bus"), require("core/events")
local file=assert(io.open("scripts/vscripts/addon_game_mode.lua","rb"))
local text=file:read("*a");file:close()
local start=assert(text:find("    event_bus.subscribe(events.PLAYER_DEFEATED, function()",1,true))
local finish=assert(text:find("    sound_service.init()",start,true))
local listener=assert(loadstring(text:sub(start,finish-1)))
local all_defeated,victory,ended,timing=false,false,0,0
local multiplayer_player_service={all_participants_defeated=function() return all_defeated end}
local GameRules={SetGameWinner=function(_,team) assert(team==3);ended=ended+1 end}
package.loaded["systems/online_time_service"]={finish=function(reason)
    assert(reason=="all_players_defeated");timing=timing+1
end}
setfenv(listener,setmetatable({event_bus=event_bus,events=events,
    multiplayer_player_service=multiplayer_player_service,GameRules=GameRules,DOTA_TEAM_BADGUYS=3}, {__index=_G}))
event_bus.reset()
event_bus.handle_request(events.WAVE_STATE_GET_REQUEST,function() return {victory_settled=victory} end)
listener()
event_bus.emit(events.PLAYER_DEFEATED,{player_id=0})
assert(ended==0 and timing==0,"a surviving teammate preserves the match")
all_defeated=true
event_bus.emit(events.PLAYER_DEFEATED,{player_id=1})
assert(ended==1 and timing==1,"ordinary all-player defeat still loses normally")
victory=true
for _=1,3 do event_bus.emit(events.PLAYER_DEFEATED,{player_id=1}) end
assert(ended==1 and timing==1,"post-win disconnect defeat cannot bypass the reward save barrier")
print("ARCHIVE_POST_WIN_DEFEAT_PASS: real bootstrap listener preserves saved victory; ordinary defeat remains effective")
