package.path='scripts/vscripts/?.lua;'..package.path
-- Execute the shipping function with the real training tracker and catalogue.
-- Engine lifecycle/dependency setup is intentionally outside this unit fixture.
local file=assert(io.open('scripts/vscripts/systems/worker_system.lua','rb'));local source=file:read('*a');file:close()
local start=assert(source:find('local commerce_capacity_bonus = {}',1,true))
local finish=assert(source:find('local repairer_training =',start,true))
local tracker=require('systems/worker_training_progress').create(require('config/generated/training_definitions'))
local original=tracker.set_capacity_bonus;local sets,events=0,0
function tracker:set_capacity_bonus(id,bonus)sets=sets+1;return original(self,id,bonus)end
local owned={}
local env=setmetatable({M={},lumberjack_training=tracker,event_bus={emit=function(name,p)
 assert(name=='changed'and p.player_id==0 and p.training_capacity_changed==1);events=events+1
end},events={WORKER_CHANGED='changed'},require=function(name)
 assert(name=='systems/commerce_effects');return{owned=function(_,key)return owned[key]end}
end},{__index=_G})
local chunk=assert(loadstring(source:sub(start,finish-1)));setfenv(chunk,env);chunk()
local refresh=env.M.refresh_commerce_capacity
assert(refresh(0));for n=1,1000 do assert(refresh(0)==false)end
assert(sets==1 and events==1)
local before=tracker:get_for(0,'train_lumberjack_01').max_count
owned.immortal=true;assert(refresh(0)==false)
owned.lumber_fury=true;assert(refresh(0));assert(tracker:get_for(0,'train_lumberjack_01').max_count==before+1)
for n=1,1000 do assert(refresh(0)==false)end
assert(sets==2 and events==2)
owned.immortal=false;assert(refresh(0));assert(tracker:get_for(0,'train_lumberjack_01').max_count==before)
assert(sets==3 and events==3)
assert(source:find('lumberjack_training:reset%(%)%s+commerce_capacity_bonus = {}'),'lifecycle reset also retires capacity cache')
print('WORKER_CAPACITY_CHANGE_PASS real tracker,unchanged1000 calls0 setter/events,acquire/revoke preserve capacity rule')
