package.path = "scripts/vscripts/?.lua;" .. package.path
local function copy(v)
    if type(v) ~= "table" then return v end
    local r = {}; for k,x in pairs(v) do r[k]=copy(x) end; return r
end
local stats = require("config/generated/player_gameplay_stats")
local levels = require("config/generated/archive_map_levels")
local items = require("config/generated/archive_work_items")
assert(#levels.rows == 34 and #items.rows == 34)
assert(levels.rows[1].required_seconds == 3600 and levels.rows[34].required_seconds == 1112*3600)
assert(items.rows[1].cost == 600 and items.rows[34].cost == 24000)
for _, list in ipairs({levels.rows, items.rows}) do
    for _, item in ipairs(list) do
        assert(#item.effect_ids == #item.effect_values)
        for i, field in ipairs(item.effect_ids) do assert(stats.by_id[field] and tonumber(item.effect_values[i]) > 0, field) end
    end
end
local bus, events = require("core/event_bus"), require("core/events")
local tasks, listeners, profiles, connection = {}, {}, {}, {[0]=2,[1]=2}
local now, fail, writes = 1000000, false, 0
local function new_profile()
    local p={revision=1,save={gameplay_stats={}},entitlements={}}
    for _,row in ipairs(stats.rows) do p.save.gameplay_stats[row.field_id]=row.default_value end
    return p
end
profiles[0], profiles[1] = new_profile(), new_profile()
package.loaded["core/scheduler"]={every=function(_,f,k)tasks[k]=f end,after=function(_,f,k)tasks[k]=f end,cancel=function(k)tasks[k]=nil end}
package.loaded["systems/player_profile_service"]={get_profile=function(id)return copy(profiles[id])end,
    get_provider=function()return {persist_save=function()end}end,
    update_save_sections=function(id,sections,reason)
        if fail then return {ok=false,error="disk_failed"} end
        for k,v in pairs(sections)do profiles[id].save[k]=copy(v)end
        writes=writes+1
        bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,reason=reason})
        return {ok=true}
    end}
GameRules={GetGameTime=function()return now end}
PlayerResource={IsValidPlayerID=function(_,id)return profiles[id]~=nil end,
    GetPlayer=function(_,id)return id end,GetConnectionState=function(_,id)return connection[id]end}
CustomGameEventManager={RegisterListener=function(_,n,f)listeners[n]=f end,Send_ServerToPlayer=function()end}
local calendar=require("systems/archive_calendar")
calendar.set_clock(function()return now end)
local service=require("systems/archive_service")
local function start()
    bus.reset();service.init()
    for id in pairs(profiles)do bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id})end
end
local function tick(seconds)
    for _=1,seconds do now=now+1;tasks.archive_online_clock()end
end
profiles[0].entitlements.archive_pass={active=true,expires_at=now+1810}
start();tick(1800)
local s=profiles[0].save.archive.online
assert(s.map_level==1 and s.map_seconds==3600 and s.coins==30)
assert(profiles[0].save.gameplay_stats.map_level==1)
assert(profiles[1].save.archive.online.map_level==0 and profiles[1].save.archive.online.coins==30)
tick(60);s=profiles[0].save.archive.online
assert(s.map_seconds==3670 and s.coins==31,"expiry splits weighted time, coins never double")
tick(29);bus.emit(events.PLAYER_DISCONNECTED,{player_id=0});connection[0]=3
assert(profiles[0].save.archive.online.actual_seconds==1889,"disconnect checkpoints remainder")
tick(300);assert(profiles[0].save.archive.online.actual_seconds==1889)
connection[0]=2;tick(1);tick(31)
require("systems/archive_online_clock").flush(0)
assert(profiles[0].save.archive.online.actual_seconds==1920 and profiles[0].save.archive.online.coins==32)
start();tick(60)
assert(profiles[0].save.archive.online.actual_seconds==1980,"new session adds only new connected time")
fail=true;tick(60)
assert(profiles[0].save.archive.online.actual_seconds==1980 and service.has_pending(0))
fail=false;tick(60);tasks.archive_retry()
assert(profiles[0].save.archive.online.actual_seconds==2100,"newer checkpoint and old retry cannot double count")
assert(not service.has_pending(0))
local before=copy(profiles[0].save.gameplay_stats)
assert(not service.work_upgrade(0,"work_01",0).ok,"insufficient balance")
profiles[0].save.archive.online.coins=600
fail=true;assert(not service.work_upgrade(0,"work_01",0).ok)
assert(profiles[0].save.archive.online.coins==600 and profiles[0].save.archive.online.work_levels.work_01==nil)
fail=false;tasks.archive_retry()
assert(profiles[0].save.archive.online.coins==0 and profiles[0].save.archive.online.work_levels.work_01==1)
assert(profiles[0].save.gameplay_stats.lumberjack_attack_speed_bonus_pct==before.lumberjack_attack_speed_bonus_pct+2)
assert(service.work_upgrade(0,"work_01",0).ok)
assert(profiles[0].save.archive.online.coins==0,"duplicate charged once")
assert(not service.work_upgrade(0,"work_01",1).ok)
assert(not service.work_upgrade(0,"missing",0).ok)
assert(not listeners.survival_archive_online_checkpoint,"clients cannot submit time")
assert(service.snapshot(0,"map_level").rows[1].completed==1)
assert(service.snapshot(0,"work").rows[1].completed==1)
assert(service.snapshot(0,"work").online.coins==0)
local model=require("systems/archive_online_rewards")
local a,st={},{}
local function apply(target,item)
    for i,f in ipairs(item.effect_ids)do target[f]=(target[f]or 0)+tonumber(item.effect_values[i])end
