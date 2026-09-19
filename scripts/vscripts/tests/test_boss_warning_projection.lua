package.path = "scripts/vscripts/?.lua;" .. package.path
local handlers, sent = {}, {}
package.loaded["core/event_bus"] = {
    subscribe=function(name,fn) handlers[name]=fn; return name end,
    unsubscribe=function(name) handlers[name]=nil end,
    emit=function() end, register_request=function() end,
    register=function() end, handle_request=function() end,
}
PlayerResource={GetPlayer=function(_,id) if id==0 or id==1 then return id end end}
CustomGameEventManager={
    Send_ServerToPlayer=function(_,p,event,payload) sent[#sent+1]={player=p,event=event,payload=payload} end,
    Send_ServerToAllClients=function(_,event,payload) sent[#sent+1]={event=event,payload=payload} end,
}
local events=require("core/events")
local projection=require("ui/ui_projection")
projection.init()
local fire=assert(handlers[events.MONSTER_SPAWNED])
fire({monster_source="wave",is_boss=false,wave_number=4,player_id=0})
fire({monster_source="building_challenge",is_boss=true,player_id=0})
fire({monster_source="wave",is_boss=true,wave_number=0,player_id=0})
fire({monster_source="wave",is_boss=true,boss_warning=false,wave_number=7,player_id=0})
assert(#sent==0,"ordinary spawns and invalid waves do not warn")
fire({monster_source="wave",is_boss=true,wave_number=7,player_id=0})
fire({monster_source="wave",is_boss=true,wave_number=7,player_id=0})
assert(#sent==1 and sent[1].player==0 and sent[1].payload.wave_number==7)
fire({monster_source="wave",is_boss=true,wave_number=7,player_id=1})
assert(#sent==2 and sent[2].player==1,"player channels are independent")
fire({monster_source="wave",is_boss=true,wave_number=11})
assert(#sent==3 and sent[3].player==nil)
fire({monster_source="wave",is_boss=true,wave_number=12,player_id=99})
assert(#sent==3,"do not broadcast a disconnected player's warning")
assert(sent[1].payload.notice_id~=sent[2].payload.notice_id)
require("ui/boss_warning_ui_service").init()
handlers[events.MONSTER_SPAWNED]({monster_source="wave",is_boss=true,wave_number=7,player_id=0})
assert(#sent==3,"reinitializing the presentation service does not replay a warning")
print("BOSS_PROJECTION_PASS: actual boss spawn only, actual wave, deduplication, player targeting")
