package.path = "scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS=2
DOTA_UNIT_TARGET_TEAM_BOTH=3
DOTA_UNIT_TARGET_HERO=1
DOTA_UNIT_TARGET_BASIC=2
DOTA_UNIT_TARGET_BUILDING=4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=0
FIND_ANY_ORDER=0
local mt={__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},mt) end
GetGroundHeight=function() return 384 end
GetGroundPosition=function(p) return Vector(p.x,p.y,384) end
local queries=0
FindUnitsInRadius=function() queries=queries+1; return {} end
GridNav={IsTraversable=function(_,p) return p.x>=0 end,
    IsBlocked=function() return false end, IsNearbyTree=function() return false end}
package.loaded["systems/forbidden_region_service"]={validate_building_footprint=function(_,y)
    return y>=0, y<0 and "forbidden" or nil
end}
local grid=require("systems/grid_placement_system")
local config=require("config/grid_placement_config")
local center=Vector(19,27,384)
local function decode(encoded)
    local fields={}
    for field in encoded:gmatch("[^|]+") do fields[#fields+1]=field end
    assert(fields[1]=="3" and tonumber(fields[2])==64)
    local cells={}
    local width,height=tonumber(fields[5]),tonumber(fields[6])
    for i=0,width*height-1 do
        local bits=tonumber(fields[8]:sub(math.floor(i/2)+1,math.floor(i/2)+1),16)
        local state=math.floor(bits/(i%2==0 and 1 or 4))%4
        if state>0 then
            cells[#cells+1]={tonumber(fields[3])+math.floor(i/height),
                tonumber(fields[4])+i%height,tonumber(fields[7]),state==2 and 1 or 0}
        end
    end
    return cells
end

local encoded=grid.preview_area({position=center,team=2,ignore_entindex=10})
assert(queries==1,"one spatial unit query for the whole circle")
local count,green,red=0,0,0
for _,v in ipairs(decode(encoded)) do
    local x,y=(v[1]+0.5)*64,(v[2]+0.5)*64
    assert((x-center.x)^2+(y-center.y)^2<=config.preview_visual.radius^2)
    assert(v[3]==384)
    if x<0 or y<0 then assert(v[4]==0,"blocked terrain / policy is red") end
    if v[4]==1 then green=green+1 else red=red+1 end
    count=count+1
end
assert(count>1200 and count<1300 and green>0 and red>0)
assert(config.preview_visual.radius>=1280,"wide screen coverage")
assert(#encoded<1000,"denser 64-unit overlay stays under 1KB")
assert(next(grid._occupied_for_test())==nil,"preview must not reserve cells")
print("GRID_PREVIEW_AREA_PASS cells="..count.." bytes="..#encoded)

-- A blocker in one 64-unit cell must remain visible.
GridNav.IsTraversable=function(_,p) return not (p.x>64 and p.x<128 and p.y>64 and p.y<128) end
encoded=grid.preview_area({position=center,team=2,ignore_entindex=10})
local found=false
for _,v in ipairs(decode(encoded)) do
    if v[1]==1 and v[2]==1 then assert(v[4]==0); found=true end
end
assert(found,"overview cannot hide a small blocker")

config.build_ground_height=384
GetGroundHeight=function(p) return p.x>200 and 768 or 384 end
GetGroundPosition=function(p) return Vector(p.x,p.y,GetGroundHeight(p)) end
encoded=grid.preview_area({position=center,team=2,ignore_entindex=10})
for _,v in ipairs(decode(encoded)) do
    assert(v[3]==384,"cliff cells share the construction plane without overlapping")
    if (v[1]+0.5)*64>320 then assert(v[4]==0,"actual cliff height remains blocked") end
end
local geometry=require("core/building_grid_geometry")
for value=-512,512,7 do
    local anchor,world,origin=geometry.snap_axis(value,4)
    assert(world%64==0 and world==anchor*64 and origin==anchor-2)
    local again,again_world=geometry.snap_axis(world,4)
    assert(again==anchor and again_world==world,"snap is stable at positive and negative coordinates")
    assert((origin+4)*64-origin*64==256,"wall stays 256 units wide / four complete 64-unit cells")
end

-- Streaming starts at the cursor, preserves completed terrain across jumps,
-- and never trusts the advisory cache when actually placing a building.
local game_time=10
GameRules={GetGameTime=function() return game_time end}
GetGroundHeight=function() return 384 end
local terrain_calls=0
GridNav.IsTraversable=function() terrain_calls=terrain_calls+1; return true end
package.loaded["systems/forbidden_region_service"].validate_building_footprint=function() return true end
local terrain_cache={}
local payload={position=Vector(0,0,384),team=2,ignore_entindex=10,
    yield_after=128,time_budget=100,terrain_cache=terrain_cache}
local job=coroutine.create(function() return grid.preview_area(payload) end)
local ok,partial=coroutine.resume(job)
assert(ok and coroutine.status(job)=="suspended")
local initial=decode(partial)
local scanned=0
for _,v in ipairs(initial) do
    local x,y=(v[1]+0.5)*64,(v[2]+0.5)*64
    if x-32>=config.build_bounds.min_x and x+32<=config.build_bounds.max_x
        and y-32>=config.build_bounds.min_y and y+32<=config.build_bounds.max_y then
        scanned=scanned+1
        assert(x*x+y*y<512^2,"scan starts near mouse, not corner of bounding square")
    else assert(v[4]==0,"outside construction bounds is immediately known red") end
end
assert(scanned==128,"cold first batch immediately publishes 128 near-cursor terrain cells")
local final,batches=partial,1
while coroutine.status(job)~="dead" do
    ok,final=coroutine.resume(job); assert(ok,final); batches=batches+1
end
assert(#decode(final)>1200 and batches<=10,"cold scan needs at most ten count-limited batches")
terrain_calls=0
local cached=grid.preview_area(payload)
assert(cached==final and terrain_calls==0,"stationary cached overview performs no terrain rechecks")
payload.position=Vector(256,0,384)
job=coroutine.create(function() return grid.preview_area(payload) end)
ok,partial=coroutine.resume(job); assert(ok,partial)
assert(#decode(partial)>1000,"moving four cells retains the scanned overlap in the first response")
assert(terrain_calls<128*6,"cursor move scans only exposed terrain")

-- Moving units are NOT cached along with terrain. Each unit origin/hull is
-- sampled once per scan, even with hundreds of visible cells.
local origin_reads,hull_reads=0,0
FindUnitsInRadius=function() return {{IsNull=function() return false end,
    IsAlive=function() return true end,entindex=function() return 99 end,
    GetAbsOrigin=function() origin_reads=origin_reads+1; return Vector(32,32,384) end,
    GetHullRadius=function() hull_reads=hull_reads+1; return 20 end}} end
payload.position=Vector(0,0,384); payload.yield_after=nil
terrain_calls=0
local occupied_result=grid.preview_area(payload)
for _,v in ipairs(decode(occupied_result)) do
    if v[1]==0 and v[2]==0 then assert(v[4]==0,"new unit blocks cached green terrain") end
end
assert(origin_reads==1 and hull_reads==1 and terrain_calls==0,"unit work scales with units, not units times tiles")
FindUnitsInRadius=function() return {} end
grid._occupied_for_test()[0]={[0]=999}
for _,v in ipairs(decode(grid.preview_area(payload))) do
    if v[1]==0 and v[2]==0 then assert(v[4]==0,"new building blocks cached terrain") end
end
grid._occupied_for_test()[0]=nil
GridNav.IsTraversable=function() terrain_calls=terrain_calls+1; return false end
local exact=grid._can_place_for_test({position=Vector(64,64,384),footprint={x=2,y=2},team=2})
assert(not exact.ok and terrain_calls>0,"actual placement bypasses advisory terrain cache")
game_time=13; terrain_calls=0
payload.yield_after=128
job=coroutine.create(function() return grid.preview_area(payload) end)
ok,partial=coroutine.resume(job); assert(ok,partial)
assert(#decode(partial)>1200,"expiry refresh retains coverage instead of blanking the whole circle")
payload.yield_after=nil
for _,v in ipairs(decode(grid.preview_area(payload))) do assert(v[4]==0,"expired terrain gets refreshed") end
assert(terrain_calls>0)
print("GRID_STREAM_CACHE_PASS first_cells="..#initial.." batches="..batches.." refresh_coverage="..#decode(partial))

-- Full-map static terrain survives cursor jumps, TTL expiry and preview sessions.
config.build_bounds={min_x=-2048,max_x=2048,min_y=-2048,max_y=2048}
GridNav.IsTraversable=function(_,p) terrain_calls=terrain_calls+1; return p.x>=0 end
terrain_calls=0; queries=0
FindUnitsInRadius=function() queries=queries+1; return {} end
local atlas_job=coroutine.create(function() return grid.static_preview({yield_after=128,time_budget=100}) end)
local atlas,atlas_batches=nil,0
while coroutine.status(atlas_job)~="dead" do
    local success,result=coroutine.resume(atlas_job);assert(success,result)
    atlas=result;atlas_batches=atlas_batches+1
end
assert(atlas_batches>1 and queries==0,"startup scan is incremental and never queries units")
assert(#decode(atlas)==4096 and #atlas<2200,"compact complete static atlas")
for _,v in ipairs(decode(atlas)) do assert(v[4]==(v[1]>=0 and 1 or 0)) end
game_time=100;terrain_calls=0
for _,x in ipairs({-256,256,0,512}) do
    grid.preview_area({position=Vector(x,0,384),team=2,terrain_cache={}})
end
assert(terrain_calls==0,"new preview sessions and distant cursor moves reuse preloaded terrain beyond TTL")
grid._occupied_for_test()[0]={[0]=999}
for _,v in ipairs(decode(grid.preview_area({position=Vector(0,0,384),team=2}))) do
    if v[1]==0 and v[2]==0 then assert(v[4]==0,"new building still overrides static green") end
end
grid._occupied_for_test()[0]=nil
GridNav.IsTraversable=function() terrain_calls=terrain_calls+1;return false end
assert(not grid._can_place_for_test({position=Vector(64,64,384),footprint={x=2,y=2},team=2}).ok)
assert(terrain_calls>0,"commit validation must not trust the static advisory atlas")
print("GRID_STATIC_TERRAIN_PASS cells=4096 cursor_terrain_queries=0")

-- Completed walls reserve only their registered rectangle, not a second,
-- oversized circular unit hull. Exercise both preview and authoritative build.
local bus=require("core/event_bus")
local events=require("core/events")
bus.reset();grid.init()
GridNav.IsTraversable=function() return true end
local wall={survival_is_building=true,IsNull=function() return false end,IsAlive=function() return true end,
    entindex=function() return 77 end,GetAbsOrigin=function() return Vector(0,0,384) end,
    GetHullRadius=function() return 256 end}
EntIndexToHScript=function(i) return i==77 and wall or nil end
FindUnitsInRadius=function() return {wall} end
local reservation={grid_x=-2,grid_y=-2,footprint={x=4,y=4},entindex=77}
assert(bus.request(events.GRID_OCCUPY_REQUEST,reservation))
local adjacent={position=Vector(192,64,384),footprint={x=2,y=2},team=2}
assert(grid._can_place_for_test(adjacent).ok,"completed wall must allow building flush against its footprint")
assert(not grid._can_place_for_test({position=Vector(0,0,384),footprint={x=2,y=2},team=2}).ok,
    "wall footprint remains occupied")
for _,v in ipairs(decode(grid.preview_area({position=Vector(0,0,384),team=2}))) do
    if v[1]==2 and v[2]==0 then assert(v[4]==1,"adjacent overview cell is green, not hull-blocked") end
    if v[1]==0 and v[2]==0 then assert(v[4]==0,"occupied overview cell stays red") end
end
assert(bus.request(events.GRID_RELEASE_REQUEST,reservation))
assert(not grid._can_place_for_test(adjacent).ok,"unregistered physical blockers must still be tested")
wall.survival_wall_collision_barrier=true
assert(grid._can_place_for_test(adjacent).ok,"retired barrier never blocks construction during migration")
terrain_calls=0
GridNav.IsTraversable=function() terrain_calls=terrain_calls+1;return true end
FindUnitsInRadius=function() return {} end
for _,v in ipairs(decode(grid.preview_area({position=Vector(10000,10000,384),team=2}))) do
    assert(v[4]==0,"ocean outside build bounds stays red")
end
assert(terrain_calls==0,"permanently forbidden ocean requires zero terrain checks")
print("GRID_WALL_NEIGHBORS_PASS exact footprint, preview parity, release, retired barriers, ocean zero scans")

-- Non-combat rebirth displays must not become invisible construction blockers.
local display={IsNull=function() return false end,IsAlive=function() return true end,
    entindex=function() return 101 end,GetAbsOrigin=function() return Vector(32,32,384) end,
    GetHullRadius=function() return 0 end,survival_rebirth_scene_display=true}
FindUnitsInRadius=function() return {display} end
local at_display={position=Vector(64,64,384),footprint={x=2,y=2},team=2}
assert(grid._can_place_for_test(at_display).ok,"display body does not reserve its center cell")
local visible_cell=false
for _,v in ipairs(decode(grid.preview_area({position=Vector(0,0,384),team=2}))) do
    if v[1]==0 and v[2]==0 then assert(v[4]==1);visible_cell=true end
end
assert(visible_cell,"overview keeps the display cell available")
display.survival_rebirth_scene_display=nil
assert(not grid._can_place_for_test(at_display).ok,"real combat units still block placement")
FindUnitsInRadius=function() return {} end
print("GRID_REBIRTH_DISPLAY_PASS nonblocking preview and placement, live combat blockers preserved")

-- Startup tree markers have no entity yet. Reconciliation must preserve them
-- and live resource trees, while still clearing dead or missing buildings.
local tree_alive=true
local tree={survival_tree_owner_id=0,IsNull=function() return false end,
    IsAlive=function() return tree_alive end}
local entity_lookups=0
EntIndexToHScript=function(index)
    assert(type(index)=="number","named reservation must never reach the engine entity API")
    entity_lookups=entity_lookups+1
    if index==88 then return tree end
    return nil
end
local named={grid_x=8,grid_y=8,footprint={x=2,y=2},entindex="survival_tree_reserved"}
local living={grid_x=10,grid_y=8,footprint={x=2,y=2},entindex=88}
local stale={grid_x=12,grid_y=8,footprint={x=2,y=2},entindex=99}
assert(bus.request(events.GRID_OCCUPY_REQUEST,named))
assert(bus.request(events.GRID_OCCUPY_REQUEST,living))
assert(bus.request(events.GRID_OCCUPY_REQUEST,stale))
grid._reconcile_occupied_for_test()
local cells=grid._occupied_for_test()
assert(cells[8][8]=="survival_tree_reserved","keep future tree location reserved")
assert(cells[10][8]==88,"live tree is a valid grid occupant")
assert(cells[12]==nil,"missing building occupancy is still removed")
assert(entity_lookups==2,"resolve each numeric occupant once, never static markers")
assert(not grid._can_place_for_test({position=Vector(576,576,384),footprint={x=2,y=2},team=2}).ok,
    "authoritative placement cannot overlap a future tree")
tree_alive=false
grid._reconcile_occupied_for_test()
assert(cells[10]==nil and cells[8][8]=="survival_tree_reserved",
    "dead tree handle expires independently of persistent startup marker")
print("GRID_TREE_RESERVATION_PASS named startup markers, live tree, stale/dead cleanup")
