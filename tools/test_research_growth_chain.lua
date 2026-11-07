-- Actual event producer/bootstrap/shop/native ability sync; only engine and
-- surrounding authority boundaries are substituted. No client/network IO.
package.path='scripts/vscripts/?.lua;'..package.path
package.loaded['core/test_access_policy']={enabled=function()return false end}
package.loaded['core/scheduler']={after=function()end,cancel=function()end,every=function()end}
package.loaded['systems/book_auto_purchase_service']={init=function()end}
package.loaded['debug/technology_cheat_handler']={register=function()end}
package.loaded['systems/technology_stat_manager']={training_room_multiplier=function()return 1 end}
package.loaded['systems/commerce_effects']={owned=function()return false end}
local bus,events=require('core/event_bus'),require('core/events');bus.reset()
local json=require('core/json_encoder')
local directory=arg[1] or 'production';local count=tonumber(arg[2])or 64;local hits=tonumber(arg[3])or 600
if directory~='baseline'and directory~='production'then
 package.preload['bootstrap/research_technology_bootstrap']=function()return assert(loadfile(directory..'/research_technology_bootstrap.lua'))()end
 package.preload['systems/research_lab_ability_sync']=function()return assert(loadfile(directory..'/research_lab_ability_sync.lua'))()end
end
local counters,roster,first,last={},{},nil,nil
local function inc(key,n)counters[key]=(counters[key]or 0)+(n or 1)end
local request=bus.request
bus.request=function(name,payload)
 if name==events.HERO_PROGRESSION_GET_REQUEST then inc('authoritative_rebirth_reads')end
 return request(name,payload)
end
local original_ipairs=ipairs
ipairs=function(t)
 local next,index,value=original_ipairs(t)
 if t~=roster then return next,index,value end
 return function(a,i)local k,v=next(a,i);if k then inc('returned_building_entries_walked')end;return k,v end,index,value
end
local errors={};local output=print
print=function(s)if tostring(s):find('handler error',1,true)then errors[#errors+1]=s else output(s)end end
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,GetTeam=function()return 2 end}
CustomNetTables={SetTableValue=function(_,name,key,value)
 assert(name=='survival_research');inc('research_nettables_calls');inc('research_rows_constructed',#value.technologies);first=first or value;last=value
end}
local function unit()
 local abilities={}
 return {abilities=abilities,IsNull=function()inc('native_reads');return false end,
 FindAbilityByName=function(_,name)inc('native_reads');return abilities[name]end,
 AddAbility=function(_,name)
  inc('native_writes');local a={level=0,hidden=true,active=false,slot=-1}
  function a:GetLevel()inc('native_reads');return self.level end
  function a:SetLevel(v)inc('native_writes');self.level=v end
  function a:IsHidden()inc('native_reads');return self.hidden end
  function a:SetHidden(v)inc('native_writes');self.hidden=v end
  function a:IsActivated()inc('native_reads');return self.active end
  function a:SetActivated(v)inc('native_writes');self.active=v end
  function a:GetAbilityIndex()inc('native_reads');return self.slot end
  function a:SetAbilityIndex(v)inc('native_writes');self.slot=v end
  abilities[name]=a;return a
 end,RemoveAbility=function(_,name)inc('native_writes');abilities[name]=nil end}
end
for i=1,count do roster[i]={player_id=0,team=2,building_id=i==1 and 'building_research_lab'or i==2 and 'building_advanced_research_lab'or 'tower',entindex=i,unit=unit()}end
bus.handle_request(events.BUILDING_LIST_REQUEST,function()inc('building_list_requests');return{buildings=roster}end)
bus.handle_request(events.RESOURCE_GET_REQUEST,function()return{gold=1e6,wood=1e6}end)
bus.handle_request(events.PERMANENT_REWARD_EFFECTS_GET_REQUEST,function()return{ok=true,totals={}}end)
local production=require('systems/hero_progression_system');production.init()
local shop=require('systems/shop_system');shop.init()
local bootstrap=require('bootstrap/research_technology_bootstrap');bootstrap.init()
local sync=require('systems/research_lab_ability_sync');sync.init()
bus.request(events.HERO_PROGRESSION_APPLY_REQUEST,{player_id=0,effects={{effect_type='add_attack_all_attribute_gain',value=1},{effect_type='set_rebirth_level',value=10}}})
bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0}) -- warm the stable path
counters={};first=nil;last=nil
local start=os.clock()
for n=1,hits do bus.emit(events.HERO_MAIN_ATTACK_LANDED,{player_id=0})end
local duration=(os.clock()-start)*1000
assert(#errors==0,table.concat(errors,'\n'))
local measured=counters;counters={}
assert(bus.request(events.HERO_PROGRESSION_GET_REQUEST,{player_id=0}).snapshot.all_attributes==hits+1,'growth rules unchanged')
local identical=first~=nil and json.encode(first)==json.encode(last)or nil
local checks=0;local function check(ok,why)assert(ok,why);checks=checks+1 end
if directory~='baseline'then
 check((measured.research_nettables_calls or 0)==0 and (measured.native_reads or 0)==0 and (measured.building_list_requests or 0)==0,'stable attacks skip unrelated research work')
 production._test.get_state(0).rebirth_level=0
 bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,reason='unrecognized_reason',rebirth_level=10})
 check(counters.research_nettables_calls==1,'unknown reason and stale payload cannot hide authoritative rebirth change')
 local old,last_rows=last,{}
 for _,row in ipairs(last.technologies)do last_rows[row.tech_id]=row end
 check(last_rows['ARS-03'].prerequisite_met==0,'real rebirth prerequisite recomputed')
 counters={};bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0,reason='another_unknown'})
 check((counters.research_nettables_calls or 0)==0 and (counters.native_reads or 0)==0,'unknown but same dependencies has no repaint')
 production._test.get_state(0).rebirth_level=10
 bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0})
 check(counters.research_nettables_calls==1,'true upward rebirth recomputes even without reason')
 counters={};roster[1].unit=unit();bus.emit(events.BUILDING_CREATED,roster[1])
 check(next(roster[1].unit.abilities)~=nil and (counters.native_writes or 0)>0,'same-id replacement binds actual new abilities')
 bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0})
 check(counters.research_nettables_calls==1,'building identity invalidation prevents stale rank proof')
 counters={};bus.emit(require('research/research_event_names').LEVEL_CHANGED,{player_id=0})
 check((counters.native_reads or 0)>0,'real technology event still syncs native slots')
 bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0})
 check(counters.research_nettables_calls==1,'level event invalidates global projection')
 counters={};bus.emit(events.PLAYER_DISCONNECTED,{player_id=0});bus.emit(events.HERO_PROGRESSION_CHANGED,{player_id=0})
 check(counters.research_nettables_calls==1,'same player id cannot retain old disconnected projection')
 check(#errors==0,table.concat(errors,'\n'))
end
output(json.encode({status='REAL_PRODUCTION_RESEARCH_GROWTH_COUNTS',variant=directory,buildings=count,hits=hits,counters=measured,identical_first_last_research_dto=identical,dependency_regression_checks=checks,
 isolated_lua_ms=duration,native_time_measured=false,network_requests=0,source_changes=0,authoritative_growth=hits+1}))
