-- Actual grid identity lookup, global order filter and repair AI lifecycle.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) t.__index=t; return t end
IsServer = function() return true end
MODIFIER_ATTRIBUTE_PERMANENT, ACT_DOTA_ATTACK = 1, 2
FIND_UNITS_EVERYWHERE, FIND_CLOSEST = -1, 0
DOTA_UNIT_TARGET_TEAM_FRIENDLY = 1
DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_BUILDING = 1, 2, 4
DOTA_UNIT_TARGET_FLAG_INVULNERABLE = 16
DOTA_UNIT_ORDER_MOVE_TO_POSITION, DOTA_UNIT_ORDER_MOVE_TO_TARGET = 1, 2
DOTA_UNIT_ORDER_ATTACK_MOVE, DOTA_UNIT_ORDER_ATTACK_TARGET, DOTA_UNIT_ORDER_STOP = 3, 4, 21
Vector = function(x,y,z) return {x=x,y=y,z=z or 0} end
local entities, pending, scans, paths = {}, {}, 0, 0
EntIndexToHScript = function(id) return entities[id] end
local function unit(id, building)
    local u={health=1000,max=1000,alive=true,idle=true,position=Vector(16,16),
        survival_is_building=building,survival_player_id=0,team=2,id=id}
    function u:IsNull() return self.null==true end
    function u:IsAlive() return self.alive end
    function u:entindex() return self.id end
    function u:GetTeamNumber() return self.team end
    function u:GetHealth() return self.health end
    function u:GetMaxHealth() return self.max end
    function u:SetHealth(h) self.health=h end
    function u:GetAbsOrigin() self.position_reads=(self.position_reads or 0)+1; return self.position end
    function u:GetHullRadius() return self.survival_is_building and 128 or 32 end
    function u:IsIdle() return self.idle end
    function u:HasModifier(name) return name=="modifier_building_under_construction" and self.constructing end
    function u:FindModifierByName(name) return name=="modifier_repair_worker_ai" and self.repair or nil end
    function u:FaceTowards() end
    function u:StartGesture() self.gestures=(self.gestures or 0)+1 end
    function u:GetModelName() error("model tags must not participate in repair") end
    entities[id]=u; return u
end
package.loaded["systems/tree_damage_rules"]={is_arrow_tower=function() return false end,is_tree=function() return false end}
package.loaded["systems/lumberjack_order_service"]={process=function() end}
package.loaded["systems/anti_air_rules"]={is_anti_air_tower=function() return false end}
package.loaded["systems/destination_validation_service"]={is_constrained_hero=function() return false end}
package.loaded["systems/player_context_service"]={is_defeated=function() return false end,owner_player_id=function(u) return u.survival_player_id end}
package.loaded["systems/startup_loading_service"]={is_ready=function() return true end,is_player_ready=function() return true end}
local grid=require("systems/grid_placement_system")
local cells=grid._occupied_for_test()
local wall=unit(2,true);wall.survival_building_id="wall"
local city=unit(3,true);city.survival_building_id="main_city"
local bus,events=require('core/event_bus'),require('core/events')
local list_reads=0
bus.handle_request(events.BUILDING_LIST_REQUEST,function(payload)
    assert(payload.handles_only==true);list_reads=list_reads+1
    return {buildings={{unit=wall,building_id='wall',player_id=0},{unit=city,building_id='main_city',player_id=0}}}
end)
cells[0]={[0]=2,[1]=2};cells[1]={[0]=3}
assert(grid.occupant_at_position(Vector(1,1))==2)
assert(grid.occupant_at_position(Vector(65,1))==3)
local service=require("systems/repair_order_service")
local filter=require("systems/tree_attack_order_filter")._filter_for_test
local definition=require("modifiers/modifier_repair_worker_ai")
package.loaded["systems/builder_work_position_service"]={find=function()
    paths=paths+1;return Vector(300,16)
end}
FindUnitsInRadius=function()
    scans=scans+1; return {wall,city}
end
ExecuteOrderFromTable=function(order)
    local u=entities[order.UnitIndex]
    u.idle=order.OrderType==DOTA_UNIT_ORDER_STOP
    -- Deliberately deliver engine orders after the issuing guard is gone.
    pending[#pending+1]={issuer_player_id_const=-1,order_type=order.OrderType,
        units={['0']=order.UnitIndex},position_x=order.Position and order.Position.x,
        position_y=order.Position and order.Position.y}
end
local function player_order(id,kind,target,x,y,issuer)
    return filter(nil,{issuer_player_id_const=issuer or 0,order_type=kind,
        entindex_target=target or -1,units={['0']=id},position_x=x,position_y=y})
