package.path = "scripts/vscripts/?.lua;" .. package.path
package.loaded["systems/rogue_builder_start_effect_service"] = {init=function() end}
package.loaded["systems/player_context_service"] = {is_defeated=function() return false end}
PlayerResource={GetPlayer=function() return {} end}
GameRules={GetGameTime=function() return 0 end}
RandomInt=function() return 1 end
local bus,events=require("core/event_bus"),require("core/events")
local runtime=require("systems/rogue_effect_runtime_service")
local buildings,requests,quotes
local function building(index,kind,owner,level)
    local unit={level=level or 1}
    function unit:IsNull() return false end
    function unit:IsAlive() return not self.dead end
    function unit:HasModifier() return self.constructing==true end
    return {unit=unit,entindex=index,building_id=kind,player_id=owner or 0}
end
local function reset(list)
    buildings,requests,quotes=list,{},{}
    bus.reset();runtime.init()
    bus.handle_request(events.BUILDING_LIST_REQUEST,function(payload)
        local result={}
        for _,row in ipairs(buildings) do
            if row.player_id==payload.player_id and row.unit:IsAlive() then result[#result+1]=row end
        end
        return {buildings=result}
    end)
    local function quote(payload,event)
        quotes[#quotes+1]=event
        assert(payload.player_id==0)
        local unit=payload.building
        return {ok=unit.level<4 and not unit.survival_upgrade_in_progress}
    end
    local function upgrade(payload,event)
        assert(payload.system_free_upgrade and payload.silent_notification and payload.upgrade_mode=="one")
        payload.building.survival_upgrade_in_progress=true
        requests[#requests+1]={payload=payload,event=event}
        return {ok=true,pending=true}
    end
    for _,event in ipairs({events.BUILDING_UPGRADE_QUOTE_REQUEST,events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST}) do
        bus.handle_request(event,function(p) return quote(p,event) end)
    end
    for _,event in ipairs({events.BUILDING_UPGRADE_FREE_REQUEST,events.GOLD_MINE_LEVEL_UPGRADE_REQUEST}) do
        bus.handle_request(event,function(p) return upgrade(p,event) end)
    end
end
local function grant(player)
    assert(runtime.grant(player or 0,"infrastructure_maniac","test:upgrade","boss").ok)
    return runtime.snapshot(player or 0)[1]
end
local function changed(row,reason)
    row.unit.survival_upgrade_in_progress=nil
    bus.emit(events.BUILDING_CHANGED,{unit=row.unit,entindex=row.entindex,
        player_id=row.player_id,building_id=row.building_id,reason=reason})
end
local function complete(row)
    row.unit.level=row.unit.level+1
    changed(row,row.building_id=="gold_mine" and "gold_mine_upgraded" or "wall_upgraded")
end
local mine=building(1,"gold_mine")
reset({mine,building(2,"gold_mine",1)})
local instance=grant()
assert(#requests==1 and requests[1].event==events.GOLD_MINE_LEVEL_UPGRADE_REQUEST)
bus.emit(events.BUILDING_CHANGED,{unit=mine.unit,player_id=1,entindex=1,reason="gold_mine_upgraded"})
assert(instance.upgrade_remaining==3 and #requests==1,"foreign completion cannot consume an upgrade")
for i=1,3 do complete(mine);assert(#requests==math.min(3,i+1)) end
assert(mine.unit.level==4 and instance.status=="completed" and instance.upgrade_remaining==0)
for _,event in ipairs(quotes) do assert(event==events.GOLD_MINE_LEVEL_UPGRADE_QUOTE_REQUEST) end

mine=building(1,"gold_mine",0,3)
reset({mine});instance=grant();complete(mine)
assert(#requests==1 and instance.status=="completed","candidate exhaustion ends the chain")
mine=building(1,"gold_mine");mine.unit.constructing=true
reset({mine});instance=grant()
assert(#requests==0 and #quotes==0 and instance.status=="completed")

local wall=building(2,"wall")
mine=building(1,"gold_mine")
reset({mine,wall});instance=grant()
changed(mine,"upgrade_cancelled_completion_failed")
assert(#requests==2 and requests[2].payload.entindex==2 and instance.upgrade_remaining==3)
complete(wall);complete(mine);complete(mine)
assert(#requests==4 and instance.status=="completed","cancelled attempts do not spend the three successful upgrades")

mine=building(1,"gold_mine")
reset({mine});instance=grant()
changed(mine,"upgrade_cancelled_completion_failed")
assert(#requests==2 and instance.upgrade_remaining==3,"the only eligible cancelled target can be retried")
for i=1,3 do complete(mine) end
assert(instance.status=="completed" and #requests==4)

mine=building(1,"gold_mine");wall=building(2,"wall")
reset({mine,wall});instance=grant()
mine.unit.dead=true
bus.emit(events.BUILDING_DESTROYED,{unit=mine.unit,entindex=1,player_id=0,building_id="gold_mine"})
assert(#requests==2 and requests[2].payload.entindex==2 and instance.upgrade_remaining==3)
for i=1,3 do complete(wall) end
assert(instance.status=="completed" and #requests==4)
print("PASS infrastructure maniac: gold mine routing, serial completion, owner isolation, exhaustion and cancelled/destroyed retry")
