-- Real projection/event bus/definitions. Simulate only engine transport/time.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus, events = require("core/event_bus"), require("core/events")
local tasks, tables, workers, errors = {}, {}, {}, {}
local calls, city_level, wallet = 0, 4, {wood = 30000, gold = 5000}
local original_print = print
print = function(s) if tostring(s):find("handler error", 1, true) then errors[#errors+1] = s end end
package.loaded["core/scheduler"] = {
    after = function(_, callback, id) assert(not tasks[id]); tasks[id] = callback end,
    cancel = function(id) tasks[id] = nil end,
    every = function() error("must not poll") end,
}
CustomNetTables = {SetTableValue = function(_, name, key, value)
    if name == "survival_ability_runtime" then tables[key] = value end
end}
local function unit(id, name, passive)
    local a = {active=true, level=1, writes=0}
    function a:IsNull() return false end
    function a:GetAbilityName() return name or "ability_fuse_lumberjack_03" end
    function a:entindex() return id+1000 end
    function a:GetLevel() return self.level end
    function a:SetLevel(v) self.level=v end
    function a:IsActivated() return self.active end
    function a:SetActivated(v) self.active=v;self.writes=self.writes+1 end
    function a:IsPassive() return passive == true end
    local u = {ability=a,survival_player_id=0,survival_worker_type="lumberjack",survival_lumberjack_level=3}
    function u:IsNull() return false end
    function u:IsAlive() return not self.dead end
    function u:entindex() return id end
    function u:GetTeamNumber() return 2 end
    function u:GetPlayerOwnerID() return self.survival_player_id end
    function u:GetAbilityCount() return 1 end
    function u:GetAbilityByIndex() return a end
    function u:FindAbilityByName() return a end
    return u
end
bus.reset()
bus.handle_request(events.RESOURCE_GET_REQUEST,function() return wallet end)
bus.handle_request(events.BUILDING_LIST_REQUEST,function()
    return {buildings={{building_id="main_city",level=city_level}}}
end)
bus.handle_request(events.WORKER_LIST_REQUEST,function() calls=calls+1;return workers end)
local service = require("ui/ability_runtime_service");service.init()
local function changed(state) bus.emit(events.WORKER_CHANGED,state) end
local function flush(id)
    id=id or "ability_fusion_refresh_0:2"
    local callback=assert(tasks[id],id);tasks[id]=nil;callback()
    assert(#errors==0,table.concat(errors,"\n"))
end
local function value(u) return assert(tables[tostring(u.ability:entindex())]) end
local function check(u,active)
    assert(u.ability.active==active,"engine activation mismatch")
    assert(value(u).available==(active and 1 or 0),"UI availability mismatch")
end
for i=1,3 do
    local u=unit(i)
    workers[i]={unit=u,entindex=i,player_id=0,team=2,worker_type="lumberjack"};changed(workers[i])
    assert(not u.ability.active,"new workers must be disabled before the first batched snapshot")
end
local a,c=workers[1].unit,workers[3].unit
flush();assert(calls==1,"training burst shares one registry scan")
for _,s in ipairs(workers) do check(s.unit,false) end
assert(value(a).status_text:find("LV5",1,true))
city_level=5
bus.emit(events.BUILDING_CHANGED,{unit=unit(90,"mock_city"),player_id=0,team=2,building_id="main_city",level=5})
flush();for _,s in ipairs(workers) do check(s.unit,true) end
local function resource() bus.emit(events.RESOURCE_CHANGED,{player_id=0,team=2}) end
wallet.gold=4999;resource();flush("ability_resource_refresh_player:0");check(a,false)
wallet.gold=5000;calls=0
for i=1,100 do resource() end
flush("ability_resource_refresh_player:0");assert(calls==1,"resource burst shares one registry scan");check(a,true)
local writes=a.ability.writes;resource();flush("ability_resource_refresh_player:0")
assert(a.ability.writes==writes,"unchanged state must not reset activation")
for _,flag in ipairs({"dead","survival_super_lumberjack","survival_lumberjack_fusion_pending"}) do
    c[flag]=true;changed(workers[3]);flush();check(a,false)
    c[flag]=nil;changed(workers[3]);flush();check(a,true)
end
workers[3].player_id,c.survival_player_id=1,1
changed(workers[1]);flush();check(a,false)
workers[3].player_id,c.survival_player_id=0,0
changed(workers[3]);flush();check(a,true)
workers[3]=nil
changed({player_id=0,team=2,worker_type="lumberjack",entindex=3,removed=true})
assert(tables["1003"].removed==1);flush();check(a,false);assert(value(a).fields[2].value=="2/3")
local mine=unit(20,"ability_gold_mine_stop_auto_upgrade")
for _,auto in ipairs({0,1,0}) do
    bus.emit(events.GOLD_MINE_CHANGED,{unit=mine,player_id=0,building_id="gold_mine",auto_upgrading=auto})
    check(mine,auto==1)
end
local passive=unit(21,"mock_passive",true)
bus.emit(events.BUILDING_CREATED,{unit=passive,player_id=0,building_id="mock"})
assert(value(passive).passive==1 and passive.ability.writes==0)
changed(workers[1]);local stale=tasks["ability_fusion_refresh_0:2"]
service.init();assert(not tasks["ability_fusion_refresh_0:2"])
tables={};stale();assert(next(tables)==nil)
original_print("PASS fusion runtime: city/material/resource gates, ownership, death/consumption, coalescing, native activation, passive metadata and generation cleanup")
