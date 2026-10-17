-- Real relocation service, native ability entry and server grid router.
package.path="scripts/vscripts/?.lua;"..package.path
local bus,events=require("core/event_bus"),require("core/events")
bus.reset()
Vector=function(x,y,z) return {x=x,y=y,z=z or 384} end
class=function(t) return t end
IsServer=function() return true end
UF_SUCCESS,UF_FAIL_CUSTOM=0,1
local time,grid_calls,moves,cooldowns=0,0,0,0
local blocked,move_ok,defeated=false,true,false
local units,abilities,states={},{},{}
local records={
    {id=10,owner=0,building="wall",ability="ability_wall_blink",width=4,cooldown=120},
    {id=11,owner=1,building="wall",ability="ability_wall_blink",width=4,cooldown=120},
    {id=12,owner=0,building="arrow_tower",ability="ability_building_blink",width=2,cooldown=5},
    {id=13,owner=0,building="main_city",ability="ability_building_blink",width=4,cooldown=5},
}
for _,r in ipairs(records) do
    local u={IsNull=function() return false end,IsAlive=function() return true end,
        entindex=function() return r.id end,GetTeamNumber=function() return 2 end,
        GetAbsOrigin=function() return Vector(0,0,384) end}
    local a={ready_at=0,IsNull=function() return false end,IsHidden=function() return false end,
        IsActivated=function() return true end,GetLevel=function() return 1 end,
        GetCaster=function() return u end,entindex=function() return r.id+100 end,
        GetAbilityName=function() return r.ability end,GetCooldown=function() return r.cooldown end,
        GetCursorPosition=function() return Vector(385,191,384) end}
    function a:IsCooldownReady() return time>=self.ready_at end
    function a:StartCooldown(seconds)
        assert(seconds==r.cooldown,"wall/tower cooldowns must remain independent")
        self.ready_at=time+seconds;cooldowns=cooldowns+1
    end
    function a:EndCooldown() self.ready_at=time end
    function u:FindAbilityByName(name) if name==r.ability then return a end end
    units[r.id],abilities[r.id]=u,a
    states[r.id]={unit=u,player_id=r.owner,building_id=r.building,
        definition={footprint={x=r.width,y=r.width}}}
end
units[10].survival_player_id=0
package.loaded["systems/player_context_service"]={is_defeated=function() return defeated end}
package.loaded["systems/tower_fusion_service"]={relocation_state=function() end}
package.loaded["systems/building_system"]={relocate_for_player=function(player,index,p)
    assert(player==0 and (index==10 or index==12))
    assert(p.x%64==0 and p.y%64==0 and p.z==384)
    if move_ok then moves=moves+1 end
    return move_ok,move_ok and nil or "wall_relocation_failed"
end}
bus.handle_request(events.BUILDING_QUERY_REQUEST,function(p)
    assert(p.read_only);return states[p.entindex]
end)
bus.handle_request(events.GRID_CAN_PLACE_REQUEST,function(p)
    grid_calls=grid_calls+1
    assert(p.team==2 and p.ignore_entindexes==nil)
    local expected=p.ignore_entindex==12 and 2 or 4
    assert(p.footprint.x==expected and p.footprint.y==expected,
        "wall preview and commit require the actual 4x4 footprint")
    return {ok=not blocked,error=blocked and "build_cell_occupied" or nil,
        world_position=Vector(math.floor(p.position.x/64+.5)*64,
            math.floor(p.position.y/64+.5)*64,384),cells={}}
end)
local relocation=require("systems/tower_relocation_service")
local p=Vector(385,191,0)
assert(relocation.validate(0,10,p,110).ok)
assert(relocation.move(0,10,p,110).ok and moves==1 and cooldowns==1)
local checked=grid_calls
assert(relocation.move(0,10,p,110).error=="move_ability_cooldown" and grid_calls==checked)
time=119.99
assert(relocation.move(0,10,p,110).error=="move_ability_cooldown")
time=120
assert(relocation.validate(0,10,p,110).ok,"wall cooldown must expire after 120 seconds")
blocked=true
assert(not relocation.move(0,10,p,110).ok and cooldowns==1)
blocked=false;move_ok=false
assert(not relocation.move(0,10,p,110).ok and cooldowns==1)
move_ok=true
assert(relocation.validate(0,11,p,111).error=="tower_not_owned")
assert(relocation.validate(0,13,p,113).error=="building_not_movable")
assert(relocation.validate(0,10,p,112).error=="ability_profile_mismatch")
assert(relocation.validate(0,10,Vector(1025,0,384),110).error=="relocation_out_of_range")
for _,value in ipairs({0/0,math.huge,-math.huge,40000}) do
    assert(relocation.validate(0,10,Vector(value,0,384),110).error=="invalid_position")
