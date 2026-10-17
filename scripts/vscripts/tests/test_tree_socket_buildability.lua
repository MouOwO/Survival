-- Real grid/tree integration: one permanent patch per court, dynamic backups.
package.path = "scripts/vscripts/?.lua;" .. package.path
local map_name=arg and arg[1] or "template_map"
GetMapName=function() return map_name end
DOTA_TEAM_GOODGUYS,DOTA_TEAM_BADGUYS=2,3
DOTA_UNIT_CAP_NO_ATTACK=0
DOTA_UNIT_TARGET_TEAM_BOTH=3
DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC,DOTA_UNIT_TARGET_BUILDING=1,2,4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE,FIND_ANY_ORDER=0,0
local vector_mt={__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vector_mt) end
GetGroundHeight=function() return 384 end
GetGroundPosition=function(p) return Vector(p.x,p.y,384) end
local nav_queries,unit_queries=0,0
GridNav={IsTraversable=function() nav_queries=nav_queries+1;return true end,
    IsBlocked=function() return false end,IsNearbyTree=function() return false end}
FindUnitsInRadius=function() unit_queries=unit_queries+1;return {} end
Entities={FindByName=function() return nil end,
    FindAllByClassname=function() error("tree socket placement must not scan all entities") end}
GameRules={GetGameTime=function() return 0 end}
package.loaded["core/particle_manager"]={}
package.loaded["core/modifier_registry"]={ensure=function() end}
package.loaded["systems/harvest_feedback_service"]={reset=function() end}
package.loaded["systems/rogue_effect_state_service"]={numeric=function() return 0 end}
local created,entities={},{}
local function unit(id,position)
    local u={id=id,position=position}
    function u:IsNull() return self.removed==true end
    function u:IsAlive() return not self.removed end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.position end
    function u:SetAbsOrigin(p) self.position=p end
    function u:HasModifier() return false end
    function u:SetBaseMaxHealth(h) self.max=h end
    function u:SetMaxHealth(h) self.max=h end
    function u:SetHealth(h) self.health=h end
    for _,method in ipairs({"SetModel","SetOriginalModel","SetModelScale",
        "SetAttackCapability","SetPhysicalArmorBaseValue"}) do u[method]=function() end end
    entities[id]=u
    return u
end
CreateUnitByName=function(_,position)
    local tree=unit(100+#created,position)
    created[#created+1]=tree
    return tree
end
EntIndexToHScript=function(id) return entities[id] end
UTIL_Remove=function(u) u.removed=true end
local bus=require("core/event_bus")
local events=require("core/events")
local grid=require("systems/grid_placement_system")
local trees=require("systems/tree_system")
local config=require("config/tree_config")
local function reset()
    bus.reset();grid.init();trees.init()
    created,entities={},{}
end
local function place(point)
    return bus.request(events.GRID_CAN_PLACE_REQUEST,{
        position=Vector(point.x,point.y,384),footprint=config.footprint,team=2})
end
local function decode(encoded)
    local fields={}
    for field in encoded:gmatch("[^|]+") do fields[#fields+1]=field end
    assert(fields[1]=="3" and tonumber(fields[2])==64)
    local width,height=tonumber(fields[5]),tonumber(fields[6])
    local result={}
    for index=0,width*height-1 do
        local packed=tonumber(fields[8]:sub(math.floor(index/2)+1,math.floor(index/2)+1),16)
        result[(tonumber(fields[3])+math.floor(index/height))..":"
            ..(tonumber(fields[4])+index%height)]=math.floor(packed/(index%2==0 and 1 or 4))%4
    end
    return result
end
local function preview(points,cache)
    return decode(grid.preview_area({position=Vector(points[1].x,points[1].y,384),
        team=2,terrain_cache=cache}))
end
local function assert_preview(cells,point,expected)
    local reserved=trees._tree_grid_for_test(point)
    for x=reserved.grid_x,reserved.grid_x+1 do
        for y=reserved.grid_y,reserved.grid_y+1 do
            assert(cells[x..":"..y]==expected,
                "all four cells of a tree patch must match exact placement and preview")
        end
    end
end
local function build(player_id,point)
    bus.emit(events.BUILDING_CREATED,{player_id=player_id,building_id="main_city",
        unit=unit(1000+player_id,Vector(point.x,point.y,384))})
end

reset()
local court_count,occupied_count=0,0
for _,column in pairs(grid._occupied_for_test()) do
    for _ in pairs(column) do occupied_count=occupied_count+1 end
end
assert(occupied_count==16,"four courts reserve one 2x2 patch each, not four patches")
for _,points in pairs(config.spawn_regions) do
    court_count=court_count+1
    local cells=preview(points,{})
    for index,point in ipairs(points) do
        local result=place(point)
        assert(result and result.ok==(index~=1),
            "only the primary patch is forbidden; three empty backups remain buildable")
        assert_preview(cells,point,index==1 and 1 or 2)
    end
end
assert(court_count==4,"all four rotated construction courts obey the same reservation rule")

local points=config.spawn_regions.northeast
local cache={}
preview(points,cache)
local before_nav,before_units=nav_queries,unit_queries
build(0,points[1]);build(1,points[1])
assert(#created==2,"players sharing a court still receive independent trees")
assert(created[2].position.x==points[2].x and created[2].position.y==points[2].y)
assert(nav_queries==before_nav and unit_queries==before_units,
    "fixed socket allocation adds no navigation search or spatial unit query")
assert(not place(points[2]).ok,"an actual backup tree occupies its registered footprint")
assert_preview(preview(points,cache),points[2],1)
assert(place(points[3]).ok and place(points[4]).ok,"unused backups remain available")

bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
assert(created[2].removed and place(points[2]).ok,"backup tree removal releases buildable ground")
assert_preview(preview(points,cache),points[2],2)
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0})
assert(not place(points[1]).ok,"the primary patch stays reserved after its tree leaves")
assert_preview(preview(points,cache),points[1],1)

-- Buildings can use a released backup. Later personal trees skip it, and
-- duplicate disconnect messages must not erase that newly built footprint.
local reserved=trees._tree_grid_for_test(points[2])
local building=unit(900,Vector(points[2].x,points[2].y,384))
building.survival_is_building=true
assert(bus.request(events.GRID_OCCUPY_REQUEST,{grid_x=reserved.grid_x,grid_y=reserved.grid_y,
    footprint=reserved.footprint,entindex=building:entindex()}))
bus.emit(events.PLAYER_DISCONNECTED,{player_id=1})
assert(not place(points[2]).ok,"duplicate disconnect preserves a subsequent building")
build(0,points[1]);build(1,points[1])
assert(#created==4 and created[4].position.x==points[3].x
    and created[4].position.y==points[3].y,"tree creation skips a building on a backup")
assert_preview(preview(points,cache),points[2],1)
assert_preview(preview(points,cache),points[3],1)
assert_preview(preview(points,cache),points[4],2)
print("TREE_SOCKET_BUILDABILITY_PASS map="..map_name..": four courts, one primary patch each, real placement/preview, dynamic backups, safe building reuse and no spawn-time scans")
