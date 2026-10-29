package.path = "scripts/vscripts/?.lua;" .. package.path
GetMapName = function() return "template_map" end
DOTA_TEAM_GOODGUYS, DOTA_UNIT_TARGET_TEAM_BOTH = 2, 3
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 0, 0
DOTA_UNIT_ORDER_MOVE_TO_POSITION, DOTA_UNIT_ORDER_CAST_POSITION = 1, 5
local mt = {__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end}
mt.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__mul=function(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
mt.__index={Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end,
    Normalized=function(v) local d=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z);return Vector(v.x/d,v.y/d,v.z/d) end}
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z or 0},mt) end
package.loaded["systems/match_setup_service"] = {get_mode=function() return "rich" end}
package.loaded["systems/player_context_service"] = {slot=function(id)
    return {slot_id=({"east","south","west","north"})[id+1]}
end}
local tasks = {}
package.loaded["core/scheduler"] = {cancel=function(name) tasks[name]=nil end,
    every=function(_,fn,name) tasks[name]=fn end}

-- Keep the real generated map rectangles, marker names and placement modules.
-- The engine fixture supplies high platforms, connecting low roads and two
-- terrain holes inside a rectangle, independently of navigation blockers.
local config = require("config/mode_spawn_config").modes.rich
assert(config.build_ground_height==256 and config.build_ground_height_tolerance==16,
    "rich authored membership must use the native platform height")
local centers, markers, recovery = {}, {}, {}
local function inside(b,p)
    return p.x>=b.min_x and p.x<b.max_x and p.y>=b.min_y and p.y<b.max_y
end
for id=0,3 do
    local b=config.player_bounds[id]
    centers[id]=Vector(math.floor((b.min_x+b.max_x)/128)*64,
        math.floor((b.min_y+b.max_y)/128)*64,256)
    markers[config.player_markers[id]]=centers[id]
    recovery[id]=Vector(centers[id].x+384,centers[id].y+384,256)
end
local b=config.player_bounds[0]
local low={min_x=b.min_x+256,max_x=b.min_x+512,min_y=b.min_y+256,max_y=b.min_y+512}
local cliff={min_x=b.min_x+640,max_x=b.min_x+896,min_y=b.min_y+256,max_y=b.min_y+512}
markers[config.center_marker]=Vector(-2816,-9984,128)
local blocked, trees, units, slope, reachable = true, false, {}, false, true
local function height(p)
    if inside(low,p) then return 128 end
    if inside(cliff,p) then return 512 end
    for id=0,3 do if inside(config.player_bounds[id],p) then
        if slope and math.abs(p.x-centers[0].x)<128 and math.abs(p.y-centers[0].y)<128 then
            return p.x<centers[0].x+32 and 256 or 384
        end
        return 256
    end end
    return 128
end
GetGroundHeight=function(p) return height(p) end
GetGroundPosition=function(p) return Vector(p.x,p.y,height(p)) end
GridNav={IsTraversable=function() return true end,
    IsBlocked=function(_,p)
        if not blocked then return false end
        for id=0,3 do
            if math.abs(p.x-recovery[id].x)<=128 and math.abs(p.y-recovery[id].y)<=128 then return true end
        end
        return false
    end,
    IsNearbyTree=function() return trees end,
    CanFindPath=function() return reachable end}
FindUnitsInRadius=function() return units end
Entities={FindByName=function(_,_,name)
    local p=markers[name]
    return p and {IsNull=function() return false end,GetAbsOrigin=function() return p end}
end}
local regions=require("systems/rich_region_service")
local grid=require("systems/grid_placement_system")
local work=require("systems/builder_work_position_service")
local bus,events=require("core/event_bus"),require("core/events")
bus.reset();grid.init();regions.init()
for id=0,3 do assert(regions.region(id)) end -- cache while recovery tiles are blocked
local function place(p,owner)
    return grid._can_place_for_test({player_id=owner or 0,position=p,footprint={x=4,y=4}})
