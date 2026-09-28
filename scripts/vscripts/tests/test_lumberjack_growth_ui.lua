-- Real growth manager/event consumers; engine transport and scheduling are controlled.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus,events=require("core/event_bus"),require("core/events")
local now,tasks,writes,errors=0,{},{},{}
local old_print=print
print=function(message,...)
    if tostring(message):find("[EventBus] handler error",1,true) then errors[#errors+1]=message
    else old_print(message,...) end
end
package.loaded["core/scheduler"]={
    after=function(delay,callback,id) assert(not tasks[id],"bounded pending callback");tasks[id]={at=now+delay,callback=callback} end,
    cancel=function(id) tasks[id]=nil end,
}
GameRules={GetGameTime=function() return now end}
CustomNetTables={SetTableValue=function(_,name,key,value) writes[#writes+1]={name=name,key=key,value=value} end}
CustomGameEventManager={RegisterListener=function() end}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end}
local manager=require("systems/technology_stat_manager")
local info=require("ui/game_info_service")
local combat=require("ui/combat_stats_ui_service")
local function reset()
    bus.reset();manager.init();info.init();combat.init()
    writes={}
end
local function hit(id,amount,section)
    local value,err=bus.request(events.TECHNOLOGY_STATS_GROWTH_ADD_REQUEST,{
        player_id=id,section=section or "lumberjack",field="attack",amount=amount,reason="test_growth"})
    assert(not err,err);assert(value.ok)
    return value
end
local function flush(at)
    now=at
    local due={};for id,task in pairs(tasks) do if task.at<=now then due[#due+1]=id end end
    for _,id in ipairs(due) do local task=tasks[id];tasks[id]=nil;task.callback() end
end
reset()
local scopes={}
bus.subscribe(events.TECHNOLOGY_STATS_CHANGED,function(p) scopes[#scopes+1]={p.changed_section,p.changed_field} end)
for i=1,200 do hit(0,0.25) end
for i=1,80 do hit(1,0.5) end
assert(manager.get(0).final.lumberjack.attack_flat==50 and manager.get(1).final.lumberjack.attack_flat==40)
assert(#writes==0,"growth presentation is coalesced")
local n=0;for _ in pairs(tasks) do n=n+1 end;assert(n==4,"two bounded UI jobs per player")
flush(0.099);assert(#writes==0)
flush(0.1);assert(#writes==4)
for _,row in ipairs(writes) do
    if row.name=="survival_combat_debug" then
        local expected=row.key=="player_0" and 50 or 40
        assert(row.value.technology_stats.final.lumberjack.attack_flat==expected,"flush reads latest authoritative total")
    end
end
assert(#scopes==280 and scopes[1][1]=="lumberjack" and scopes[1][2]=="attack")
writes={};hit(0,1,"hero");assert(#writes==2,"hero growth retains its synchronous notification")
assert(scopes[#scopes][1]=="hero")
hit(0,1);local stale={};for _,task in pairs(tasks) do stale[#stale+1]=task.callback end
reset();assert(next(tasks)==nil)
for _,callback in ipairs(stale) do callback() end
assert(#writes==0,"old session callbacks cannot publish into a new session")
hit(0,2);flush(0.2);assert(#writes==2)
assert(#errors==0,table.concat(errors,"\n"));print=old_print
print("LUMBERJACK_GROWTH_UI_PASS: 280 synchronous growth mutations, 4 UI writes, player isolation, latest totals, hero compatibility, stale callback cancellation")

-- Keep the real hero event handler, instrument only its expensive recalculation.
local hero=require("systems/hero_combat_stat_service")
local function upvalue(fn,wanted)
    for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end
        if name==wanted then return value,i end
    end
    error("missing upvalue "..wanted)
end
local handler=upvalue(hero.init,"on_technology_stats_changed")
local original,index=upvalue(handler,"recalculate")
local recalculations=0
debug.setupvalue(handler,index,function() recalculations=recalculations+1 end)
for i=1,200 do handler({player_id=0,changed_section="lumberjack",changed_field="attack"}) end
assert(recalculations==0,"wood growth must not recompute hero/equipment")
handler({player_id=0,changed_section="hero",changed_field="attack"})
handler({player_id=0,reason="research_completed"})
assert(recalculations==2,"hero growth and ordinary research still apply")
debug.setupvalue(handler,index,original)
print("LUMBERJACK_HERO_ISOLATION_PASS")
