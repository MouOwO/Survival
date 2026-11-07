-- Actual resource authority -> projection -> HUD service -> production wire.
-- Only native handles, transport sink and time/scheduler are deterministic seams.
-- These are call counts, not a native FPS or latency benchmark.
package.path="scripts/vscripts/?.lua;"..package.path
package.loaded["config/test_access"]={enabled=false}
local bus=require("core/event_bus")
local events=require("core/events")
local lookup=require("config/generated/ui_static_catalog_lookup")
local wire=require("ui/compact_wire")
local schema=assert(wire.compile_lookup(lookup,1))
local F=lookup.field_by_name
local errors={}
local output=print
print=function(message,...)
    if tostring(message):find("[EventBus] handler error",1,true) then errors[#errors+1]=message
    else output(message,...) end
end
local checks=0
local function check(value,why) assert(value,why);checks=checks+1 end
local function fixture()
    bus.reset()
    local f={time=0,tasks={},sends={},players={},bound={},opened={},builds=0,
        slots=0,installs=0,building_queries=0,wave={},legacy=0,revision=826}
    for id=0,3 do f.players[id]={id=id};f.bound[id]=true;f.opened[id]=true;f.wave[id]=0 end
    GameRules={GetGameTime=function()return f.time end}
    DOTA_MAX_TEAM_PLAYERS=64
    PlayerResource={IsValidPlayerID=function(_,id)f.slots=f.slots+1;return f.players[id]~=nil end,
        GetPlayer=function(_,id)return f.players[id]end,GetTeam=function()return 2 end}
    CustomGameEventManager={Send_ServerToPlayer=function()f.legacy=f.legacy+1 end}
    package.loaded["core/scheduler"]={after=function(delay,callback,id)
        assert(delay>=0);f.installs=f.installs+1
        f.tasks[id]={at=f.time+delay,callback=callback,id=id}
    end,cancel=function(id)f.tasks[id]=nil end,
    -- Authority's existing one-second income task is outside this display test.
    every=function(interval,callback,id)assert(id:match("^resource_income:"));return id end}
    package.loaded["ui/compact_ui_transport"]={available=function()return true end,
        register_view=function(id,handler)assert(id==2);f.view=handler end,
        is_bound=function(id)return f.bound[id]end,is_open=function(id)return f.opened[id]end,
        publish=function(id,view,ops,settings)
            f.revision=f.revision+1
            local packets=assert(wire.encode(schema,{schema=1,schema_sha256=lookup.sha256,
                session=1,epoch=1,view=view},f.revision,ops,settings))
            for _,packet in ipairs(packets) do assert(#packet.d+25<=50,"native frame budget") end
            local row={id=id,time=f.time,ops=ops,packets=#packets}
            f.sends[#f.sends+1]=row
            if f.hook then local hook=f.hook;f.hook=nil;hook()end
            return f.revision
        end}
    package.loaded["ui/boss_warning_ui_service"]={init=function()end}
    package.loaded["systems/player_context_service"]={is_defeated=function()return false end}
    package.loaded["systems/gameplay_phase_guard"]={post_clear_frozen=function()return false end}
    bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()
        return {ok=true,totals={initial_wood=10000,initial_gold=1000,initial_population_cap=20}}
    end)
    bus.handle_request(events.WAVE_STATE_GET_REQUEST,function(p)
        f.builds=f.builds+1
        return {ok=true,player_id=p.player_id,alive=f.wave[p.player_id]}
    end)
    bus.handle_request("archive.challenge_state",function()return {}end)
    bus.handle_request(events.BUILDING_LIST_REQUEST,function()
        f.building_queries=f.building_queries+1;return {buildings={}}
    end)
    f.resources=dofile("scripts/vscripts/systems/resource_system.lua");f.resources.init()
    f.projection=dofile("scripts/vscripts/ui/ui_projection.lua");f.projection.init()
    f.service=dofile("scripts/vscripts/ui/ui_snapshot_service.lua");f.service.init()
    function f.get(id)return assert(bus.request(events.RESOURCE_GET_REQUEST,{player_id=id or 0}))end
    function f.add(id,wood,gold,reason,cap)
        local result=bus.request(events.RESOURCE_ADD_REQUEST,{player_id=id or 0,wood=wood or 0,
            gold=gold or 0,reason=reason or "lumberjack_hit",max_population=cap})
        assert(result and result.ok);return result.snapshot
    end
    function f.spend(id,amount)
        local result=bus.request(events.RESOURCE_TRY_SPEND_REQUEST,
            {player_id=id or 0,wood=amount,reason="shop_purchase"})
        assert(result and result.ok);return result.snapshot
    end
    function f.advance(target)
        assert(target>=f.time)
        while true do
            local next_task
            for _,task in pairs(f.tasks) do
                if task.at<=target and (not next_task or task.at<next_task.at
                    or task.at==next_task.at and task.id<next_task.id) then next_task=task end
            end
            if not next_task then break end
            f.time=math.max(f.time,next_task.at);f.tasks[next_task.id]=nil;next_task.callback()
        end
        f.time=target
    end
    function f.pending(id)return f.tasks["ui_passive_income:"..tostring(id or 0)]end
    function f.sent_value(name,id)
        for i=#f.sends,1,-1 do if f.sends[i].id==(id or 0) then
            for _,op in ipairs(f.sends[i].ops)do if op.field==F[name] then return op.value end end
        end end
    end
    for id=0,3 do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id})end
    f.advance(0)
    f.sends={};f.builds=0;f.installs=0
    assert(next(f.tasks)==nil)
    return f
end

do
    local f=fixture();f.advance(1)
    f.add(0,1);check(#f.sends==1 and f.sent_value("wood")==10001,"idle leading edge is immediate")
    f.advance(1.05);f.add(0,1);local task=assert(f.pending())
    for i=2,8 do f.advance(1+i*.05);f.add(0,1)end
    check(f.get().wood==10009 and #f.sends==1,"authority commits every hit before deferred display")
    check(f.pending()==task and task.at==1.5 and f.installs==1,"one fixed deadline; never debounce/starve")
    f.advance(1.5)
    check(#f.sends==2 and f.sent_value("wood")==10009 and not f.pending(),"stopping still delivers final balance")
    local builds,sends,installs=f.builds,#f.sends,f.installs
    for i=1,1000 do f.time=2+i*.001;f.add(0,0,0)end
    check(f.builds==builds and #f.sends==sends and f.installs==installs,"1000 equal passive states: zero builds, timers or sends")
    f.advance(100)
    check(next(f.tasks)==nil and f.builds==builds,"idle has no polling/build")
end

do
    local f=fixture();f.advance(1);f.add(0,1)
    f.advance(1.1);f.add(0,3);local stale=assert(f.pending()).callback
    local count=#f.sends;local clock=f.time
    f.spend(0,10)
    check(#f.sends==count+1 and f.sent_value("wood")==9994 and f.time==clock,"paused spending sends immediately and includes pending income")
    check(not f.pending(),"spending cancels passive deadline")
    stale();check(#f.sends==count+1,"retired trailing callback cannot resend")
    for _,reason in ipairs({"shop_refund","lottery_reward","monster_reward:boss","unknown"})do
        count=#f.sends;f.add(0,2,0,reason)
        check(#f.sends==count+1 and not f.pending(),reason.." remains immediate without advancing time")
    end
    count=#f.sends;f.add(0,-1,0,"lumberjack_hit")
    check(#f.sends==count+1,"decrement cannot claim passive eligibility")
    count=#f.sends;f.add(0,0,0,"profile_income",1)
    check(#f.sends==count+1 and f.sent_value("max_population")==21,"population capacity change remains immediate")
end

do
    local f=fixture();f.advance(1)
    f.hook=function()f.add(0,1)end
    f.add(0,1)
    check(#f.sends==1 and f.pending() and f.pending().at==1.5,"native callback reentry keeps second passive delta in trailing window")
    f.advance(1.5)
    check(#f.sends==2 and f.sent_value("wood")==10002,"reentrant final value is not lost")
    f.advance(2)
    f.hook=function()f.add(0,1);f.spend(0,3)end
    local count=#f.sends;f.add(0,1)
    check(#f.sends==count+2 and f.sent_value("wood")==10001 and not f.pending(),"reentrant urgent event upgrades passive pending immediately")
    bus.subscribe("test.resource_batch",function()f.add(0,1);f.spend(0,3)end)
    f.advance(3);count=#f.sends;bus.emit("test.resource_batch",{})
    check(#f.sends==count+1 and f.sent_value("wood")==9999,"same dispatch leading plus urgent coalesce to latest authoritative balance")
end

do
    local f=fixture();f.advance(1);f.add(0,1)
    f.advance(1.1);f.add(0,2)
    local old=assert(f.pending()).callback;local before=f.builds
    f.wave[0]=1;bus.emit(events.UI_DIRTY,{player_id=0});f.advance(f.time)
    check(f.builds==before+1 and f.sent_value("wood")==10003 and f.sent_value("wave_alive")==1,
        "wave change keeps its immediate path and piggybacks newest wallet")
    check(not f.pending(),"generic owner flush absorbs trailing income")
    local count=#f.sends;old();check(#f.sends==count,"absorbed trailing is inert")
    bus.emit(events.UI_DIRTY,{player_id=0});before=f.builds;f.spend(0,1);f.advance(f.time)
    check(f.builds==before+1,"resource immediate absorbs already queued personal generic dirty without second build")
end

do
    local f=fixture();f.advance(1)
    for id=0,3 do f.add(id,id+1)end
    local slots=f.slots
    f.advance(1.1);for id=0,3 do f.add(id,id+1)end
    check(f.slots-slots==4,"four changes consult four owners, never 64-slot rescan")
    for id=0,3 do check(f.pending(id)~=nil,"each owner has an independent deadline")end
    local close_old=f.pending(1).callback;f.opened[1]=false;f.view.close(1)
    local builds,count=f.builds,#f.sends
    f.add(1,20);close_old()
    check(f.builds==builds and #f.sends==count and not f.pending(1),"closed view cancels and builds/sends nothing")
    f.opened[1]=true;local ops=f.view.open(1);local reopened
    for _,op in ipairs(ops)do if op.field==F.wood then reopened=op.value end end
    check(reopened==10024,"reopen obtains latest authority")
    local old=f.pending(2).callback;f.service.publish_player(2);count=#f.sends;old()
    check(not f.pending(2) and #f.sends==count and f.sent_value("wood",2)==10006,"explicit resync absorbs only its owner")
    old=f.pending(3).callback;f.view.snapshot(3);count=#f.sends;old()
    check(not f.pending(3) and #f.sends==count,"transport full snapshot invalidates prior trailing callback")
    f.advance(1.5)
    check(f.sent_value("wood",0)==10002 and next(f.tasks)==nil,"remaining owner receives correct final balance")
end

do
    local f=fixture();f.advance(1);f.add(0,1);f.advance(1.1);f.add(0,1)
    local stale=f.pending().callback
    bus.emit(events.PLAYER_DISCONNECTED,{player_id=0});local count=#f.sends;stale()
    check(not f.pending() and #f.sends==count,"disconnect invalidates trailing")
    f.players[0]={id=0,new=true};f.view.open(0);f.advance(2);f.add(0,1);f.advance(2.1);f.add(0,1)
    stale=f.pending().callback;count=#f.sends;f.players[0]={id=0,newer=true};stale()
    check(#f.sends==count,"reused player handle cannot receive old callback")
    f.view.open(0);f.advance(3);f.add(0,1);f.advance(3.1);f.add(0,1)
    stale=f.pending().callback;count=#f.sends;bus.reset();f.service.init();stale()
    check(#f.sends==count and not f.pending(),"world generation cancels old callback")
end

do
    local f=fixture();f.bound[0]=false;f.advance(1)
    local builds=f.builds
    for _=1,1000 do f.add(0,1)end
    check(f.builds==builds and #f.sends==0 and f.legacy==0 and not f.pending(),"unnegotiated owner does not opt into legacy publishing")
    bus.emit(events.UI_SNAPSHOT_REQUESTED,{player_id=0})
    check(f.legacy==1,"explicit old-client subscription remains supported")
    f.add(0,1);check(f.legacy==1 and f.pending(),"legacy passive display also coalesces")
    f.spend(0,1);check(f.legacy==2 and not f.pending(),"legacy active spending remains immediate")
end

do
    -- At the observed revision width, a combined wood/gold transaction can
    -- still require two <=50B frames. Neither frame can commit partial values.
    local binding={schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=2}
    local receiver=assert(wire.new_receiver(schema,binding))
    local function ops(wood,gold)return {
        {record=lookup.by_key["hud:state"],field=F.wood,value=wood},
        {record=lookup.by_key["hud:state"],field=F.gold,value=gold}}
    end
    local initial=assert(wire.encode(schema,binding,834,ops(1370,2030),{full=true}))
    for _,packet in ipairs(initial)do
        local result=assert(receiver.accept(packet))
        if not result.pending then assert(receiver.commit(result))end
    end
    local packets=assert(wire.encode(schema,binding,835,ops(1372,2040),{}))
    check(#packets==2 and #packets[1].d+25<=50 and #packets[2].d+25<=50,"combined delta retains the production frame budget")
    check(assert(receiver.accept(packets[1])).pending and receiver.inspect().revision==834,"first fragment cannot expose partial balance")
    local transaction=assert(receiver.accept(packets[2]))
    check(#transaction.changes==2 and receiver.inspect().revision==834,"whole transaction waits for atomic commit")
    check(receiver.commit(transaction) and receiver.inspect().revision==835,"second fragment permits atomic final balance")
end

do
    -- Deterministic 60s workload inspired by the native window, NOT a native
    -- replay/FPS result: 9 wood changes/s +1 gold/s; then 0.5 wave changes/s.
    local function simulate(with_wave)
        local f=fixture();f.advance(1)
        for tick=0,599 do
            f.advance(1+tick/10)
            if tick%10~=9 then f.add(0,1)end
            if tick%10==0 then f.add(0,0,10,"profile_income")end
            if with_wave and tick%20==10 then
                f.wave[0]=f.wave[0]+1;bus.emit(events.UI_DIRTY,{player_id=0});f.advance(f.time)
            end
        end
        f.advance(61)
        local packets=0;for _,row in ipairs(f.sends)do packets=packets+row.packets end
        check(f.get().wood==10540 and f.get().gold==1600,"replay preserves authoritative sums")
        check(f.sent_value("wood")==10540 and f.sent_value("gold")==1600 and next(f.tasks)==nil,"replay publishes final values and goes idle")
        if not with_wave then
            for i=2,#f.sends do check(f.sends[i].time-f.sends[i-1].time>=.5-1e-8,"passive transactions separated by 500ms")end
            check(#f.sends<=121,"passive display transactions bounded near2/s, not frame count")
        end
        output(string.format("HUD_PASSIVE_SYNTHETIC wave=%s income_events=600 transactions=%d frames=%d builds=%d timers=%d",
            tostring(with_wave),#f.sends,packets,f.builds,f.installs))
    end
    simulate(false);simulate(true)
end

check(#errors==0,"no swallowed EventBus assertions/errors: "..tostring(errors[1]))
output("HUD_PASSIVE_INCOME_PASS: "..checks.." assertions; actual authority/projection/service/wire, passive500ms, paused urgent, reentry, owner/world invalidation; each frame<=50B")