end
local function flush()
    for _,order in ipairs(pending) do assert(filter(nil,order)==true,"server orders remain engine orders") end
    pending={}
end
for _,role in ipairs({"builder","repairer"}) do
    local worker=unit(1,false);worker.survival_builder_id=role=="builder" and "builder_io" or nil
    worker.survival_worker_type=role=="repairer" and role or nil
    local m=setmetatable({},definition);worker.repair=m
    function m:GetParent() return worker end
    function m:StartIntervalThink(interval) assert(interval==0.1 or interval==1);self.interval=interval end
    local function reset()
        m:OnCreated({repair_max_health_pct_per_second=2,repair_range=200})
        wall.health=1000;wall.alive=true;wall.survival_player_id=0;wall.constructing=false
        wall.team=2;worker.position=Vector(1000,16);worker.idle=true;worker.gestures=nil
        scans,paths,pending=0,0,{}
    end
    reset()
    assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_POSITION,nil,16,16)==false,
        role.." wall ground-click must be consumed as repair, not movement into a blocked center")
    assert(m.manual_repair_target_handle==wall)
    flush();assert(m.manual_repair_target_entindex==2,"deferred STOP must not erase the assignment")
    m:OnIntervalThink();flush()
    assert(paths==1 and m.manual_repair_target_entindex==2)
    for i=1,5 do m:OnIntervalThink();flush() end
    assert(paths==1 and scans==0,"approaching a manual wall does not search or replan each tick")
    worker.position=Vector(300,16);m:OnIntervalThink();flush()
    local read_count=wall.position_reads
    wall.health=990
    for i=1,20 do m:OnIntervalThink() end
    assert(wall.health==990 and scans==0 and not worker.gestures,"99% standby does not repair or search")
    assert(wall.position_reads==read_count,"standby skips range/path checks too")
    wall.health=980
    for i=1,10 do m:OnIntervalThink() end
    assert(wall.health==1000,"repair begun at 98% continues through the threshold to full")
    assert(worker.gestures<=5,"100ms decisions do not restart gestures on every tick")
    assert(scans==0,"active repair never rescans")
    assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_POSITION,nil,500,500)==true)
    assert(not m.manual_repair_target_entindex and not m.repair_target_handle,"real player move cancels work")
    assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_TARGET,3)==false,"other building target-click still repairs")
    assert(m.manual_repair_target_handle==city)
    assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_POSITION,nil,65,1)==true,"non-wall ground clicks keep native movement")
    for _,bad in ipairs({{field='survival_player_id',value=1},{field='alive',value=false},
        {field='constructing',value=true},{field='team',value=3}}) do
        local original=wall[bad.field];wall[bad.field]=bad.value
        assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_POSITION,nil,16,16)==true,"invalid/foreign wall is not repairable")
        assert(not m.manual_repair_target_entindex);wall[bad.field]=original
    end
    assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_POSITION,nil,0/0,1)==true)
    assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_POSITION,nil,16,16,1)==false,"global ownership gate still denies another player")
    assert(not m.manual_repair_target_entindex)
    assert(player_order(1,DOTA_UNIT_ORDER_MOVE_TO_TARGET,2)==false)
    local replacement=unit(2,true);replacement.survival_building_id='wall';replacement.health=500
    m:OnIntervalThink()
    assert(not m.manual_repair_target_entindex and replacement.health==500,"recycled entity index cannot inherit repair")
    entities[2]=wall
    reset();wall.health=900;city.health=1000
    m:OnIntervalThink();assert(scans==0 and paths==1)
    local seeded_reads=list_reads
    flush();assert(m.repair_target_handle==wall and not worker.idle)
    for i=1,5 do m:OnIntervalThink();flush() end
    assert(scans==0 and list_reads==seeded_reads,"moving to an automatic target retains it without a new unit or registry search")
    worker.position=Vector(300,16)
    for i=1,10 do m:OnIntervalThink() end
    assert(wall.health==920 and scans==0 and list_reads==seeded_reads,"2% per second is unchanged and cached repair continues while busy")
    reset();wall.max=7;wall.health=1;worker.position=Vector(300,16)
    for i=1,100 do m:OnIntervalThink() end
    assert(wall.health==2,"fractional healing is retained across 0.1 second ticks")
    wall.max=1000
end
assert(list_reads==1,'All builder/repairer instances share one lifecycle-maintained registry seed')
print("REPAIR_ORDER_LIFECYCLE_PASS: builder/repairer wall position orders, real grid/filter, ownership, deferred commands, cached approach/heal, 99% standby, full completion, heal rate, fractional amount and entity reuse")