end
for owner=0,3 do for court=0,3 do
    local r=place(centers[court],owner)
    assert(r.ok and #r.cells==16,"all owners must place a complete wall on every court: "..tostring(r.error))
    local blocked_result=place(recovery[court],owner)
    assert(not blocked_result.ok and blocked_result.error=="terrain_blocked",
        "temporary native blockers must continue to reject placement")
end end
blocked=false
for owner=0,3 do for court=0,3 do
    assert(place(recovery[court],owner).ok,
        "removing a temporary obstacle must restore every owner's build access without region reinit")
end end

trees=true;assert(place(centers[1]).error=="tree_blocked");trees=false
units={{IsNull=function() return false end,IsAlive=function() return true end,
    entindex=function() return 501 end,GetAbsOrigin=function() return centers[1] end,
    GetHullRadius=function() return 32 end}}
assert(place(centers[1]).error=="unit_blocked");units={}
local occupied=place(centers[1])
local reservation={grid_x=occupied.grid_x,grid_y=occupied.grid_y,footprint={x=4,y=4},entindex=702}
assert(bus.request(events.GRID_OCCUPY_REQUEST,reservation))
assert(place(centers[1]).error=="build_cell_occupied","shared ownership must never bypass a reserved footprint")
assert(bus.request(events.GRID_RELEASE_REQUEST,reservation));assert(place(centers[1]).ok)
slope=true;assert(not place(centers[0]).ok,"fresh terrain changes cannot bypass the exact slope check");slope=false
assert(not place(Vector((low.min_x+low.max_x)/2,(low.min_y+low.max_y)/2,128)).ok,
    "a low-road hole inside a court rectangle is not a platform")
assert(not place(Vector((cliff.min_x+cliff.max_x)/2,(cliff.min_y+cliff.max_y)/2,512)).ok,
    "a high cliff inside a court rectangle is not a platform")
assert(not place(Vector(low.min_x,(low.min_y+low.max_y)/2,256)).ok,
    "every cell of a footprint crossing high and low terrain must be checked")
assert(not place(Vector(b.max_x-64,centers[0].y,256)).ok,"the whole 4x4 wall must stay on one platform")
local road=markers[config.center_marker]
assert(regions.validate_position(0,road) and not place(road).ok,"connecting roads allow movement but never walls")
local outside=Vector(config.bounds.max_x+64,config.bounds.max_y+64,256)
assert(not regions.validate_position(0,outside) and not place(outside).ok,"other modes remain inaccessible")

local builders={}
for owner=0,3 do
    local unit={survival_builder_id="default_builder",survival_player_id=owner,position=centers[owner],stops=0}
    function unit:IsNull() return false end
    function unit:IsAlive() return true end
    function unit:GetAbsOrigin() return self.position end
    function unit:SetOrigin(p) self.position=p end
    function unit:Stop() self.stops=self.stops+1 end
    function unit:GetHullRadius() return 0 end
    function unit:GetTeamNumber() return 2 end
    assert(regions.attach_builder(owner,unit));builders[owner]=unit
end
for owner=0,3 do for court=0,3 do
    local unit,p=builders[owner],centers[court]
    for _,order in ipairs({DOTA_UNIT_ORDER_MOVE_TO_POSITION,DOTA_UNIT_ORDER_CAST_POSITION}) do
        assert(regions.validate_order({order_type=order,position_x=p.x,position_y=p.y,position_z=p.z},{unit}),
            "move and blink orders must reach another court")
    end
    unit.position=Vector(p.x,p.y,p.z)
    assert(regions.guard() and unit.stops==0 and unit.position.x==p.x and unit.position.y==p.y,
        "the guard must not undo a legal cross-court movement or blink")
    unit.position=centers[owner] -- construction starts at the owner's original court
    local working=assert(work.find(unit,{footprint={x=4,y=4},hull_radius=128},p),
        "each owner needs a usable construction point at the chosen court")
    assert(regions.validate_position(owner,working)
        and (math.abs(working.x-p.x)>128 or math.abs(working.y-p.y)>128))
    unit.position=Vector(p.x,p.y,p.z)
    local keep=unit.position
    assert(not regions.validate_order({order_type=DOTA_UNIT_ORDER_CAST_POSITION,
        position_x=outside.x,position_y=outside.y,position_z=outside.z},{unit}))
    unit.position=outside
    assert(regions.guard() and unit.stops==1 and unit.position.x==keep.x and unit.position.y==keep.y,
        "an actual out-of-mode displacement must still be rolled back")
    unit.stops=0
end end
reachable=false
assert(not work.find(builders[0],{footprint={x=4,y=4},hull_radius=128},centers[1]),
    "shared building never provides an unchecked construction point across a broken path")

-- Exercise the real ability as well as the order filter: a range-clamped blink
-- leaves the original court, remains inside rich bounds, then survives guard.
class=function(t) return t end
IsServer=function() return true end
UF_SUCCESS,UF_FAIL_CUSTOM,PATTACH_WORLDORIGIN=0,1,0
ParticleManager={CreateParticle=function() return 1 end,
    SetParticleControl=function() end,ReleaseParticleIndex=function() end}
ProjectileManager={ProjectileDodge=function() end}
FindClearSpaceForUnit=function() end
local ability=require("abilities/ability_survival_builder_blink")
local unit=builders[0]
unit.position=Vector(b.min_x+320,centers[0].y,256);unit.stops=0
assert(regions.guard())
local start=unit.position
local cursor=Vector(start.x-2000,start.y,128)
local spell=setmetatable({GetCaster=function() return unit end,
    GetCursorPosition=function() return cursor end,
    EndCooldown=function() error("a legal blink must not refund its cooldown") end},{__index=ability})
assert(spell:CastFilterResultLocation(cursor)==UF_SUCCESS)
assert(regions.validate_order({order_type=DOTA_UNIT_ORDER_CAST_POSITION,
    position_x=cursor.x,position_y=cursor.y,position_z=cursor.z},{unit}))
spell:OnSpellStart()
assert(unit.position.x==start.x-1000 and unit.position.y==start.y and unit.position.z==128,
    "native blink keeps its 1000 range and grounds its endpoint on the connecting road")
assert(not inside(b,unit.position) and regions.validate_position(0,unit.position))
assert(unit.stops==1 and regions.guard() and unit.stops==1 and unit.position.x==start.x-1000,
    "the guard must not pull the builder back after the actual blink ability teleports it")
print("RICH_SHARED_BUILDING_PASS: real four-court config x4 owners, 4x4 walls, move/cast/actual blink/guard, cross-court work points, temporary blocker recovery, live slope/nav/tree/unit/occupancy and mode/road/cliff/edge safety")
