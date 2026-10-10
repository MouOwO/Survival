-- Real repair AI, formal building registry, order service and work-position
-- finder. Native building walls must be found without an automatic engine scan.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) t.__index=t; return t end
IsServer = function() return true end
FIND_UNITS_EVERYWHERE, FIND_CLOSEST, FIND_ANY_ORDER = -1, 1, 0
DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_TEAM_BOTH = 1, 3
DOTA_UNIT_TARGET_FLAG_INVULNERABLE, ACT_DOTA_ATTACK = 16, 1
DOTA_UNIT_ORDER_STOP, DOTA_UNIT_ORDER_MOVE_TO_TARGET = 1, 2
DOTA_UNIT_ORDER_ATTACK_TARGET, DOTA_UNIT_ORDER_MOVE_TO_POSITION = 3, 4
local mt={}
mt.__index={Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end}
mt.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
Vector=function(x,y,z) return setmetatable({x=x,y=y,z=z or 128},mt) end
local units, orders, scan_calls = {}, {}, 0
local function unit(id,kind,x)
    local u={id=id,kind=kind,position=Vector(x,0,128),health=500,max_health=1000,
        alive=true,idle=true,team=2,survival_player_id=0}
    function u:IsNull() return false end
    function u:IsAlive() return self.alive end
    function u:IsIdle() return self.idle end
    function u:entindex() return self.id end
    function u:GetAbsOrigin() return self.position end
    function u:GetTeamNumber() return self.team end
    function u:GetHullRadius() return self.kind==4 and 128 or 32 end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.max_health end
    function u:SetHealth(v) self.health=v end
    function u:HasModifier(name) return name=="modifier_building_under_construction" and self.constructing end
    function u:FaceTowards() end
    function u:StartGesture() self.gestures=(self.gestures or 0)+1 end
    function u:GetCurrentActiveAbility() return nil end
    function u:IsChanneling() return false end
    function u:SetModel(name) self.model=name end
    function u:GetModelName() error("repair decisions must not depend on visual model tags") end
    function u:FindModifierByName(name) if name=="modifier_repair_worker_ai" then return self.repair end end
    units[id]=u;return u
