package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;"..package.path
local clock = 0
GameRules = {GetGameTime=function() return clock end}
local scheduler = require("core/scheduler")
local factory = require("ui/stat_push_coalescer")
local selected, delivered, builds = {[0]=291,[1]=500}, {}, 0
local queue = factory.new({
    scheduler=scheduler,
    is_selected=function(player,unit) return selected[player]==unit end,
    build=function(p)
        builds=builds+1
        return {entindex=p.entindex,armor=p.armor,level=p.level or 1,
            reason=p.reason,stat_tooltips={armor={value=p.armor,unit="war3_display"}}}
    end,
    send=function(player,snapshot) delivered[#delivered+1]={player=player,snapshot=snapshot} end,
})
local function advance(t) clock=clock+t;scheduler.think() end
for i=1,100 do queue.push({player_id=0,entindex=291,armor=i}) end
assert(scheduler.task_count()==1 and builds==0,"coalesce before computing snapshots")
advance(.16)
assert(#delivered==1 and delivered[1].snapshot.armor==100,"latest real value only")
for i=1,20 do queue.push({player_id=0,entindex=291,armor=100,reason="other"}) end
advance(.16);assert(#delivered==1,"same displayed data is not resent")
queue.push({player_id=0,entindex=291,armor=100.3,level=2})
advance(.16);assert(#delivered==2 and delivered[2].snapshot.armor==100.3,"do not round away real growth")
local n=builds
for i=1,100 do queue.push({player_id=0,entindex=999,armor=i}) end
assert(scheduler.task_count()==0 and builds==n,"unselected buildings do no UI work")
queue.push({player_id=0,entindex=291,armor=101});selected[0]=999
advance(.16);assert(#delivered==2,"selection changed before delivery")
selected[0]=291
local p={player_id=0,entindex=291,armor=102};queue.push(p);p.armor=999
queue.push({player_id=1,entindex=500,armor=20});advance(.16)
assert(#delivered==4)
local found=false;for _,d in ipairs(delivered) do if d.player==0 and d.snapshot.armor==102 then found=true end end
assert(found,"copy event payload before later handlers mutate it")
queue.push({player_id=0,entindex=291,armor=103});queue.reset();advance(.16)
assert(#delivered==4 and scheduler.task_count()==0,"reset cancels pending work")
for i=1,20 do queue.push({player_id=0,entindex=291,armor=200+i});advance(.05) end
advance(.16)
assert(#delivered>5 and #delivered<=11,"continuous updates are bounded without starvation")
assert(delivered[#delivered].snapshot.armor==220,"last real update is retained")
print("STAT_PUSH_PASS: burst100->1, latest value, unchanged skip, unselected skip, switch, two players, reset, sustained updates")

queue.reset()
local combat_sent=0
local combat=factory.new({scheduler=scheduler,task_prefix="combat_ui_push_",interval=0.1,
 is_selected=function(player,unit)return selected[player]==unit end,
 merge=function(previous,latest)latest.armor_dirty=previous.armor_dirty or latest.armor_dirty end,
 build=function(p)return {entindex=p.entindex,attack=p.attack,armor_dirty=p.armor_dirty}end,
 send=function(_,value)combat_sent=combat_sent+1;assert(value.attack==500 and value.armor_dirty)end})
queue.push({player_id=0,entindex=291,armor=250})
combat.push({player_id=0,entindex=291,attack=1,armor_dirty=true})
for i=2,500 do combat.push({player_id=0,entindex=291,attack=i}) end
assert(scheduler.task_count()==2,"building and combat queues never replace each other's tasks")
advance(.11);assert(combat_sent==1 and scheduler.task_count()==1)
advance(.05);assert(scheduler.task_count()==0)
print("COMBAT_PUSH_PASS: 500 changes -> 1 latest snapshot; 100ms; independent building queue; armor invalidation preserved")
