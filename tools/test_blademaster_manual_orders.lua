-- Actual clone lifecycle/guard and actual order filter. Reuse only the existing
-- attack-rate test's engine fixture prefix, never its assertions/test body.
-- Optional immutable baseline: lua this.lua <service.lua> <filter.lua>.
local fixture_file = assert(io.open("tools/test_blademaster_attack_rate.lua", "rb"))
local fixture_source = fixture_file:read("*a"); fixture_file:close()
local marker = 'local service = require("systems/blademaster_exclusive_service")'
local boundary = assert(fixture_source:find(marker, 1, true), "fixture service boundary missing")
assert(not fixture_source:find(marker, boundary + #marker, true), "fixture boundary duplicated")
local f = assert(loadstring(fixture_source:sub(1, boundary - 1) .. [[
return { bus=bus, events=events, jobs=jobs, heroes=heroes, snapshots=snapshots,
    created=created, entities=entities, orders=orders, source=source, unit=unit,
    enemies=function(values) enemies=values end }
]], "@blademaster_native_fixture_prefix"))()
local normal_print = print
print = function(...)
    local line = tostring(select(1, ...))
    if line:find("handler error", 1, true) or line:find("task failed", 1, true) then error(line) end
end
DOTA_UNIT_ORDER_MOVE_TO_TARGET = 2
DOTA_UNIT_ORDER_ATTACK_MOVE = 3
DOTA_UNIT_ORDER_HOLD_POSITION = 10
DOTA_UNIT_ORDER_STOP = 21
local MOVE, FOLLOW, ATTACK_MOVE = DOTA_UNIT_ORDER_MOVE_TO_POSITION, DOTA_UNIT_ORDER_MOVE_TO_TARGET, DOTA_UNIT_ORDER_ATTACK_MOVE
local ATTACK, HOLD, STOP = DOTA_UNIT_ORDER_ATTACK_TARGET, DOTA_UNIT_ORDER_HOLD_POSITION, DOTA_UNIT_ORDER_STOP
local frame, checks, scans, networks, scheduled, accepted_notifications = 1, 0, 0, 0, 0, 0
local busy_ticks, probe_before_native, same_frame_probes, same_frame_writes = 0, false, 0, 0
local attack_callbacks, callback_native_queries, in_attack_callback, random_offsets = 0, 0, false, 0
local ready, player_ready, rich_allowed, repair_claimed = true, true, true, false
GameRules.GetGameTime = function() return frame / 60 end
GameRules.GetFrameCount = function() return frame end
GetFrameCount = function() return frame end
RandomFloat = function() return 99 end
RandomVector = function() random_offsets=random_offsets+1;return Vector(73,41,0) end
EntIndexToHScript = function(index) return f.entities[tonumber(index)] end
CustomGameEventManager = { Send_ServerToPlayer = function() networks=networks+1 end,
    Send_ServerToAllClients = function() networks=networks+1 end }
local scheduler = package.loaded["core/scheduler"]
for _, name in ipairs({"after", "every"}) do
    local original = scheduler[name]
    scheduler[name] = function(...) scheduled=scheduled+1; return original(...) end
end
local native_find = FindUnitsInRadius
FindUnitsInRadius = function(...) scans=scans+1; return native_find(...) end
local destination = package.loaded["systems/destination_validation_service"]
destination.is_constrained_hero = function(unit) return unit and unit.survival_hero_id ~= nil end
destination.validate = function(position) return position ~= nil and position.x > -50000 end
package.loaded["systems/startup_loading_service"] = {
    is_ready=function()return ready end,is_player_ready=function()return player_ready end,
}
package.loaded["systems/rich_region_service"] = { validate_order=function() return rich_allowed end }
package.loaded["systems/repair_order_service"] = { process=function() return repair_claimed end }
package.loaded["systems/lumberjack_order_service"] = { process=function() end }
-- Keep real player_context owner checks; only defeated-state authority is a fixture.
local defeated = {}
package.loaded["systems/multiplayer_player_service"] = { is_defeated=function(id)return defeated[id]==true end }
local function load_actual(name, optional)
    if optional then package.preload[name] = function() return assert(loadfile(optional))() end end
    package.loaded[name] = nil; return require(name)
end
local service = load_actual("systems/blademaster_exclusive_service", arg and arg[1])
local filter = load_actual("systems/tree_attack_order_filter", arg and arg[2])
local on_order = service.on_player_order
local on_clone_attack = service.on_clone_attack
if on_clone_attack then
    service.on_clone_attack = function(...)
        attack_callbacks=attack_callbacks+1;in_attack_callback=true
        local result={pcall(on_clone_attack,...)}
        in_attack_callback=false;assert(result[1],result[2]);return unpack(result,2)
    end
end
if on_order then
    service.on_player_order = function(...)
        accepted_notifications=accepted_notifications+1
        local result=on_order(...)
        if probe_before_native then
            local count, query_count=#f.orders,scans
            service._test.guard_clone(select(3,...))
            same_frame_probes=same_frame_probes+1
            if #f.orders~=count or scans~=query_count then same_frame_writes=same_frame_writes+1 end
        end
        return result
    end
end
local function check(value, label) checks=checks+1;assert(value,label) end
local function equal(value, expected, label) check(value==expected,label..": "..tostring(value)) end
local function position_same(a,b,label)
    check(a and b and math.abs(a.x-b.x)<0.001 and math.abs(a.y-b.y)<0.001,label)
end
local function copy(p) return Vector(p.x,p.y,p.z) end
local function extra_native(unit)
    for _,name in ipairs({"IsNull","IsAlive","GetAbsOrigin","GetPlayerOwnerID","GetTeamNumber","entindex"}) do
        local original=unit[name]
        unit[name]=function(...)
            if in_attack_callback then callback_native_queries=callback_native_queries+1 end
            return original(...)
        end
    end
    function unit:GetCurrentOrderType() return self.current_order end
    function unit:IsMoving() return self.idle ~= true and self.current_order ~= HOLD end
    function unit:IsAttacking() return self.attack_target ~= nil end
    return unit
end
local function guard(id, count)
    for _=1,count or 1 do frame=frame+1;service._test.guard_clone(id) end
end
local function guard_busy(id,count) busy_ticks=busy_ticks+count;guard(id,count) end
local function issue(unit, kind, position, target, issuer, queued, others)
    local keys={order_type=kind,issuer_player_id_const=issuer==nil and unit.player_id or issuer,
        units={["0"]=unit:entindex()},queue=queued and 1 or 0}
    if position then keys.position_x,keys.position_y,keys.position_z=position.x,position.y,position.z end
    if target then keys.entindex_target=target:entindex() end
    for i,other in ipairs(others or {}) do keys.units[tostring(i)]=other:entindex() end
    local result=filter._filter_for_test(nil,keys)
    if result and not queued then
        -- Native execution happens AFTER the real filter authorizes the order.
        unit.current_order=kind;unit.idle=kind==STOP or kind==HOLD
        unit.attack_target=kind==ATTACK and target or nil
    end
    return result
end
local function settle(unit, point)
    unit.position=copy(point);unit.idle=true;unit.attack_target=nil;unit.current_order=STOP
    guard(unit.player_id)
end
local function enemy_at(point)
    local enemy=extra_native(f.unit(99));enemy.team=3;enemy.position=copy(point)
    return enemy
end
local record_sequence=100000
local function attack_record(unit,target,fields)
    local modifier=assert(unit:FindModifierByName("modifier_blademaster_clone"))
    record_sequence=record_sequence+1
    local params={attacker=unit,target=target,record=record_sequence}
    for key,value in pairs(fields or {}) do params[key]=value end
    modifier:OnAttackRecord(params)
    modifier:OnAttackRecordDestroy(params)
end
local function test_return_point(unit, point, label)
    unit.position=copy(point);unit.idle=true;unit.attack_target=nil
    local enemy=enemy_at(Vector(point.x+300,point.y,point.z));f.enemies({enemy})
    local n=#f.orders;guard(unit.player_id)
    equal(#f.orders,n+1,label.." acquires an enemy")
    equal(f.orders[#f.orders].TargetIndex,enemy.id,label.." attack identity")
    enemy.dead=true;f.enemies({});unit.attack_target=nil;unit.idle=true
    unit.position=Vector(point.x+500,point.y,point.z)
    n=#f.orders;guard(unit.player_id)
    equal(#f.orders,n+1,label.." returns after pursuit")
    position_same(f.orders[#f.orders].Position,point,label.." exact stationed point")
    settle(unit,point)
end
service.init()
local hero0,hero1=extra_native(f.source(0,10)),extra_native(f.source(1,3))
f.bus.emit(f.events.HERO_SKILL_CHANGED,{player_id=0});local clone=extra_native(f.created[#f.created])
f.bus.emit(f.events.HERO_SKILL_CHANGED,{player_id=1});local clone1=extra_native(f.created[#f.created])
local initial_timers=scheduled
equal(initial_timers,1,"only the existing growth scheduler initialized")
local point=Vector(1800,700,0)
probe_before_native=true
check(issue(clone,MOVE,point),"owner move accepted by real filter")
probe_before_native=false
clone.position=Vector(700,100,0)
local n,scan0=#f.orders,scans
guard_busy(0,100)
equal(#f.orders,n,"manual move must not be overwritten by guard")
equal(scans-scan0,0,"manual busy does not query enemies")
check(type(on_order)=="function","real filter/service manual interface is present")
equal(same_frame_probes,1,"guard probed before native order applies")
equal(same_frame_writes,0,"same-frame idle cannot complete or override new move")
settle(clone,point)
test_return_point(clone,point,"completed move")
-- The committed point is a copy, and subsequent walls do not move it.
local wall=extra_native(f.unit(0));wall.position=Vector(9000,9000,0)
f.bus.emit(f.events.BUILDING_CREATED,{player_id=0,building_id="wall",unit=wall})
wall.position=Vector(12000,12000,0)
f.bus.emit(f.events.BUILDING_CHANGED,{player_id=0,building_id="wall",unit=wall})
test_return_point(clone,point,"wall moved after manual station")

for _, kind in ipairs({ATTACK_MOVE,FOLLOW,ATTACK}) do
    local destination_point=Vector(point.x+2100,point.y+400,0)
    local target=enemy_at(destination_point)
    if kind==FOLLOW then target.team=2 end
    check(issue(clone,kind,destination_point,kind~=ATTACK_MOVE and target or nil),"manual order accepted "..kind)
    clone.position=Vector(point.x+400,point.y,0)
    if kind==ATTACK_MOVE then attack_record(clone,target);target.dead=true end
    n,scan0=#f.orders,scans;guard_busy(0,20)
    equal(#f.orders,n,"busy order preserved "..kind)
    equal(scans-scan0,0,"busy order no enemy scan "..kind)
    if kind==ATTACK then target.dead=true end
    settle(clone,destination_point);point=copy(destination_point)
    test_return_point(clone,point,"completed order "..kind)
end

-- Move can reach its destination and immediately engage without an idle frame.
local arrived=Vector(point.x+1800,point.y,0)
check(issue(clone,MOVE,arrived),"arrival move accepted")
clone.position=copy(arrived);clone.idle=false
clone.attack_target=enemy_at(Vector(arrived.x+100,arrived.y,0))
f.enemies({clone.attack_target});guard(0)
-- The acquired target dies after that manual-completion tick but before the
-- next guard tick. Its remembered identity must still cause a return leg.
clone.attack_target.dead=true;clone.attack_target=nil;f.enemies({});point=copy(arrived)
clone.position=Vector(point.x+500,point.y,0);clone.idle=true;n=#f.orders
guard(0)
equal(#f.orders,n+1,"target dying before following tick retains pursuit return")
position_same(f.orders[#f.orders].Position,point,"auto-acquired target returns to move destination, not chase end")
settle(clone,point)
test_return_point(clone,point,"move arrival without idle")

-- Native attack and death can both happen between the existing 1Hz guard
-- calls. Exercise the REAL modifier callback; no guard tick observes a target.
local function between_ticks(label,from_move)
    local anchor=from_move and Vector(point.x+1500,point.y+350,0) or copy(point)
    if from_move then check(issue(clone,MOVE,anchor),label.." move accepted") end
    clone.position=copy(anchor);clone.idle=false
    local victim=enemy_at(Vector(anchor.x+300,anchor.y,0));clone.attack_target=victim
    local calls=attack_callbacks;attack_record(clone,victim)
    equal(attack_callbacks,calls+1,label.." primary actual modifier notifies once")
    victim.dead=true;clone.attack_target=nil;clone.idle=true
    clone.position=Vector(anchor.x+500,anchor.y,0);f.enemies({})
    local before=#f.orders;guard(0)
    equal(#f.orders,before+1,label.." remembers native pursuit between ticks")
    position_same(f.orders[#f.orders].Position,anchor,label.." returns to committed anchor")
    settle(clone,anchor);point=copy(anchor)
end
between_ticks("move arrival/kill before any guard tick",true)
between_ticks("stationed native attack/kill between guard ticks",false)
for _,secondary in ipairs({{is_main_attack=false},{is_multishot_secondary=true},{no_attack_cooldown=1}}) do
    local target=enemy_at(Vector(point.x+100,point.y,0))
    local calls=attack_callbacks;attack_record(clone,target,secondary)
    equal(attack_callbacks,calls,"secondary actual modifier does not update guard")
end

check(issue(clone,HOLD),"hold accepted")
clone.idle=true;f.enemies({enemy_at(Vector(point.x+100,point.y,0))})
n,scan0=#f.orders,scans;guard_busy(0,100)
equal(#f.orders,n,"hold persists across idle ticks")
equal(scans-scan0,0,"hold has no automatic enemy scans")
f.enemies({});local stopped=Vector(point.x+1000,point.y+300,0);clone.position=copy(stopped)
check(issue(clone,STOP),"stop replaces hold")
n=#f.orders;service._test.guard_clone(0)
equal(#f.orders,n,"stop has no same-frame AI override")
point=copy(stopped);guard(0)
test_return_point(clone,point,"stop commits actual location")

-- A queued order must not override the native in-progress queue, even when the
-- first destination has already been reached. Commit only final actual idle.
local a,b=Vector(point.x+1000,point.y,0),Vector(point.x+2200,point.y+700,0)
check(issue(clone,MOVE,a),"queue first move")
check(issue(clone,MOVE,b,nil,nil,true),"queued second move")
local queued_victim=enemy_at(Vector(a.x+50,a.y,0))
attack_record(clone,queued_victim);queued_victim.dead=true
clone.position=copy(a);clone.idle=false;n,scan0=#f.orders,scans;guard_busy(0,50)
equal(#f.orders,n,"queued native chain is not overwritten")
equal(scans-scan0,0,"queued native chain has no automatic scans")
settle(clone,b);point=copy(b);test_return_point(clone,point,"queue final actual position")
check(issue(clone,MOVE,Vector(point.x+1000,point.y,0)),"queued-stop first move")
check(issue(clone,STOP,nil,nil,nil,true),"queued stop accepted")
clone.position=Vector(point.x+200,point.y,0);clone.idle=false;n=#f.orders;guard_busy(0,10)
equal(#f.orders,n,"queued stop cannot prematurely replace pending native move")
local queue_end=Vector(point.x+800,point.y,0);settle(clone,queue_end);point=copy(queue_end)
test_return_point(clone,point,"queued stop settles at native final position")

-- Every rejecting filter branch must run before notifying the clone service.
local function rejected_attempt(label, setup, cleanup, units, kind, target)
    local notified=accepted_notifications
    setup();local allowed=issue(clone,kind or MOVE,Vector(-60000,0,0),target,0,false,units);cleanup()
    equal(allowed,false,label.." rejected")
    equal(accepted_notifications,notified,label.." cannot mutate manual state")
    test_return_point(clone,point,label.." preserved station")
end
rejected_attempt("startup",function()ready=false end,function()ready=true end)
rejected_attempt("player startup",function()player_ready=false end,function()player_ready=true end)
rejected_attempt("defeated",function()defeated[0]=true end,function()defeated[0]=nil end)
rejected_attempt("rich boundary",function()rich_allowed=false end,function()rich_allowed=true end)
rejected_attempt("repair consumes order",function()repair_claimed=true end,function()repair_claimed=false end)
rejected_attempt("invalid destination",function()end,function()end)
rejected_attempt("mixed owner group",function()end,function()end,{clone1})
local tree=enemy_at(Vector(point.x+50,point.y,0));tree.GetUnitName=function()return "enemy_tree"end
rejected_attempt("illegal tree target",function()end,function()end,nil,ATTACK,tree)
local before=accepted_notifications
equal(issue(clone,MOVE,point,nil,1),false,"foreign issuer cannot move owner clone")
equal(accepted_notifications,before,"foreign filter rejection precedes notification")
-- Accepted engine orders do not establish player stations or suspend AI.
check(issue(clone,MOVE,Vector(point.x+4000,point.y,0),nil,-1),"engine order stays filter-compatible")
test_return_point(clone,point,"engine order cannot change station")
service.on_player_order({order_type=MOVE,position_x=99999,position_y=99999,queue=0},{clone},1)
test_return_point(clone,point,"direct foreign issuer cannot change station")

equal(scheduled,initial_timers,"manual orders/guard add zero timers")
equal(networks,0,"manual orders/guard send zero network messages")
-- A dead pending move is discarded; the last committed location survives.
local pending=Vector(point.x+5000,point.y+5000,0)
check(issue(clone,MOVE,pending),"pending command before death")
clone.position=Vector(point.x+200,point.y,0);clone.dead=true
f.bus.emit(f.events.ENGINE_ENTITY_KILLED,{victim=clone})
local respawn=assert(f.jobs["blademaster_clone_respawn:0"]);respawn()
local old=clone;clone=extra_native(f.created[#f.created])
check(clone~=old,"real clone lifecycle respawned")
position_same(clone.position,point,"respawn retains committed station, not unfinished destination")
equal(scheduled,initial_timers+1,"only pre-existing death respawn timer added")
test_return_point(clone,point,"respawn resumes at committed point")
for cycle=1,3 do
    clone.dead=true;f.bus.emit(f.events.ENGINE_ENTITY_KILLED,{victim=clone})
    assert(f.jobs["blademaster_clone_respawn:0"])()
    clone=extra_native(f.created[#f.created])
    position_same(clone.position,point,"nonzero random offset cannot drift respawn "..cycle)
    test_return_point(clone,point,"repeated respawn "..cycle)
end
equal(random_offsets,2,"nonzero random spawn offset runs only for initial two clones")
equal(scheduled,initial_timers+4,"four deaths use four existing respawn timers only")
-- A stale native handle, even if falsely marked alive again, cannot address the
-- current clone state. Filter's owner check alone is not sufficient here.
old.dead=false;old.null=false
service.on_player_order({order_type=MOVE,position_x=99999,position_y=99999,queue=0},{old},0)
test_return_point(clone,point,"old clone identity cannot change replacement")
local old_target=enemy_at(Vector(point.x+5000,point.y,0))
attack_record(old,old_target)
-- No current target or pursuit exists. If the old callback were accepted, it
-- would manufacture a return order after this external displacement.
local displaced=Vector(point.x+500,point.y,0)
clone.position=copy(displaced);clone.idle=true;clone.attack_target=nil;f.enemies({});n=#f.orders
guard(0)
equal(#f.orders,n,"old clone attack record cannot manufacture replacement pursuit")
test_return_point(clone,point,"old callback preserves committed manual station")
local owner1_point=copy(clone1.position)
test_return_point(clone1,owner1_point,"other player's independent default station")
equal(networks,0,"whole fixture has zero network sends")
equal(callback_native_queries,0,"new per-primary attack callback makes zero native queries")
normal_print("BLADEMASTER_MANUAL_ORDERS_PASS checks="..checks
    .." busy_ticks="..busy_ticks.." busy_enemy_queries=0 busy_AI_orders=0 manual_added_timers=0 custom_network_sends=0 attack_callbacks="..attack_callbacks
    .." callback_native_queries="..callback_native_queries.." random_offsets="..random_offsets
    .."; real service/filter/modifier, native boundary simulated")
