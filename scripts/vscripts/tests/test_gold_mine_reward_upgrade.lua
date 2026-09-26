package.path = "scripts/vscripts/?.lua;" .. package.path
local bus,events = require("core/event_bus"),require("core/events")
package.loaded["core/scheduler"]={after=function() end,cancel=function() end}
package.loaded["systems/building_visual_service"]={apply=function() end}
package.loaded["systems/building_sound_service"]={upgrade_completed=function() end}
package.loaded["systems/technology_stat_manager"]={get=function() return {final={gold_mine={}}} end}
local active, begins, last_options = false,0,nil
package.loaded["systems/building_upgrade_process"]={
    is_active=function() return active end,
    begin=function(unit,options) begins=begins+1;last_options=options;active=true;return {ok=true} end,
}
local config=require("config/gold_mine_config")
local service=require("systems/gold_mine_system")
local spent=0
bus.handle_request(events.RESOURCE_TRY_SPEND_REQUEST,function(p) spent=spent+1;return {ok=true} end)
service.init()
local unit={}
function unit:IsNull() return false end
function unit:IsAlive() return self.dead~=true end
function unit:entindex() return 101 end
function unit:FindAbilityByName() return nil end
for _,name in ipairs({"SetBaseMaxHealth","SetMaxHealth","SetHealth","SetPhysicalArmorBaseValue"}) do unit[name]=function() end end
bus.emit(events.BUILDING_CREATED,{unit=unit,building_id="gold_mine",player_id=0,team=2,level=1,definition={}})
local function upgrade(p)
    p.entindex=101
    local result,err=bus.request(events.GOLD_MINE_LEVEL_UPGRADE_REQUEST,p)
    assert(not err,err)
    return result
end
assert(not upgrade({player_id=1,system_free_upgrade=true}).ok and begins==0 and spent==0)
assert(upgrade({player_id=0,system_free_upgrade=true}).ok and begins==1 and spent==0)
assert(last_options.target_level==2)
assert(not upgrade({player_id=0,system_free_upgrade=true}).ok and begins==1)
active=false;last_options.on_complete();assert(unit.survival_level==2)
assert(upgrade({player_id=0}).ok and begins==2 and spent==1,"normal upgrades still pay")
active=false;unit.dead=true;assert(not upgrade({player_id=0,system_free_upgrade=true}).ok)
print("PASS gold mine reward upgrade: owner, free one level, busy/dead target, normal upgrade payment")


unit.dead=nil
local schedules,harvest_publishes=0,0
bus.subscribe(events.GOLD_MINE_CHANGED,function() harvest_publishes=harvest_publishes+1 end)
package.loaded["core/scheduler"].after=function() schedules=schedules+1 end
for i=1,200 do bus.emit(events.TECHNOLOGY_STATS_CHANGED,{player_id=0,changed_section="lumberjack",changed_field="attack"}) end
assert(schedules==0 and harvest_publishes==0,"wood attack growth must not reschedule gold production or republish mine stats")
print("LUMBERJACK_GOLD_ISOLATION_PASS")
