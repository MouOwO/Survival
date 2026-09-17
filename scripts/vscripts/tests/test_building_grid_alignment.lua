package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local events = require("core/events")
local handlers = {}
package.loaded["core/event_bus"] = {
    handle_request = function(name, fn) handlers[name] = fn end,
    request = function(name, data) return handlers[name] and handlers[name](data) end,
    emit = function() end,
}
package.loaded["systems/forbidden_region_service"] = {
    validate_building_footprint = function() return true end,
}
local vec = {}
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z or 0},vec) end
vec.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
DOTA_TEAM_GOODGUYS=2; DOTA_UNIT_TARGET_TEAM_BOTH=3
DOTA_UNIT_TARGET_HERO=1; DOTA_UNIT_TARGET_BASIC=2; DOTA_UNIT_TARGET_BUILDING=4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE=8; FIND_ANY_ORDER=0
GetGroundHeight=function() return 0 end
GetGroundPosition=function(p) return p end
FindUnitsInRadius=function() return {} end
local tree
GridNav={IsTraversable=function() return true end,IsBlocked=function() return false end,
    IsNearbyTree=function(_,p,r) return tree and (p.x-tree.x)^2+(p.y-tree.y)^2<r*r or false end}
local grid=require("systems/grid_placement_system")
local geometry=require("core/building_grid_geometry")
local buildings=require("config/buildings_config")
grid.init()
local footprint=buildings.main_city.footprint
local function check(p) return handlers[events.GRID_CAN_PLACE_REQUEST]({position=p,footprint=footprint}) end
for _,n in ipairs({-129,-64,-32,-1,0,31,32,63,64,127}) do
    local result=check(Vector(n,n,0))
    assert(result.ok and #result.cells==4,"building must reserve exactly four cells")
    local again=check(result.world_position)
    assert(again.grid_x==result.grid_x and again.grid_y==result.grid_y,"re-snapping moved the building")
    assert(result.world_position.x==(result.grid_x+1)*64,"model is not centered over its footprint")
    local x,y=geometry.origin(result.world_position,footprint)
    assert(x==result.grid_x and y==result.grid_y,"recovery disagrees with placement")
end
for _,cells in ipairs({2,4}) do
    local _,world,origin=geometry.snap_axis(64,cells)
    assert(world==64 and origin==1-cells/2,"existing tower/wall snapping changed")
end
for _,cells in ipairs({3,5}) do
    local _,world,origin=geometry.snap_axis(64,cells)
    local _,again=geometry.snap_axis(world,cells)
    assert(world==96 and world==again and origin==1-math.floor(cells/2),
        "generic odd footprints lost their centered snapping")
end
tree=Vector(160,160,0)
assert(check(Vector(0,0,0)).ok,"tree outside the smaller footprint still blocks placement")
tree=Vector(32,32,0)
assert(not check(Vector(0,0,0)).ok,"tree inside the four-cell footprint was ignored")
tree=nil
local first=check(Vector(0,0,0))
handlers[events.GRID_OCCUPY_REQUEST]({grid_x=first.grid_x,grid_y=first.grid_y,footprint=footprint,entindex=77})
assert(not check(Vector(0,0,0)).ok,"overlapping building accepted")
assert(not check(Vector(64,0,0)).ok,"partly overlapping four-cell building accepted")
assert(check(Vector(128,0,0)).ok,"adjacent four-cell building still uses the old footprint")
local state={grid_x=first.grid_x,grid_y=first.grid_y,definition=buildings.main_city,team=2}
local unit={origin=first.world_position}
function unit:IsNull() return false end
function unit:entindex() return 77 end
function unit:Stop() end
function unit:FindModifierByName() end
function unit:RemoveModifierByName() end
function unit:AddNewModifier() end
function unit:GetAbsOrigin() return self.origin end
function unit:SetAbsOrigin(p) self.origin=p end
GameRules={GetGameModeEntity=function() return {SetContextThink=function() end} end}
local relocation=require("systems/building_relocation")
relocation.bind(function() return state end,function(s) return s end)
assert(relocation.move(unit,Vector(400,-200,0)))
local x,y=geometry.origin(unit.origin,footprint)
assert(state.grid_x==x and state.grid_y==y,"relocation drifted by a cell")
assert(check(Vector(0,0,0)).ok,"relocation left the old cells occupied")
assert(not check(unit.origin).ok,"relocation did not reserve the new cells")
handlers[events.GRID_RELEASE_REQUEST]({grid_x=x,grid_y=y,footprint=footprint,entindex=77})
assert(check(unit.origin).ok,"destruction did not release all four cells")

local router=require("ui/grid_placement_router")
router._build_profiles_for_test()
local proxy={}
function proxy:SetAngles(_,yaw) self.yaw=yaw end
function proxy:SetHullRadius(r) self.hull=r end
function proxy:SetModelScale(s) self.scale=s end
local count,wall_count=0,0
for _,profile in pairs(router._profiles_for_test()) do
    if profile.preview_model_name and profile.preview_model_name:find("survival_buildings",1,true) then
        local is_wall=profile.building_id=="wall"
        local expected_cells=is_wall and 4 or 2
        assert(profile.grid_footprint_x==expected_cells and profile.grid_footprint_y==expected_cells)
        router._prepare_preview_unit_for_test(proxy,profile)
        router._prepare_preview_unit_for_test(proxy,profile)
        assert(proxy.yaw==(is_wall and 180 or 0) and proxy.scale==1 and proxy.hull==0,"preview facing/scale drifted")
        if is_wall then wall_count=wall_count+1 else count=count+1 end
    end
end
assert(count==7 and wall_count==1)
print("BUILDING_GRID_ALIGNMENT_PASS four_cells trees adjacency relocation release south_preview=7 wall_4x4_preview=1")
