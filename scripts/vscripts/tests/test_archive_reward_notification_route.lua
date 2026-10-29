-- Execute the real routing callback without initializing the game request bus.
local handle=assert(io.open("scripts/vscripts/ui/ui_request_router.lua","rb"))
local source=handle:read("*a");handle:close()
local start=assert(source:find("local function on_notification(payload)",1,true))
local stop=assert(source:find("\nlocal function register_rogue_reward_requests",start,true))
local chunk=assert(loadstring(source:sub(start,stop-1).."\nreturn on_notification"))
local sent={}
local environment={tonumber=tonumber,resource_failure_messages={gold_not_enough="金币不足"},
    send_to_player=function(event,id,packet) sent[#sent+1]={event=event,id=id,packet=packet} end,
    CustomGameEventManager={Send_ServerToAllClients=function(_,event,packet)
        sent[#sent+1]={event=event,id="all",packet=packet}
    end},
    PlayerResource={GetPlayerName=function() return "测试玩家" end,GetSelectedHeroName=function() return "npc_dota_hero_axe" end},
}
setfenv(chunk,environment)
local route=chunk()
local message='获得 <font color="#b680ee">紫色材料</font> ×1'
route({player_id=1,kind="archive_reward",rich_text=true,level="success",message=message})
assert(#sent==1 and sent[1].id==1 and sent[1].packet.rich_text==true and sent[1].packet.message==message)
route({player_id=0,kind="message",rich_text=true,message=message})
assert(sent[2].packet.rich_text==false)
route({player_id=0,kind="archive_reward",rich_text="true",message=message})
assert(sent[3].packet.rich_text==false)
route({kind="archive_reward",rich_text=true,message=message})
assert(#sent==3,"unresolved recipient cannot leak private rewards")
route({player_id=0,kind="research_success",audience="all",subject="研究",message="成功"})
assert(sent[4].id==0 and sent[4].packet.audience=="player" and sent[4].packet.rich_text==false)
route({player_id=0,message="gold_not_enough",level="error"})
assert(sent[5].packet.message=="金币不足" and not sent[5].packet.rich_text)
print("ARCHIVE_REWARD_ROUTE_PASS: recipient privacy, trusted rich marker, ordinary notification and research/resource behavior")
