-- Count actual frozen commerce_runtime tick calls with synthetic boundaries.
-- There is no engine, network, scene, inventory or real player in this process.
local source=arg and arg[1]
package.path=(source and source..'/scripts/vscripts/?.lua;' or 'scripts/vscripts/?.lua;')..package.path
package.loaded['core/test_access_policy']={enabled=function()return false end}
local tasks,counts,ids,last={},{},{},{}
local has_units=false
local live_unit={IsNull=function()return false end,IsAlive=function()return true end}
package.loaded['core/scheduler']={every=function(_,callback,key)tasks[key]=callback end,cancel=function()end}
package.loaded['systems/commerce_effects']={owned=function()counts.ownership=counts.ownership+1;return false end,invalidate=function()end}
package.loaded['systems/player_context_service']={active_player_ids=function()return ids end,is_defeated=function()return false end}
package.loaded['systems/worker_system']={refresh_commerce_capacity=function()counts.worker_capacity=counts.worker_capacity+1 end}
package.loaded['systems/gameplay_phase_guard']={post_clear_frozen=function()return false end}
local bus=require('core/event_bus');local events=require('core/events')
local native_world={}
GameRules={GetGameModeEntity=function()return native_world end,GetGameTime=function()return 0 end}
CustomGameEventManager={RegisterListener=function()return 1 end}
local function signature(value)
 local keys={};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys)
 local result={};for _,key in ipairs(keys)do result[#result+1]=key..'='..tostring(value[key]) end
 return table.concat(result,'|')
end
CustomNetTables={SetTableValue=function(_,table_name,key,value)
 counts.nettable=counts.nettable+1
 local identity=table_name..':'..key;local current=signature(value)
 if last[identity]==current then counts.identical=counts.identical+1 end
 last[identity]=current
end}
bus.handle_request(events.HERO_SUMMON_GET_REQUEST,function()counts.hero_request=counts.hero_request+1;return {unit=has_units and live_unit or nil} end)
local runtime=require('systems/commerce_runtime')
for _,ready in ipairs({0,1})do
for _,players in ipairs({1,4})do
 ids={};for id=0,players-1 do ids[#ids+1]=id end
 runtime.init();last={};counts={ownership=0,worker_capacity=0,nettable=0,identical=0,hero_request=0}
 has_units=ready==1
 if has_units then for _,id in ipairs(ids)do bus.emit(events.BUILDING_CREATED,{player_id=id,building_id='wall',unit=live_unit})end end
 local callback=tasks.commerce_runtime
 for second=1,60 do assert(callback()==true) end
 assert(counts.nettable==players*60 and counts.identical==players*59)
 print(string.format('COMMERCE_STABLE_CALLS units_ready=%d players=%d ticks=60 direct_ownership_queries=%d worker_capacity_queries=%d hero_bus_requests=%d mocked_nettable_writes=%d identical_writes=%d actual_native_calls=0 actual_network_calls=0',
  ready,players,counts.ownership,counts.worker_capacity,counts.hero_request,counts.nettable,counts.identical))
 assert(counts.ownership==players*60*(has_units and 13 or 11) and counts.worker_capacity==players*60)
 runtime.init();assert(callback()==false,'Old world tick must be invalid after re-init')
end
end