end
defeated=true
assert(relocation.validate(0,10,p,110).error=="player_defeated")
defeated=false
assert(relocation.move(0,12,p,112).ok and cooldowns==2,"tower still uses its own five-second cooldown")

-- The native wall class uses the same implementation; an engine-paid cooldown
-- is not started twice, and failure refunds that native cooldown.
local native=require("abilities/ability_building_blink")
assert(_G.ability_wall_blink==native)
local ability=abilities[10]
setmetatable(ability,{__index=native})
assert(ability:CastFilterResultLocation(p)==UF_SUCCESS)
ability.ready_at=time+120
local before=cooldowns
ability:OnSpellStart()
assert(cooldowns==before and ability.ready_at==time+120)
blocked=true
ability:OnSpellStart()
assert(ability:IsCooldownReady(),"a rejected native wall move must refund its cooldown")
blocked=false
ability.cast_error="move_ability_cooldown"
assert(ability:GetCustomCastErrorLocation()=="移动城墙CD中")

-- Client previews are advisory: the real router authenticates the wall and
-- rechecks placement on commit without resolving a builder or paying costs.
local listeners,replies={},{}
GameRules={GetGameTime=function() return time end}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    GetPlayer=function(_,id) return id end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_,id,name,data) replies[#replies+1]={id=id,name=name,data=data} end}
EntIndexToHScript=function(index) return units[index] or abilities[index-100] end
package.loaded["config/buildings_config"]={wall={id="wall",footprint={x=4,y=4}},
    arrow_tower={id="arrow_tower",footprint={x=2,y=2}}}
package.loaded["config/generated/building_definitions"]={rows={}}
package.loaded["systems/grid_preview_model_service"]={clear=function() end,clear_all=function() end,
    update=function() end}
package.loaded["systems/grid_placement_system"]={preview_area=function() return "" end}
for _,event in ipairs({events.BUILDER_GET_REQUEST,events.BUILD_CAN_PLACE_REQUEST,events.BUILD_REQUEST}) do
    bus.handle_request(event,function() error("wall movement must not use construction or resource requests") end)
end
local router=require("ui/grid_placement_router")
router.init()
local profile=router._profiles_for_test().ability_wall_blink
assert(profile.building_id=="wall" and profile.placement_action=="relocate"
    and profile.footprint_x==4 and profile.footprint_y==4)
local request={PlayerID=0,player_id=1,session_id=1,request_id=1,
    ability_name="ability_wall_blink",entindex=10,ability_entindex=110,x=385,y=191,z=384}
listeners.ui_grid_placement_validate(nil,request)
assert(replies[#replies].id==0 and replies[#replies].data.success==1)
listeners.ui_grid_placement_commit(nil,request)
assert(replies[#replies].data.success==1 and ability.ready_at==time+120)
local committed,charged=moves,cooldowns
listeners.ui_grid_placement_commit(nil,request)
assert(replies[#replies].data.success==0 and moves==committed and cooldowns==charged)
ability:EndCooldown()
request.session_id=2;request.request_id=2;request.ability_name="ability_building_blink"
listeners.ui_grid_placement_commit(nil,request)
assert(replies[#replies].data.error=="ability_profile_mismatch" and moves==committed,
    "a tower profile cannot resize the wall preview/commit")
request.session_id=3;request.request_id=3;request.ability_name="ability_wall_blink"
listeners.ui_grid_placement_preview_end(nil,request)
listeners.ui_grid_placement_commit(nil,request)
assert(replies[#replies].data.error=="stale_preview_session" and cooldowns==charged)
print("WALL_MOVE_GRID_PASS wall120s tower5s, native refund, ownership and 4x4 profile, no construction costs, cold commit and stale-session safety")
