local file=assert(io.open('scripts/vscripts/tests/test_grid_builder_preview.lua','rb'))
local text=file:read('*a');file:close()
local at=assert(text:find('require("ui/grid_placement_router").init()',1,true))
local prefix=text:sub(1,at-1)
local body=[=[
GetMapName=function()return 'template_map'end
package.loaded['config/buildings_config']=nil
package.loaded['config/generated/building_definitions']=nil
package.loaded['config/grid_placement_config']=nil
package.loaded['core/building_grid_geometry']=nil
local lookup=require('config/generated/ui_static_catalog_lookup')
local wire=require('ui/compact_wire')
local handlers,published,opened,registrations={},{},{},0
local bound=false
package.loaded['ui/compact_ui_transport']={available=function()return true end,
 is_bound=function()return bound end,is_open=function(_,view)return opened[view]end,
 register_view=function(id,h)assert(not handlers[id]);handlers[id]=h;registrations=registrations+1;return true end,
 publish=function(id,view,ops,options)published[#published+1]={id=id,view=view,ops=ops,options=options};return true end}
local poses=0
package.loaded['systems/grid_preview_model_service']={clear=function()end,clear_all=function()end,update=function()poses=poses+1 end}
own_ability.GetAbilityName=function()return 'ability_build_arrow_tower'end
other_ability.GetAbilityName=own_ability.GetAbilityName
own_ability.StartCooldown=function()end;own_ability.GetCooldown=function()return 1 end
local checks,builds=0,0
local refused=false
bus.reset()
bus.handle_request(events.BUILDER_GET_REQUEST,function(p)return {ok=true,builder=p.player_id==0 and own or other}end)
local function geometry(position)
 local cells={};for x=-1,0 do for y=-1,0 do cells[#cells+1]={x=(x+0.5)*64,y=(y+0.5)*64,z=384,ok=true}end end
 return {ok=true,anchor_x=0,anchor_y=0,world_position={x=0,y=0,z=384},cells=cells}
end
bus.handle_request(events.BUILD_CAN_PLACE_REQUEST,function(p)
 checks=checks+1;assert(p.caster==own and p.player_id==0 and p.building_id=='arrow_tower')
 return {ok=not refused,error=refused and 'insufficient_gold' or nil,grid=geometry(p.position)}
end)
bus.handle_request(events.BUILD_REQUEST,function(p)assert(p.caster==own and p.source_ability==own_ability);builds=builds+1;return {ok=true}end)
-- Advisory area is an actual v3 bitmask. It never changes the exact-footprint
-- validator and contains no ownership, costs or account identity.
package.loaded['systems/grid_placement_system'].preview_area=function()return '3|64|-2|-2|4|4|384|aaaaaaaa'end
local router=require('ui/grid_placement_router');router.init()
assert(registrations==2 and handlers[4] and handlers[6] and #sent==0)
bus.emit(events.BUILDER_READY,{player_id=0});assert(#sent==0,'pre-Hello profile events cannot opt into legacy large packets')
bound=true;opened[4],opened[6]=true,true
assert(#assert(handlers[4].open(0))>0);handlers[6].open(0)
local function arguments(session,request,actor,ability)
 local out={grid_session=session,grid_request=request,grid_actor=actor or 10,grid_ability=ability or 20,
  grid_profile=lookup.by_key['grid:profile:ability_build_arrow_tower']}
 for axis,value in pairs({x=0,y=0,z=384})do local words=assert(wire.float64_words(value));out['grid_'..axis..'_hi']=words.hi;out['grid_'..axis..'_lo']=words.lo end
 return out
end
handlers[4].input(0,1,arguments(77,1),2)
assert(checks==1 and #published>0 and #sent==0,'typed input must reuse the original business/grid validator without legacy output')
local function last_success()
 for n=#published,1,-1 do for _,op in ipairs(published[n].ops)do
  if op.record==lookup.by_key['grid:validation'] and op.field==lookup.field_by_name.success then return op.value end
 end end
end
assert(last_success()==1)
handlers[4].input(0,1,arguments(77,2,11,21),3)
assert(checks==1 and last_success()==0,'foreign builder/ability must still fail before business validation')
refused=true;handlers[4].input(0,1,arguments(77,3),4)
assert(checks==2 and last_success()==0,'business rejection must not become success because geometry is clear')
refused=false;handlers[4].input(0,4,arguments(77,4),5)
assert(builds==1)
handlers[4].input(0,4,arguments(77,5),6)
assert(builds==1,'a fresh transport revision cannot replay a closed preview commit')
handlers[4].input(0,1,arguments(77,6),7);assert(checks==3,'closed session cannot validate again')
handlers[4].input(0,2,arguments(78,1),8);assert(poses==1)
local same_world_handler=handlers[4];router.init()
assert(registrations==2 and handlers[4]==same_world_handler,'same-world setup must reset/restore the existing two handlers, not register duplicates')
local old=handlers[4];bus.reset();local before=checks
old.input(0,1,arguments(79,1),9);assert(checks==before,'old-world typed handlers must expire')
handlers={};router.init();assert(registrations==4 and handlers[4] and handlers[6])
print('COMPACT_GRID_VIEWS_PASS: actual router/validators, private actor checks, cost rejection, one commit, closed replay, 0legacy, real bus.reset')
]=]
local prelude="package.path='scripts/vscripts/?.lua;'..package.path\npackage.loaded['core/test_access_policy']={enabled=function()return false end,enforce=function()return true end}\n"
assert(loadstring(prelude..prefix..'\n'..body,'@actual_compact_grid_router'))()
