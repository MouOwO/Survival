-- Real regions, builder guard, hero destination, tree lifecycle and placement;
-- the native terrain arrays/marker origins are supplied by the DMX reader.
package.path="scripts/vscripts/?.lua;"..package.path
local terrain=assert(loadfile(assert(arg[1])))()
local native=arg[2] and assert(loadfile(arg[2]))()
local mt={__add=function(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end}
Vector=function(x,y,z)return setmetatable({x=x,y=y,z=z or 0},mt)end
GetMapName=function()return "template_map"end
local function vertex(i,j)return tonumber(terrain.height:sub(j*129+i+1,j*129+i+1))end
local function height(p)
 if native then
  local sample=native[string.format("%.2f:%.2f",p.x,p.y)]
  if sample then return sample[1] end
 end
 local x,y=(p.x+16384)/256,(p.y+16384)/256;local i,j=math.floor(x),math.floor(y);local u,v=x-i,y-j
 return 128+128*((1-u)*(1-v)*vertex(i,j)+u*(1-v)*vertex(i+1,j)+(1-u)*v*vertex(i,j+1)+u*v*vertex(i+1,j+1))
end
GetGroundHeight=function(p)return height(p)end
GetGroundPosition=function(p)return Vector(p.x,p.y,height(p))end
GridNav={IsTraversable=function(_,p)
 if native then local sample=native[string.format("%.2f:%.2f",p.x,p.y)];if sample then return sample[2] end end
 local k=math.floor((p.y+16384)/64)*512+math.floor((p.x+16384)/64)+1;return terrain.nav:sub(k,k)=="0"end,
 IsBlocked=function()return false end,IsNearbyTree=function()return false end,CanFindPath=function()return true end}
Entities={FindByName=function(_,_,name)local p=terrain.markers[name];return p and {IsNull=function()return false end,GetAbsOrigin=function()return Vector(unpack(p))end}end}
package.loaded["systems/match_setup_service"]={get_mode=function()return "ruins"end}
package.loaded["core/test_access_policy"]={enabled=function()return false end}
local slots={"east","south","west","north"}

package.loaded["core/scheduler"]={every=function()end,cancel=function()end}
package.loaded["visual/model_scale"]={apply=function()end}
package.loaded["core/particle_manager"]={show_green_number=function()end}
package.loaded["core/modifier_registry"]={ensure=function()end}
package.loaded["systems/rogue_effect_state_service"]={numeric=function()return 0 end}
package.loaded["systems/harvest_feedback_service"]={reset=function()end,add=function()end}
package.loaded["systems/registered_wave_lane_view"]={append=function(rows)return rows end}
package.loaded["systems/wall_navigation_service"]={original_nav=function()end}
package.loaded["systems/forbidden_region_service"]={validate_building_footprint=function()return true end}
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS,DOTA_UNIT_CAP_NO_ATTACK=2,3,0
DOTA_UNIT_TARGET_TEAM_BOTH,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC=3,1,2
DOTA_UNIT_TARGET_BUILDING,DOTA_UNIT_TARGET_FLAG_INVULNERABLE,FIND_ANY_ORDER=4,1,0
DOTA_UNIT_ORDER_MOVE_TO_POSITION=1
local units,serial={},0
local function unit(p)
 serial=serial+1;local u={position=p,index=serial}
 function u:IsNull()return false end;function u:IsAlive()return true end
 function u:GetAbsOrigin()return self.position end;function u:SetAbsOrigin(p)self.position=p end
 u.SetOrigin=u.SetAbsOrigin
 function u:Stop()self.stopped=true end;function u:entindex()return self.index end
 function u:GetTeamNumber()return 2 end;function u:GetHullRadius()return 0 end
 function u:HasModifier()return false end;function u:IsRealHero()return false end
 function u:GetUnitName()return "test_unit"end
 function u:SetHealth(n)self.health=n end;function u:GetHealth()return self.health end
 function u:SetMaxHealth(n)self.maximum=n end;function u:GetMaxHealth()return self.maximum end
 for _,name in ipairs({"SetBaseMaxHealth","SetPhysicalArmorBaseValue","SetModel","SetOriginalModel","SetAttackCapability"})do u[name]=function()end end
 units[serial]=u;return u
end
CreateUnitByName=function(_,p)return unit(p)end
FindUnitsInRadius=function()local out={};for _,u in pairs(units)do out[#out+1]=u end;return out end
EntIndexToHScript=function(id)return units[id]end
GameRules={GetGameTime=function()return 1 end}
local bus,events=require("core/event_bus"),require("core/events")
local regions=require("systems/rich_region_service")
local spawns=require("systems/mode_spawn_service")
local destinations=require("systems/destination_validation_service")
local grid=require("systems/grid_placement_system")
local trees=require("systems/tree_system")
local config=assert(spawns.config())
-- Flat land beside each stair was excluded by the old landing rectangles.
-- Check a whole wall and a usable construction position, not only its center.
local stair_walls={{-13376,-7872},{-10432,-7872},{-12608,-9792},{-11200,-9792}}
bus.reset();grid.init();regions.init();trees.init()
if native then
 local expanded=config.player_build_bounds
 config.player_build_bounds=nil;regions.init()
 for id=0,3 do
  local w=stair_walls[id+1]
  assert(not grid._can_place_for_test({player_id=id,position=Vector(w[1],w[2],640),footprint={x=4,y=4}}).ok,
      "old landing bounds must reproduce all four rejected stair walls")
 end
 config.player_build_bounds=expanded;regions.init()
end
local spawned={}
bus.subscribe(events.TREE_SPAWNED,function(p)spawned[p.player_id]=units[p.entindex]end)
for id=0,3 do
 local spawn=assert(require("systems/player_context_service").resolve_builder_spawn(id))
 assert(spawn.position.z==640,"builder starts on highest plateau")
 local region=assert(regions.region(id))
 for _,cell in ipairs(region.cells)do assert(math.abs(height(Vector((cell[1]+.5)*64,(cell[2]+.5)*64))-640)<=config.build_ground_height_tolerance)end
 local builder=unit(spawn.position);builder.survival_builder_id="default_builder";builder.survival_player_id=id
 assert(regions.attach_builder(id,builder,slots[id+1]))
 if native then
  local wall=Vector(stair_walls[id+1][1],stair_walls[id+1][2],640)
  for dx=-96,96,64 do for dy=-96,96,64 do
   for _,o in ipairs({{0,0},{24.32,24.32},{24.32,-24.32},{-24.32,24.32},{-24.32,-24.32}})do
    assert(native[string.format("%.2f:%.2f",wall.x+dx+o[1],wall.y+dy+o[2])],"missing native wall sample")
   end
  end end
  local placed=grid._can_place_for_test({player_id=id,position=wall,footprint={x=4,y=4}})
  assert(placed.ok,"stair wall "..id..": "..tostring(placed.error))
  assert(not grid._can_place_for_test({player_id=(id+1)%4,position=wall,footprint={x=4,y=4}}).ok,
      "stair repair must not permit construction on another player's plateau")
  local work=assert(require("systems/builder_work_position_service").find(builder,{footprint={x=4,y=4}},wall),
      "builder needs a valid work position beside the stair wall")
  assert(native[string.format("%.2f:%.2f",work.x,work.y)],"missing native work-position sample")
 end
 local channel=assert(spawns.wave_marker(id));local low=channel.position
 assert(low.z==128 and low.x>=-12800 and low.x<=-10752 and low.y>=-9472 and low.y<=-8192,"waves start in the central clearing")
 assert(not regions.validate_position(id,low) and destinations.validate_hero_position(low))
 assert(regions.validate_order({order_type=1,position_x=low.x,position_y=low.y,position_z=low.z},{builder})==false)
 builder:SetAbsOrigin(low);assert(regions.guard());assert(builder.stopped and builder.position.z==640)
 local city=unit(spawn.position);city.survival_player_id=id;city.survival_is_building=true
 bus.emit(events.BUILDING_CREATED,{building_id="main_city",player_id=id,unit=city})
 local tree=assert(spawned[id],"each highland base gets its own tree")
 local p=tree:GetAbsOrigin();assert(p.z==640 and regions.validate_position(id,p))
 local footprint=trees._tree_grid_for_test(p)
 assert(regions.validate_building_footprint(id,footprint.grid_x*64,footprint.grid_y*64,(footprint.grid_x+2)*64,(footprint.grid_y+2)*64))
 local wave={mode="ruins",player_id=id,route_id=id,spawn_position=low}
 for _=1,20 do local p=assert(spawns.wave_position(wave,32));assert(math.abs(p.x-low.x)<=192 and math.abs(p.y-low.y)<=192 and p.z==128)end
end
for id=0,3 do
 local low=assert(spawns.wave_marker(id)).position
 assert(not grid._can_place_for_test({player_id=id,position=low,footprint={x=4,y=4}}).ok,
     "central lowland must remain unbuildable")
end
if native then print("RUINS_STAIR_WALLS_PASS: four complete 4x4 walls and construction work positions; foreign plateaus and central lowland rejected") end
print("RUINS_SPAWNS_PASS: four highland builders/trees, full footprints, lowland builder rejection/guard, hero access, eighty safe central monster spawns")
