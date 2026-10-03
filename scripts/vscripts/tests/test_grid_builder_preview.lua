package.path="scripts/vscripts/?.lua;"..package.path
local listeners,sent,queries={},{},{}
local denied=false
local clock=0
GameRules={GetGameTime=function() return clock end}
local bus=require("core/event_bus")
local events=require("core/events")
bus.reset()
package.loaded["config/buildings_config"]={house={id="house",display_name="House",footprint={x=2,y=2},levels={}}}
package.loaded["config/generated/building_definitions"]={rows={{building_id="house",builder_ability="ability_build_house"}}}
package.loaded["config/generated/arrow_tower_base"]={rows={}}
package.loaded["config/grid_placement_config"]={cell_size=64,footprint_subdivision=1,
    build_ground_height=384,build_bounds={min_x=-4096,max_x=2048,min_y=1024,max_y=7168}}
package.loaded["systems/player_context_service"]={is_defeated=function() return false end}
local area_queries={}
package.loaded["systems/grid_placement_system"]={preview_area=function(p)
    area_queries[#area_queries+1]=p
    return "0,0,384,1,384,384,384,384"
end}
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
CreateUnitByName=function() error("validation must never create a ghost model entity") end
bus.handle_request(events.BUILDER_GET_REQUEST,function(p)
    return {ok=true,builder=p.player_id==0 and own or other}
end)
bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function(p)
    queries[#queries+1]=p
    return {ok=not denied,error=denied and "unit_blocked" or nil,
        world_position=p.position,cells={{x=0,y=0,ok=not denied}}}
end)
local reuse_business_grid=false
local business_denied=false
bus.handle_request(events.BUILD_CAN_PLACE_REQUEST,function(p)
    assert(p.caster==(p.player_id==0 and own or other))
    if business_denied then
        return {ok=false,error="insufficient_gold",grid={ok=true,world_position=p.position,
            cells={{x=32,y=32,z=384,ok=true},{x=96,y=32,z=384,ok=false}}}}
    end
    if reuse_business_grid then
        return {ok=true,grid={ok=true,world_position=p.position,cells={{x=0,y=0,ok=true,
            corners={{x=0,y=0,z=0}},reason="",grid_x=0,grid_y=0}}}}
    end
    return {ok=true}
end)
require("ui/grid_placement_router").init()
listeners.ui_grid_placement_profiles_request(nil,{PlayerID=0})
assert(sent[#sent].payload.static_grid.height==384 and sent[#sent].payload.static_grid.bounds.min_x==-4096,
    "send fixed white grid geometry with initial profiles")
assert(#area_queries==0 and #queries==0,"preloading white geometry does not scan terrain")
local validate=assert(listeners.ui_grid_placement_validate)
listeners.ui_grid_placement_pause_area(nil,{PlayerID=0,request_id=0})
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
assert(#area_queries==1 and area_queries[1].ignore_entindex==10)
assert(sent[#sent].payload.area=="0,0,384,1,384,384,384,384")
preview({entindex=11,ability_entindex=21})
assert(#queries==1 and sent[#sent].payload.success==0,"foreign builder cannot bypass occupancy")
assert(#area_queries==1 and sent[#sent].payload.area=="","foreign builder cannot query overlay")
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
local area_count=#area_queries
clock=0.1; preview()
assert(#area_queries==area_count,"reuse overview while exact footprint is revalidated")
clock=0.31; preview()
assert(#area_queries==area_count+1,"refresh dynamic blockers after cache expires")
preview({x=500})
assert(#area_queries==area_count+2,"large cursor jump refreshes overview immediately")
local scheduler=require("core/scheduler")
local batches=0
package.loaded["systems/grid_placement_system"].preview_area=function(p)
    assert(p.yield_after==128 and p.time_budget==0.002 and p.terrain_cache)
    batches=batches+1; coroutine.yield("near-cursor-ready")
    batches=batches+1; coroutine.yield("middle-ready")
    batches=batches+1; return "async-complete"
end
clock=2; denied=false; preview({x=1000})
assert(batches==1 and sent[#sent].name=="ui_grid_placement_validation"
    and sent[#sent].payload.success==1,"exact footprint reply does not wait for area scan")
assert(sent[#sent].payload.area=="0,0,384,1,384,384,384,384" and sent[#sent].payload.area_complete==1,
    "keep completed overview while replacement scans in background")
local sent_before_partial=#sent
clock=2.06; scheduler.think(); assert(batches==2)
assert(#sent==sent_before_partial,"do not transmit replacement wave when a completed overview exists")
clock=2.12; scheduler.think()
assert(batches==3 and sent[#sent].name=="ui_grid_placement_area"
    and sent[#sent].payload.area=="async-complete")
clock=3; preview({x=1500}); assert(batches==4)
listeners.ui_grid_placement_preview_end(nil,{PlayerID=0,session_id=1})
clock=4; scheduler.think()
assert(batches==4,"cancel stops background scan without late results")
local queries_before_reuse=#queries
reuse_business_grid=true
preview({session_id=2,x=1700})
assert(#queries==queries_before_reuse,"reuse business service grid validation, never scan footprint twice")
assert(sent[#sent].payload.cells[1].ok==1 and sent[#sent].payload.cells[1].corners==nil,
    "exact preview reply sends compact centers without unused ground-corner payload")
assert(sent[#sent].payload.area_complete==0 and sent[#sent].payload.area=="near-cursor-ready",
    "cold scan carries incomplete marker so client can prepare it invisibly")
clock=4.06; scheduler.think()
assert(sent[#sent].name=="ui_grid_placement_area" and sent[#sent].payload.complete==0,
    "cold progress is available only for hidden preparation")
local before_pause=batches
listeners.ui_grid_placement_pause_area(nil,{PlayerID=0,session_id=1,request_id=seq})
clock=4.12; scheduler.think()
assert(batches==before_pause+1,"stale session cannot pause current scan")
clock=5; preview({session_id=2,x=2000})
before_pause=batches
listeners.ui_grid_placement_pause_area(nil,{PlayerID=0,session_id=2,request_id=seq})
clock=5.1; scheduler.think()
assert(batches==before_pause,"fast motion cancels outstanding scan immediately")
preview({session_id=2,x=2500})
assert(batches==before_pause+1,"settled validation restarts at latest location")
print("GRID_BUILDER_PREVIEW_PASS: ignore only authenticated own builder, preserve other blockers and sender isolation")

business_denied=true
preview({session_id=2,x=2800})
assert(sent[#sent].payload.success==0 and sent[#sent].payload.cells[1].ok==1
    and sent[#sent].payload.cells[2].ok==0,"business denial preserves each cell's geometry color")

local atlas_steps=0
package.loaded["systems/grid_placement_system"].static_preview=function(p)
    assert(p.yield_after==128 and p.time_budget==0.002)
    atlas_steps=atlas_steps+1;coroutine.yield()
    atlas_steps=atlas_steps+1;return "3|64|0|0|2|2|384|a5"
end
require("ui/grid_placement_router").init()
listeners.ui_grid_placement_profiles_request(nil,{PlayerID=0})
clock=6;scheduler.think();assert(atlas_steps==1)
listeners.ui_grid_placement_preview_end(nil,{PlayerID=0,session_id=3})
clock=6.1;scheduler.think()
assert(atlas_steps==2 and sent[#sent].name=="ui_grid_placement_static_area",
    "ending preview does not cancel independent terrain preload")
listeners.ui_grid_placement_profiles_request(nil,{PlayerID=1})
assert(sent[#sent].id==1 and sent[#sent].name=="ui_grid_placement_static_area",
    "late joining client immediately receives completed atlas")
print("GRID_STATIC_ROUTER_PASS")

-- Pose messages have their own ordering and never enter terrain validation.
local poses,clears={},0
package.loaded["systems/grid_preview_model_service"]={clear=function() clears=clears+1 end,
    update=function(...) poses[#poses+1]={...} end}
local before=#queries
local pose={PlayerID=0,session_id=900,request_id=1,ability_name="ability_build_house",
    entindex=10,ability_entindex=20,x=128,y=256,z=384}
listeners.ui_grid_placement_pose(nil,pose)
assert(#poses==1 and #queries==before)
listeners.ui_grid_placement_pose(nil,pose)
assert(#poses==1,"duplicate pose ignored")
pose.request_id=2;pose.entindex=11;pose.ability_entindex=21
listeners.ui_grid_placement_pose(nil,pose)
assert(#poses==1,"foreign builder cannot move a preview")
pose.entindex=10;pose.ability_entindex=20
listeners.ui_grid_placement_pose(nil,pose)
assert(#poses==2 and #queries==before)
listeners.ui_grid_placement_preview_end(nil,{PlayerID=0,session_id=900})
local cleared=clears
pose.request_id=3
listeners.ui_grid_placement_pose(nil,pose)
assert(#poses==2 and clears==cleared,"closed session cannot resurrect model")
print("GRID_MODEL_POSE_PASS independent validation, authentication, stale/closed protection")