end
local function checkpoint(session,raw,weighted)
    return model.apply({kind="online_checkpoint",session=session,actual_seconds=raw,map_seconds=weighted},a,st,apply)
end
assert(checkpoint("first",1112*3600,1112*3600))
assert(a.online.map_level==34 and st.map_level==34)
local earned=a.online.coins;assert(checkpoint("second",60,60))
assert(checkpoint("first",1112*3600,1112*3600))
assert(a.online.coins==earned+1 and st.map_level==34,"old-session retry and max-level rewards are idempotent")
assert(not checkpoint("bad",60,121))
assert(not checkpoint("bad",0/0,60))
print("ARCHIVE_ONLINE_PASS: expiry, player isolation, reconnect, cross-session remainder, retries, atomic upgrades, 34 levels")
local tools_enabled = false
IsInToolsMode = function() return tools_enabled end
assert(not service.zaixian({player_id=0,args={"60"}}),"cheats disabled outside tools")
tools_enabled = true
for _,arg in ipairs({"0","-1","1.5","nan","inf","1000001","oops"}) do
    assert(not service.zaixian({player_id=0,args={arg}}),arg)
end
assert(not service.zaixian({player_id=0,args={}}))
assert(not service.zaixian({player_id=0,args={"1","2"}}))
local saved_before = copy(profiles[0].save.archive.online)
local other_before = copy(profiles[1].save.archive.online)
assert(service.zaixian({player_id=0,args={"60"}}))
local simulated = profiles[0].save.archive.online
assert(simulated.actual_seconds==saved_before.actual_seconds+3600)
assert(simulated.map_seconds==saved_before.map_seconds+3600 and simulated.coins==saved_before.coins+60)
assert(profiles[1].save.archive.online.actual_seconds==other_before.actual_seconds)
profiles[0].entitlements.archive_pass={active=true,expires_at=now+1000}
assert(service.zaixian({player_id=0,args={"30"}}))
assert(profiles[0].save.archive.online.map_seconds==simulated.map_seconds+3600)
assert(profiles[0].save.archive.online.coins==simulated.coins+30)
local before_failure = copy(profiles[0].save.archive.online)
fail=true;assert(not service.zaixian({player_id=0,args={"600"}}))
assert(profiles[0].save.archive.online.coins==before_failure.coins)
fail=false;tasks.archive_retry();tasks.archive_retry()
assert(profiles[0].save.archive.online.coins==before_failure.coins+600,"retry credits once")
local before_tick=profiles[0].save.archive.online.actual_seconds
tick(60)
assert(profiles[0].save.archive.online.actual_seconds==before_tick+60,"cheat does not alter natural timer cursor")
print("ZAIXIAN_PASS: arguments, permissions, normal/pass credit, isolation, retry, natural clock")
tools_enabled=false
assert(not service.xinyang({player_id=0,args={"3000"}}))
tools_enabled=true
for _,arg in ipairs({"0","-1","1.5","nan","inf","1000000001","oops"}) do
    assert(not service.xinyang({player_id=0,args={arg}}),arg)
end
assert(not service.xinyang({player_id=0,args={}}))
assert(not service.xinyang({player_id=0,args={"1","2"}}))
profiles[0].save.archive.buildings={faith=0,levels={},earned_by_day={[tostring(calendar.day())]=4000}}
assert(service.xinyang({player_id=0,args={"15000"}}))
assert(service.snapshot(0,"building").buildings.faith==15000)
assert(not profiles[1].save.archive.buildings,"only issuing account receives faith")
for level=0,4 do assert(service.building_upgrade(0,"building_01",level).ok) end
assert(profiles[0].save.archive.buildings.faith==0)
assert(profiles[0].save.gameplay_stats.technology_wood_cost_refund_pct==25)
assert(service.snapshot(0,"building").rows[1].completed==1)
assert(service.snapshot(0,"building").buildings.earned_today==4000,"cheat bypasses but does not reset daily cap")
fail=true;assert(not service.xinyang({player_id=0,args={"3000"}}))
assert(profiles[0].save.archive.buildings.faith==0)
fail=false;tasks.archive_retry();tasks.archive_retry()
assert(profiles[0].save.archive.buildings.faith==3000,"failed save retries once")
print("XINYANG_PASS: permissions, validation, account isolation, persisted balance, five upgrades, retry, daily cap")
