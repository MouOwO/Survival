-- Real training service, event bus, altar configuration and room resolver.
-- Only native engine APIs, the wallet and technology projection are fixtures.
-- Optional baseline: lua this.lua path/to/immutable/training_room_service.lua
package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["config/test_access"] = {enabled=false}
local bus = require("core/event_bus")
local events = require("core/events")
local actions = require("config/generated/altar_actions")
local checks, cases = 0, 0
local function check(value, message) checks=checks+1; assert(value, message) end
local function eq(actual, expected, message)
    check(actual==expected, message..": "..tostring(actual).." expected "..tostring(expected))
end
local vector = {}
vector.__index = vector
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},vector) end
function vector.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vector.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector:Length2D() return math.sqrt(self.x*self.x+self.y*self.y) end
local function copy(v) return Vector(v.x,v.y,v.z) end
local function same(a,b,label) check(a and b and a.x==b.x and a.y==b.y and a.z==b.z,label) end
DOTA_TEAM_BADGUYS = 3

local function fixture(options)
    local f = options or {}
    f.gold=f.gold or 500000; f.rebirth=f.rebirth or 10
    f.jobs={}; f.created={}; f.removed={}; f.spends={}; f.notifications={}
    f.tech={active=false,multiplier=1}; f.tech_changes=0; f.marker_reads=0
    f.teleports=0; f.scheduled=0; f.home_calls=0; f.nav_calls=0;f.remove_self_calls=0
    bus.reset()
    local function unit(position)
        return {position=copy(position), IsNull=function(s)return s.removed==true end,
            IsAlive=function(s)return not s.dead end,
            GetAbsOrigin=function(s)return s.position end,
            SetOrigin=function(s,p)s.position=copy(p)end,
            RemoveSelf=function(s)f.remove_self_calls=f.remove_self_calls+1;s.removed=true;f.removed[#f.removed+1]=s end,
            GetPlayerOwnerID=function()return 0 end,GetTeamNumber=function()return 2 end,
            Stop=function()end}
    end
    f.hero=unit(Vector(100,200,0))
    local function marker(name,position) f.markers[name]=unit(position);return f.markers[name] end
    f.markers={}
    if not f.no_markers then
        if f.private ~= false then
            f.entry=marker("player_0_endless_cycle_sanctum_entry",Vector(5000,6000,0))
            marker("player_0_endless_cycle_sanctum_spawn_01",Vector(5100,6100,0))
        else f.entry=marker("endless_cycle_sanctum_entry",Vector(6000,7000,0)) end
        marker("challenge_04_entry",Vector(7000,8000,0))
    end
    Entities={FindByName=function(_,_,name) f.marker_reads=f.marker_reads+1;return f.markers[name] end}
    ProjectileManager={ProjectileDodge=function()end}
    FindClearSpaceForUnit=function(u,p)
        if f.target_failure=="FindClearSpaceForUnit"then error("fixture_clear_space")end
        u.position=copy(p)
    end
    UTIL_Remove=function(u)
        if u==f.remove_failure_target then
            if f.remove_failure=="throw"then error("fixture_UTIL_Remove")end
            if f.remove_failure=="false"then return false end
        end
        u.removed=true;f.removed[#f.removed+1]=u
    end
    CreateUnitByName=function(name,position)
        if f.spawn_failure=="throw"then error("fixture_CreateUnitByName")end
        if f.spawn_failure then return nil end
        local target=unit(position);target.name=name;f.created[#f.created+1]=target
        for _,method in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth","SetPhysicalArmorBaseValue","AddNewModifier"}) do
            target[method]=function()if f.target_failure==method then error("fixture_"..method)end end
        end
        if f.spawn_hook then f.spawn_hook() end
        return target
    end
    package.loaded["core/scheduler"]={
        every=function(interval,fn,id)
            eq(interval,1,"existing periodic cadence");f.scheduled=f.scheduled+1;f.jobs[id]=fn;return id
        end,
        cancel=function(id)f.jobs[id]=nil end,
    }
    package.loaded["systems/commerce_effects"]={owned=function(id,key)
        eq(id,0,"discount owner");eq(key,"growth_ring","discount entitlement");return f.ring==true
    end}
    package.loaded["systems/technology_stat_manager"]={set_training_room_state=function(id,active,multiplier,action)
        eq(id,0,"technology owner");f.tech_changes=f.tech_changes+1
        f.tech={active=active,multiplier=multiplier,action=action};return {ok=true}
    end}
    package.loaded["systems/hero_return_home_service"]={return_unit=function(hero,id)
        f.home_calls=f.home_calls+1;eq(hero,f.hero,"return exact hero");eq(id,0,"return exact owner");return {ok=true}
    end}
    package.loaded["systems/destination_validation_service"]={
        validate=function()f.nav_calls=f.nav_calls+1;return not f.nav_failure,"fixture_nav_failure" end,
        teleport=function(hero,position)
            f.teleports=f.teleports+1
            local failure=f.teleport_failure;f.teleport_failure=nil
            if failure then
                if failure=="throw" then hero.position=Vector(-111,-222,0);error("fixture_teleport_throw") end
                return false,"fixture_teleport_false"
            end
            hero.position=copy(position);return true,nil,hero.position
        end,
    }
    -- Keep the actual resolver: private-room first, old shared-room fallback.
    package.loaded["systems/player_room_locations"]=nil
    bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function()
        if f.hero_missing then return {ok=false}end
        return {ok=true,unit=f.hero}
    end)
    bus.handle_request(events.HERO_PROGRESSION_GET_REQUEST,function()return {ok=true,snapshot={rebirth_level=f.rebirth}}end)
    bus.handle_request(events.RESOURCE_GET_REQUEST,function()
        if f.resource_failure=="nil"then return nil end
        if f.resource_failure=="false"then return {ok=false,error="profile_not_loaded",gold=999999999}end
        return {player_id=0,gold=f.gold,wood=0}
    end)
    bus.handle_request(events.RESOURCE_CAN_SPEND_REQUEST,function(p)
        return {ok=not f.pay_failure and f.gold>=p.gold,error="gold_not_enough"}
    end)
    bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST,function(p)
        f.spends[#f.spends+1]=p.gold
        if f.pay_failure or f.gold<p.gold then return {ok=false,error="gold_not_enough"}end
        f.gold=f.gold-p.gold
        bus.emit(events.RESOURCE_CHANGED,{player_id=0,gold=f.gold,reason=p.reason})
        return {ok=true,snapshot={gold=f.gold}}
    end)
    bus.subscribe(events.UI_NOTIFICATION,function(p)f.notifications[#f.notifications+1]=p end)
    package.loaded["systems/training_room_service"]=nil
    if arg and arg[1] then f.service=assert(loadfile(arg[1]))()
    else f.service=require("systems/training_room_service") end
    f.service.init()
    function f:enter()return self.service.enter(0,"altar_endless_training")end
    function f:fee()return assert(self.jobs["training_room_fee:0"],"fee task exists")()end
    return f
end
local function run(name,fn) fn();cases=cases+1;print("CASE "..name.." PASS")end

run("fixed_configuration_unchanged",function()
    local a=actions.by_id.altar_endless_training
    eq(a.gold_cost,50000,"entry rule");eq(a.gold_cost_per_second,50000,"periodic rule")
    eq(a.required_rebirth_level,10,"unlock rule");eq(a.training_room_income_multiplier,15,"growth rule")
end)
for _,ring in ipairs({false,true})do
    run(ring and "discounted_boundary_and_first_tick"or"ordinary_boundary_and_first_tick",function()
        local fee=ring and 37500 or 50000
        local f=fixture({ring=ring,gold=fee*2-1})
        local r=f:enter();check(r and r.ok==false,"one below entry plus first tick rejected")
        check(tostring(r.error):find(tostring(fee*2),1,true),"error contains actual minimum")
        eq(#f.spends,0,"insufficient never charges");eq(#f.created,0,"insufficient never spawns")
        f.gold=fee*2;r=f:enter();check(r and r.ok==true,"exact entry plus first tick enters")
        eq(f.gold,fee,"entry charged exactly");eq(f.spends[1],fee,"actual discounted entry payload")
        eq(f.tech.multiplier,15,"training multiplier committed")
        eq(#f.spends,1,"first second not charged early");eq(f:fee(),true,"first fee continues")
        eq(f.gold,0,"first second exact debit");eq(f.spends[2],fee,"actual first tick payload")
    end)
end
run("resource_failures_and_rebirth",function()
    for _,mode in ipairs({"nil","false"})do
        local f=fixture({resource_failure=mode});local r=f:enter()
        check(r and r.ok==false,"resource unavailable rejected "..mode)
        eq(#f.created,0,"unavailable no target");eq(#f.spends,0,"unavailable no spend")
    end
    local f=fixture({rebirth=9});check(f:enter().ok==false,"nine rebirth rejected")
    eq(#f.spends,0,"rebirth no spend");eq(#f.created,0,"rebirth no target")
    f=fixture({hero_missing=true});check(f:enter().ok==false,"missing hero rejected")
end)
run("insufficient_before_missing_or_blocked_location",function()
    for _,opts in ipairs({{no_markers=true,gold=99999},{nav_failure=true,gold=99999}})do
        local f=fixture(opts);local r=f:enter()
        check(r and r.ok==false and tostring(r.error):find("100000",1,true),"funds error wins")
        eq(f.marker_reads,0,"insufficient does not query markers");eq(f.nav_calls,0,"insufficient no navigation")
    end
end)
run("private_shared_and_legacy_fallback_markers",function()
    local f=fixture();local r=f:enter();check(r.ok,"private enters")
    eq(r.marker_name,"player_0_endless_cycle_sanctum_entry","private marker selected")
    same(f.hero.position,f.entry.position,"private exact destination")
    f=fixture({private=false});r=f:enter();check(r.ok,"shared old map enters")
    eq(r.marker_name,"endless_cycle_sanctum_entry","shared marker selected")
    f=fixture({private=false});f.markers.endless_cycle_sanctum_entry=nil;r=f:enter()
    check(r.ok,"old fallback enters");eq(r.marker_name,"challenge_04_entry","legacy fallback selected")
end)

local failures={
    {"spawn_nil",function(f)f.spawn_failure=true end},
    {"spawn_throw",function(f)f.spawn_failure="throw"end},
    {"teleport_false",function(f)f.teleport_failure="false"end},
    {"teleport_throw",function(f)f.teleport_failure="throw"end},
    {"payment_rejected",function(f)f.pay_failure=true end},
}
for _,method in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth","SetPhysicalArmorBaseValue","AddNewModifier","FindClearSpaceForUnit"})do
    local selected=method
    failures[#failures+1]={"target_initialization_"..selected,function(f)f.target_failure=selected end}
end
for _,spec in ipairs(failures)do run("preserve_previous_room_"..spec[1],function()
    local f=fixture();check(f:enter().ok,"initial room entered")
    local old_target=f.created[1];local old_fee=f.jobs["training_room_fee:0"]
    local old_gold,old_pos,old_tech,old_changes=f.gold,copy(f.hero.position),f.tech,f.tech_changes
    f.entry.position=Vector(8500,9000,0);spec[2](f)
    local success,r=pcall(f.enter,f);check(success,"entry failure is returned, not thrown")
    check(r and r.ok==false,"transaction failure returned")
    eq(f.gold,old_gold,"failed replacement never debits")
    eq(old_target.removed,nil,"previous target retained")
    eq(f.jobs["training_room_fee:0"],old_fee,"previous fee identity retained")
    eq(f.tech,old_tech,"previous technology retained");eq(f.tech_changes,old_changes,"no failed tech transitions")
    same(f.hero.position,old_pos,"failed replacement restores previous position")
    for index=2,#f.created do check(f.created[index].removed==true,"new failed target cleaned")end
    eq(f.home_calls,0,"rollback does not invoke return-home exit effects")
    f.spawn_failure=nil;f.target_failure=nil;f.pay_failure=nil;f.teleport_failure=nil
    check(f:enter().ok,"failure releases entry guard for next request")
end)end

run("old_fee_identity_cannot_clear_new_room",function()
    local f=fixture();check(f:enter().ok,"first room")
    local old=f.jobs["training_room_fee:0"];check(f:enter().ok,"replacement room")
    local new=f.jobs["training_room_fee:0"];local target=f.created[2]
    local before=f.gold;eq(old(),false,"stale closure exits")
    eq(f.jobs["training_room_fee:0"],new,"stale closure preserves replacement timer")
    eq(target.removed,nil,"stale closure preserves replacement target")
    eq(f.tech.active,true,"stale closure preserves technology")
    eq(f.gold,before,"stale closure no debit")
end)
for _,mode in ipairs({"throw","false"})do run("old_target_cleanup_"..mode.."_does_not_abort_paid_entry",function()
    local f=fixture();check(f:enter().ok,"original room")
    local old_target,old_fee,before=f.created[1],f.jobs["training_room_fee:0"],f.gold
    f.remove_failure_target=old_target;f.remove_failure=mode
    check(f:enter().ok,"paid replacement commits despite cleanup "..mode)
    eq(f.gold,before-50000,"replacement debits only once")
    eq(#f.spends,2,"two entries have two payments")
    eq(f.remove_self_calls,1,"RemoveSelf fallback exactly once")
    eq(old_target.removed,true,"fallback removes original target")
    eq(f.created[2].removed,nil,"new target remains owned and live")
    check(f.jobs["training_room_fee:0"]~=old_fee,"new periodic task installed")
    eq(f.tech.active,true,"new training state committed")
    eq(f:fee(),true,"new periodic task remains functional")
    eq(f.gold,before-100000,"first tick makes exactly one further debit")
end)end
run("same_player_sync_reentry_only_one_transaction",function()
    local f=fixture();local nested
    bus.subscribe(events.RESOURCE_CHANGED,function()nested=f:enter()end)
    check(f:enter().ok,"outer entry succeeds")
    check(nested and nested.ok==false,"synchronous nested entry rejects")
    eq(#f.spends,1,"only one spend");eq(#f.created,1,"only one target")
    eq(f.scheduled,1,"only one fee task")
end)
run("preparation_sync_reentry_and_invalid_actor",function()
    local f=fixture();local nested
    f.spawn_hook=function()nested=f:enter()end
    check(f:enter().ok,"outer preparation succeeds")
    check(nested and nested.ok==false,"spawn edge cannot reenter")
    eq(#f.spends,1,"spawn reentry only one spend");eq(#f.created,1,"spawn reentry only one target")
    for _,id in ipairs({-1,0.5,"invalid"})do
        check(f.service.enter(id,"altar_endless_training").ok==false,"invalid player rejected")
    end
    check(f.service.enter(0,"missing_action").ok==false,"unknown action rejected")
    eq(#f.spends,1,"invalid requests do not debit")
end)
run("leave_death_and_periodic_shortfall_cleanup",function()
    for _,mode in ipairs({"leave","death","shortfall"})do
        local f=fixture();check(f:enter().ok,"room before "..mode)
        local target=f.created[1];local before=#f.spends
        if mode=="leave"then f.hero.position=Vector(99999,99999,0)
        elseif mode=="death"then f.hero.dead=true else f.gold=49999 end
        eq(f:fee(),false,"fee stops "..mode)
        eq(f.jobs["training_room_fee:0"],nil,"fee cancelled "..mode)
        eq(target.removed,true,"target removed "..mode);eq(f.tech.active,false,"growth reset "..mode)
        eq(#f.spends,before+(mode=="shortfall"and 1 or 0),"no extra charge for departure/death")
        eq(f.home_calls,mode=="shortfall"and 1 or 0,"only shortfall returns home")
    end
end)
print("TRAINING_ROOM_ENTRY_PASS cases="..cases.." checks="..checks.."; real service/event_bus/config/resolver; native and wallet simulated; no real transactions")
