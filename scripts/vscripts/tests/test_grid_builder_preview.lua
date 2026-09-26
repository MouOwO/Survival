package.path="scripts/vscripts/?.lua;"..package.path
local listeners,sent,queries={},{},{}
local denied=false
local bus=require("core/event_bus")
local events=require("core/events")
bus.reset()
package.loaded["config/buildings_config"]={house={id="house",display_name="House",footprint={x=2,y=2},levels={}}}
package.loaded["config/generated/building_definitions"]={rows={{building_id="house",builder_ability="ability_build_house"}}}
package.loaded["config/generated/arrow_tower_base"]={rows={}}
package.loaded["config/grid_placement_config"]={cell_size=64,footprint_subdivision=1}
package.loaded["systems/player_context_service"]={is_defeated=function() return false end}
Vector=function(x,y,z) return {x=x,y=y,z=z} end
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    GetPlayer=function(_,id) return id end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_,id,name,payload) sent[#sent+1]={id=id,name=name,payload=payload} end}
local function builder(index,team)
    return {entindex=function() return index end,IsNull=function() return false end,
        GetTeamNumber=function() return team end,GetUnitName=function() return "builder" end}
end
local own,other=builder(10,2),builder(11,2)
local function ability(unit,index)
    return {entindex=function() return index end,IsNull=function() return false end,
        GetCaster=function() return unit end,GetAbilityName=function() return "ability_build_house" end,
        GetLevel=function() return 1 end,IsActivated=function() return true end}
end
local own_ability,other_ability=ability(own,20),ability(other,21)
own.FindAbilityByName=function() return own_ability end
other.FindAbilityByName=function() return other_ability end
local entities={[10]=own,[11]=other,[20]=own_ability,[21]=other_ability}
EntIndexToHScript=function(index) return entities[index] end
CreateUnitByName=function() return nil end
bus.handle_request(events.BUILDER_GET_REQUEST,function(p)
    return {ok=true,builder=p.player_id==0 and own or other}
end)
bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function(p)
    queries[#queries+1]=p
    return {ok=not denied,error=denied and "unit_blocked" or nil,
        world_position=p.position,cells={{x=0,y=0,ok=not denied}}}
end)
bus.handle_request(events.BUILD_CAN_PLACE_REQUEST,function(p)
    assert(p.caster==(p.player_id==0 and own or other))
    return {ok=true}
end)
require("ui/grid_placement_router").init()
local validate=assert(listeners.ui_grid_placement_validate)
local seq=0
local function preview(extra)
    seq=seq+1
    local p={PlayerID=0,player_id=1,session_id=1,request_id=seq,
        ability_name="ability_build_house",entindex=10,ability_entindex=20,
        x=0,y=0,z=0,ignore_entindex=11,ignore_entindices={10,11,999}}
    for k,v in pairs(extra or {}) do p[k]=v end
    validate(nil,p)
end
preview()
assert(#queries==1 and queries[1].ignore_entindex==10 and queries[1].ignore_entindices==nil)
assert(sent[#sent].id==0 and sent[#sent].payload.success==1)
preview({entindex=11,ability_entindex=21})
assert(#queries==1 and sent[#sent].payload.success==0,"foreign builder cannot bypass occupancy")
preview({entindex=10,ability_entindex=21})
assert(#queries==1 and sent[#sent].payload.success==0,"ability caster must match")
denied=true; preview()
assert(#queries==2 and sent[#sent].payload.success==0,"other units still block preview")
assert(sent[#sent].payload.error=="unit_blocked")
local count=#sent
validate(nil,{player_id=0,session_id=2,request_id=1})
assert(#sent==count and #queries==2,"lowercase client owner is not authentication")
preview({PlayerID=1,entindex=11,ability_entindex=21})
assert(#queries==3 and queries[3].ignore_entindex==11)
print("GRID_BUILDER_PREVIEW_PASS: ignore only authenticated own builder, preserve other blockers and sender isolation")
