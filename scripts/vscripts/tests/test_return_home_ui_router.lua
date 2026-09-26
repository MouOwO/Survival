package.path = "scripts/vscripts/?.lua;" .. package.path
local listeners, sent, casts, summon_requests = {}, {}, {}, {}
local admitted, defeated = {[0]=true,[1]=true}, {}
local handles = {[0]={id=0},[1]={id=1}}
PlayerResource = {
    IsValidPlayerID=function(_,id) return handles[id] ~= nil end,
    GetPlayer=function(_,id) return handles[id] end,
    GetTeam=function() return 2 end,
}
GameRules = {GetGameTime=function() return 100 end}
CustomGameEventManager = {
    RegisterListener=function(_,name,handler) listeners[name]=handler end,
    Send_ServerToPlayer=function(_,player,name,payload)
        sent[#sent+1]={player=player,name=name,payload=payload}
    end,
}
package.loaded["systems/startup_loading_service"] = {
    is_player_ready=function(id) return admitted[id] == true end,
}
package.loaded["systems/multiplayer_player_service"] = {
    is_defeated=function(id) return defeated[id] == true end,
}
-- Reuse the production UI router's engine-free fixture boundaries. The real
-- router, event bus, player context and production request registration run.
for _,name in ipairs({"systems/building_system","ui/weapon_synthesis_snapshot_service",
    "ui/combat_stat_projection","config/asset_catalog","systems/hero_summon_projection",
    "systems/building_batch_upgrade_service","systems/gold_mine_batch_upgrade_service"}) do
    package.loaded[name]={}
end
local function forbidden() error("return-home UI must use only the regular no-target ability cast") end
EntIndexToHScript=forbidden
ExecuteOrderFromTable=forbidden
FindClearSpaceForUnit=forbidden
local function hero(index,owner)
    local unit={survival_player_id=owner}
    local ability={
        IsNull=function(self) return self.removed == true end,
        IsFullyCastable=function(self) return not self.cooling_down end,
        GetLevel=function() return 1 end,
        IsActivated=function() return true end,
        IsHidden=function() return false end,
        OnSpellStart=forbidden,EndCooldown=forbidden,StartCooldown=forbidden,
    }
    unit.ability=ability
    unit.entindex=function() return index end
    unit.IsNull=function(self) return self.removed == true end
    unit.IsAlive=function(self) return not self.dead end
    unit.GetPlayerOwnerID=function() return owner end
    unit.FindAbilityByName=function(self,name)
        assert(name=="ability_survival_return_home")
        if not self.missing_ability then return self.ability end
    end
    unit.CastAbilityNoTarget=function(self,skill,player_id)
        assert(skill==self.ability)
        casts[#casts+1]={unit=self,ability=skill,player_id=player_id}
    end
    unit.SetAbsOrigin,unit.SetOrigin,unit.Stop=forbidden,forbidden,forbidden
    return unit
end
local heroes = {[0]=hero(500,0),[1]=hero(501,1)}
local summoned = {
    [0]={ok=true,unit=heroes[0]},[1]={ok=true,unit=heroes[1]},
}
local bus=require("core/event_bus")
local events=require("core/events")
bus.reset()
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function(payload)
    assert(payload.player_id==0 or payload.player_id==1)
    for key in pairs(payload) do assert(key=="player_id","client fields leaked into authoritative query") end
    summon_requests[#summon_requests+1]=payload
    return summoned[payload.player_id]
end)
require("ui/ui_request_router").init()
local send=assert(listeners.ui_return_home_request)
local function request(player_id,client_fields)
    local payload={}
    for key,value in pairs(client_fields or {}) do payload[key]=value end
    payload.PlayerID=player_id -- engine-injected identity, never an application field
    send(nil,payload)
end
local function result_for(player_id,success)
    local packet=sent[#sent]
    assert(packet and packet.name=="ui_return_home_result")
    assert(packet.player==handles[player_id] and packet.payload.success==success)
    return packet.payload
end
-- The actual client sends an empty object; after the engine supplies PlayerID,
-- only the official hero obtained on the server may receive an ability order.
request(0)
assert(#casts==1 and casts[1].unit==heroes[0] and casts[1].player_id==0)
assert(#summon_requests==1 and summon_requests[1].player_id==0)
result_for(0,1)
request(0,{
    player_id=1,unit_entindex=501,entindex=501,source_entindex=501,
    hero_entindex=501,ability_name="ability_fake_return",ability_entindex=999,
    position={x=99999,y=-99999,z=-2048},target_x=99999,target_y=-99999,
    target_z=-2048,x=99999,y=-99999,z=-2048,ignore_cooldown=true,free=true,
})
assert(#casts==2 and casts[2].unit==heroes[0] and casts[2].player_id==0)
assert(summon_requests[2].player_id==0)
result_for(0,1)
request(1,{player_id=0,unit_entindex=500})
assert(#casts==3 and casts[3].unit==heroes[1] and casts[3].player_id==1)
result_for(1,1)
-- Invalid/admission/defeat requests stop before any authoritative hero query.
local query_count,packet_count=#summon_requests,#sent
admitted[0]=false; request(0); admitted[0]=true
defeated[0]=true; request(0); defeated[0]=nil
request(-1); request(99)
send(nil,{player_id=0,unit_entindex=500})
send(nil,{})
send(nil,nil)
assert(#casts==3 and #summon_requests==query_count and #sent==packet_count)
local function rejects(player_id,mutate,restore)
    local before=#casts
    mutate()
    request(player_id,{player_id=1-player_id,unit_entindex=501})
    assert(#casts==before,"unavailable hero or ability received a cast")
    assert(result_for(player_id,0).error~="")
    restore()
end
-- Missing, failed authoritative lookup, removed/dead hero and unavailable
-- regular ability all reject. Fabricated cooldown bypass fields do nothing.
rejects(0,function() summoned[0]=nil end,function() summoned[0]={ok=true,unit=heroes[0]} end)
rejects(0,function() summoned[0].ok=false end,function() summoned[0].ok=true end)
rejects(0,function() heroes[0].removed=true end,function() heroes[0].removed=nil end)
rejects(0,function() heroes[0].dead=true end,function() heroes[0].dead=nil end)
rejects(0,function() heroes[0].missing_ability=true end,function() heroes[0].missing_ability=nil end)
rejects(0,function() heroes[0].ability.removed=true end,function() heroes[0].ability.removed=nil end)
rejects(0,function() heroes[0].ability.cooling_down=true end,function() heroes[0].ability.cooling_down=nil end)
request(0)
assert(#casts==4 and casts[4].unit==heroes[0] and casts[4].ability==heroes[0].ability)
result_for(0,1)
print("RETURN_HOME_UI_ROUTER_PASS: trusted PlayerID, authoritative hero lookup, forged target ignored, startup/defeat/death/cooldown gates, regular cast only")