end
local wall=unit(2,4,0)
wall.survival_is_building=true
wall.survival_building_id="wall"
wall.survival_grid_footprint={x=4,y=4}
local bus,events=require('core/event_bus'),require('core/events')
bus.handle_request(events.BUILDING_LIST_REQUEST,function(payload)
    assert(payload.handles_only==true)
    return {buildings={{unit=wall,building_id='wall',player_id=0}}}
end)
local function contains(mask,flag) return mask%(flag*2)>=flag end
FindUnitsInRadius=function(team,origin,_,radius,team_filter,mask)
    if team_filter==DOTA_UNIT_TARGET_TEAM_FRIENDLY then scan_calls=scan_calls+1 end
    local result={}
    for _,u in pairs(units) do
        if u.alive and contains(mask,u.kind)
            and (team_filter==DOTA_UNIT_TARGET_TEAM_BOTH or team==u.team)
            and (radius==FIND_UNITS_EVERYWHERE or (u.position-origin):Length2D()<=radius) then
            result[#result+1]=u
        end
    end
    table.sort(result,function(a,b) return (a.position-origin):Length2D()<(b.position-origin):Length2D() end)
    return result
end
GetGroundHeight=function() return 128 end
local function occupied(p) return math.abs(p.x)<=128 and math.abs(p.y)<=128 end
GridNav={IsTraversable=function(_,p) return not occupied(p) end,
    IsBlocked=function(_,p) return occupied(p) end,CanFindPath=function() return true end}
package.loaded["systems/grid_placement_system"]={is_position_occupied=occupied}
EntIndexToHScript=function(id) return units[id] end
local service=require("systems/repair_order_service")
ExecuteOrderFromTable=function(order)
    orders[#orders+1]=order
    local u=units[order.UnitIndex]
    assert(not service.process({order_type=order.OrderType,units={["0"]=u.id}}), "internal order consumed repair target")
    u.idle=order.OrderType==DOTA_UNIT_ORDER_STOP
end
local repair=require("modifiers/modifier_repair_worker_ai")
for _,kind in ipairs({"builder","repairer"}) do
    orders, scan_calls = {}, 0
    wall.health, wall.survival_player_id, wall.constructing, wall.alive = 500, 0, false, true
    local worker=unit(1,2,-1000)
    worker.survival_builder_id=kind=="builder" and "default_builder" or nil
    worker.survival_worker_type=kind=="repairer" and "repairer" or nil
    worker:SetModel("models/heroes/ogre_magi/ogre_magi.vmdl")
    local m=setmetatable({},repair)
    worker.repair=m
    function m:GetParent() return worker end
    function m:StartIntervalThink(interval) assert(interval==0.1 or interval==1) end
    local function init(range)
        m:OnCreated({repair_max_health_pct_per_second=2,repair_range=200,detection_range=range})
    end
    -- Both finite and all-map detection use registered native building walls.
    init(99999)
    m:OnIntervalThink()
    assert(scan_calls==0,'Automatic repair must not call the engine unit search')
    assert(#orders==1 and orders[1].Position, kind.." failed to find native npc_dota_building wall")
    assert(not occupied(orders[1].Position), "repair must approach outside blocked footprint")
    assert((orders[1].Position-wall.position):Length2D()-worker:GetHullRadius()-wall:GetHullRadius()
        <=m.repair_range-16, "reachable work point still lies outside repair range")
    worker.position=orders[1].Position;worker.idle=true
    for tick=1,10 do m:OnIntervalThink() end
    assert(wall.health==520, "repair remains 2% of max health each second")
    worker:SetModel("models/heroes/warlock/warlock.vmdl")
    m:OnIntervalThink()
    assert(wall.health==522, "visual model replacement must not stop repair")

    init(nil)
    assert(m.detection_range==FIND_UNITS_EVERYWHERE, "default all-map scan was clamped to melee range")
    init(FIND_UNITS_EVERYWHERE)
    assert(m.detection_range==FIND_UNITS_EVERYWHERE, "explicit all-map sentinel was lost")
    init(32)
    assert(m.detection_range==200, "ordinary finite scan remains at least repair range")
    init(nil)
    worker.position=Vector(-1000,0,128);worker.idle=true;orders={}
    m:OnIntervalThink()
    assert(#orders==1 and orders[1].Position, "all-map search must find distant wall")

    worker.position=Vector(-100,0,128);worker.idle=true
    for _,field in ipairs({"survival_is_building","constructing","survival_player_id","alive","team"}) do
        local original=wall[field]
        wall[field]=({survival_is_building=false,constructing=true,survival_player_id=1,alive=false,team=3})[field]
        local before=wall.health
        m:OnIntervalThink()
        assert(wall.health==before, "invalid repair target accepted: "..field)
        wall[field]=original
    end
    worker.survival_build_task={constructing=true}
    local before, scans=wall.health,scan_calls
    m:OnIntervalThink()
    assert(wall.health==before and scan_calls==scans, "auto repair interrupted construction")
    worker.survival_build_task=nil
    wall.health=1000;worker.position=Vector(-1000,0,128);orders={}
    assert(service.process({order_type=DOTA_UNIT_ORDER_MOVE_TO_TARGET,entindex_target=2,units={["0"]=1}}))
    m:OnIntervalThink()
    worker.position=orders[#orders].Position
    m:OnIntervalThink()
    assert(worker.idle and m.manual_repair_target_entindex==2, "manual assignment must station at full wall")
    wall.health=990;m:OnIntervalThink();assert(wall.health==990, "99% must stay on standby")
    wall.health=970;m:OnIntervalThink();assert(wall.health==972)
    assert(not service.process({order_type=DOTA_UNIT_ORDER_MOVE_TO_POSITION,units={["0"]=1}}))
    assert(m.manual_repair_target_entindex==nil, "player move must release manual assignment")
end
print("WALL_REPAIR_DETECTION_PASS: registered native walls, builder/repairer, model swaps, map-wide candidates without engine scan, safe approach, repair rate, manual standby, ownership and construction")
