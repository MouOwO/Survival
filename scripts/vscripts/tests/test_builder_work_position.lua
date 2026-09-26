package.path = "scripts/vscripts/?.lua;" .. package.path
DOTA_TEAM_GOODGUYS = 2
DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC = 3, 1, 2
DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER = 4, 16, 0
local mt = {}; mt.__index = {Length2D = function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}
Vector = function(x,y,z) return setmetatable({x=x,y=y,z=z or 0}, mt) end
mt.__add = function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__sub = function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
package.loaded["systems/forbidden_region_service"] = {validate_building_footprint = function() return true end}
local bus, events = require("core/event_bus"), require("core/events")
local grid = require("systems/grid_placement_system")
local service = require("systems/builder_work_position_service")
local origin = Vector(0,0,128)
local caster = {position=origin}
function caster:IsNull() return false end
function caster:IsAlive() return true end
function caster:entindex() return 1 end
function caster:GetAbsOrigin() return self.position end
function caster:GetTeamNumber() return 2 end
function caster:GetHullRadius() return 0 end
local units, reachable, traversable, blocked, ground
local function reset()
    caster.position = origin
    units, reachable, traversable, blocked = {caster}, true, true, false
    ground = function() return 128 end
    GetGroundHeight = function(p) return ground(p) end
    GridNav = {IsTraversable = function() return traversable end,
        IsBlocked = function() return blocked end, IsNearbyTree = function() return false end,
        CanFindPath = function(_,a,b) assert(a == caster.position);return reachable end}
    FindUnitsInRadius = function() return units end
    EntIndexToHScript = nil
    bus.reset();grid.init()
end
local definition = {footprint={x=2,y=2},hull_radius=48}
reset()
local point = service.find(caster,definition,origin)
assert(point and math.abs(point.x)+math.abs(point.y)==96 and point.z==128,
    "choose nearest point outside the requested footprint")
assert(not service.ready(caster,definition,origin,point), "inside building must move first")
caster.position=point;assert(service.ready(caster,definition,origin,point))
reset();traversable=false;assert(service.find(caster,definition,origin)==nil)
reset();blocked=true;assert(service.find(caster,definition,origin)==nil)
reset();reachable=false;assert(service.find(caster,definition,origin)==nil,
    "same-height disconnected islands are not reachable work positions")
reset();GridNav.CanFindPath=function() error("navigation unavailable") end
assert(service.find(caster,definition,origin)==nil)
reset();ground=function(p) return p.x<0 and 0 or 128 end
point=service.find(caster,definition,origin)
assert(point and point.x>=16,"avoid traversable water and shore clearance around the builder")
reset();ground=function(p) if math.abs(p.x)+math.abs(p.y)>1 then return nil end return 128 end
assert(service.find(caster,definition,origin)==nil,"missing ground never produces an unchecked fallback")
reset()
bus.request(events.GRID_OCCUPY_REQUEST,{grid_x=-2,grid_y=-1,footprint={x=2,y=2},entindex=77})
point=service.find(caster,definition,origin)
assert(point and point.x>=0,"never select an already occupied building tile")
reset()
local obstacle={survival_is_building=true,survival_grid_footprint={x=2,y=2}}
function obstacle:IsNull() return false end
function obstacle:IsAlive() return true end
function obstacle:entindex() return 77 end
function obstacle:GetAbsOrigin() return Vector(-96,0,128) end
function obstacle:GetHullRadius() return 0 end
units[#units+1]=obstacle
point=service.find(caster,definition,origin)
assert(point and point.x>=0,"logical buildings remain excluded even with zero collision hull")
reset();point=service.find(caster,definition,origin);caster.position=point
units[#units+1]={IsNull=function()return false end,IsAlive=function()return true end,
    GetAbsOrigin=function()return point end,GetHullRadius=function()return 24 end}
assert(not service.ready(caster,definition,origin,point),"arrival is rechecked if another unit takes the work position")
reset()
local own = bus.request(events.GRID_CAN_PLACE_REQUEST,{position=origin,footprint=definition.footprint,
    team=2,ignore_entindex=1})
assert(own.ok)
units[#units+1]={IsNull=function()return false end,IsAlive=function()return true end,
    entindex=function()return 2 end,GetAbsOrigin=function()return origin end,GetHullRadius=function()return 0 end}
local other=bus.request(events.GRID_CAN_PLACE_REQUEST,{position=origin,footprint=definition.footprint,
    team=2,ignore_entindex=1})
assert(not other.ok and other.error=="unit_blocked","only the requesting builder receives the preview exemption")
class=function(t)return t end
MODIFIER_STATE_NO_UNIT_COLLISION=123;MODIFIER_ATTRIBUTE_PERMANENT=4
local phase=require("modifiers/modifier_survival_builder_phase")
local states=phase:CheckState();assert(states[MODIFIER_STATE_NO_UNIT_COLLISION])
local count=0;for _ in pairs(states)do count=count+1 end
assert(count==1 and not phase:IsPurgable() and not phase:RemoveOnDeath(),"permanent phase changes no ground/flying/pathing state")
print("BUILDER_WORK_POSITION_PASS: nearest safe reachable point, shore/terrain/occupancy checks, no fallback, arrival revalidation and ground-only phase")
-- Creating the real registered builder must install the phase modifier, not
-- merely define a modifier that is never applied to the live unit.
bus.reset()
local spawned_builder, links, made = nil, 0, 0
package.loaded["systems/player_context_service"] = {
    is_defeated = function() return false end,
    resolve_builder_spawn = function() return {position=Vector(0,0,128),slot_id="test",marker="test",source="test"} end,
    register_unit = function() return true end,
    unregister_unit = function() end,
}
LUA_MODIFIER_MOTION_NONE=0
LinkLuaModifier=function(name,path)
    assert(name=="modifier_survival_builder_phase" and path=="modifiers/modifier_survival_builder_phase")
    links=links+1
end
GameRules={GetGameTime=function()return 0 end}
PlayerResource={GetPlayer=function()return {} end}
CustomGameEventManager=nil;CustomNetTables=nil
FindClearSpaceForUnit=function()end
CreateUnitByName=function(name,position)
    made=made+1
    local unit={position=position,name=name,modifiers={}}
    function unit:IsNull()return false end
    function unit:entindex()return 50 end
    function unit:GetTeamNumber()return 2 end
    function unit:GetUnitName()return self.name end
    function unit:SetHullRadius(value)self.hull=value end
    function unit:FindModifierByName(name)return self.modifiers[name] end
    function unit:AddNewModifier(_,_,name)
        assert(self.hull==0,"phase is applied after removing the builder hull")
        self.modifiers[name]={};return self.modifiers[name]
    end
    setmetatable(unit,{__index=function(_,key)if key:match("^Set")then return function()end end end})
    spawned_builder=unit;return unit
end
local builder_service=require("systems/builder_service");builder_service.init()
local hero={IsNull=function()return false end}
bus.emit(events.HERO_READY,{player_id=0,hero=hero,team=2})
assert(spawned_builder and spawned_builder.modifiers.modifier_survival_builder_phase and links==1)
bus.emit(events.HERO_READY,{player_id=0,hero=hero,team=2})
assert(made==1,"duplicate hero-ready events do not create duplicate phased builders")
print("BUILDER_PHASE_CREATION_PASS: live creation installs registered phase modifier once")