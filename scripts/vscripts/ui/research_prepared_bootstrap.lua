local M={}
function M.new(o)
 local bus=require('core/event_bus');local events=require('core/events')
 local builder=require('ui/ability_runtime_builder')
 local research_events=require('research/research_event_names')
 local config=require('config/buildings_config')
 local world=bus.get_generation();local mode=GameRules:GetGameModeEntity();local live=true
 local function current()return live and bus.get_generation()==world and GameRules:GetGameModeEntity()==mode and not mode:IsNull()end
 local driver=require('ui/compact_dispatch_driver').new({entity=mode,is_current=current})
 local cache,versions={},{};local learning_epoch=0
 local metrics={learning_builds=0,learning_rows=0,authority_reads=0}
 local research={}
 for _,row in ipairs(o.lookup.production.research)do
  if row.mapping.building_id=='building_advanced_research_lab'then research[#research+1]=row end
 end
 assert(#research==10,'prepared_research_scope_changed')
 local function input(id)
  local owner=PlayerResource:GetPlayer(id);local state=cache[id]
  if state and state.owner==owner then return state end
  local personal=bus.request(research_events.STATE_GET_REQUESTED,{player_id=id})or{}
  local progression=bus.request(events.HERO_PROGRESSION_GET_REQUEST,{player_id=id})or{}
  metrics.authority_reads=metrics.authority_reads+2
  state={owner=owner,personal=personal,rebirth=tonumber(progression.snapshot and progression.snapshot.rebirth_level)or 0}
  cache[id]=state;return state
 end
 local function invalidate(id)cache[id]=nil;versions[id]=(versions[id]or 0)+1 end
 local service=require('ui/research_prepared_service').new({bus=bus,transport=o.transport,lookup=o.lookup,
  max_players=require('systems/player_context_service').max_players(),basic_limit=config.building_research_lab.max_count,
  advanced_limit=config.building_advanced_research_lab.max_count,current=current,allowed=o.allowed,
  player=function(id)return PlayerResource:GetPlayer(id)end,team=function(id)return PlayerResource:GetTeam(id)end,
  valid_unit=function(unit,index)
   if not unit or unit:IsNull()or unit:entindex()~=index or(unit.IsAlive and not unit:IsAlive())then return false end
   local ok,actual=pcall(EntIndexToHScript,index);return ok and actual==unit
  end,
  after=function(fn)return driver.after(0,fn,'compact_ui_dispatch')end,
  cancel=function()driver.cancel('compact_ui_dispatch')end,
  list=function()
   local response=bus.request(events.BUILDING_LIST_REQUEST,{handles_only=true})or{}
   local result={}
   for _,row in ipairs(response.buildings or{})do
    if row.building_id=='building_research_lab'or row.building_id=='building_advanced_research_lab'then
     row.team=row.unit:GetTeamNumber();result[#result+1]=row
    end
   end
   return result
  end,
  stamp=function(id)return tostring(world)..':'..learning_epoch..':'..tostring(versions[id]or 0)end,
  snapshot=function(id)
   local state=input(id)
   if not state.learning then
    local learning={}
    for _,row in ipairs(research)do
     learning[row.ability_name]=assert(builder.research_learning_state(row.ability_name,state.personal.legacy_levels,state.rebirth))
     metrics.learning_rows=metrics.learning_rows+1
    end
    state.learning=learning;metrics.learning_builds=metrics.learning_builds+1
   end
   return{learning=state.learning,_prepared_stamp=tostring(world)..':'..learning_epoch..':'..tostring(versions[id]or 0)}
  end,
  rebirth=function(id)return input(id).rebirth end,
  current_rebirth=function(id)
   local response=bus.request(events.HERO_PROGRESSION_GET_REQUEST,{player_id=id})or{}
   metrics.authority_reads=metrics.authority_reads+1
   return tonumber(response.snapshot and response.snapshot.rebirth_level)or 0
  end,
  levels=function(id)local out={}for key,value in pairs(input(id).personal.levels or{})do out[key]=value end;return out end,
  invalidate_learning=invalidate})
 return{reset=function()cache={};versions={};learning_epoch=learning_epoch+1;service.reset()end,
  inspect=function()return{service=service.inspect(),learning=metrics}end,
  dispose=function()live=false;cache={};service.dispose();driver.dispose()end}
end
return M
