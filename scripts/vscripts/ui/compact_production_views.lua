-- One private production lane per viewer. Selection identifiers are not
-- transaction nonces; consumptive intents retain independently cached tokens.
local M={}
local ACTION={production_train=8,production_research=9,production_auto=10,production_cancel=11}
function M.new(o)
 local factory=assert(require('ui/compact_production_projection').new(o.lookup))
 local players,live,owner_serial={},true,0
 local function current()return live and(not o.current or o.current())end
 local function owner(id)
  if not current()or not o.allowed(id)then return nil end
  local handle=o.player and o.player(id)or id;local state=players[id]
  if state and state.owner~=handle then players[id]=nil;state=nil end
  if not state then owner_serial=owner_serial+1;state={owner=handle,owner_serial=owner_serial,entity=0,selection=0,projection=factory.initialize(),used={},busy=false};players[id]=state end
  return state
 end
 local function snapshot(id,state)
  if state.entity<=0 then return{}end
  local stamp=o.stamp and o.stamp(id,state.entity)
  if stamp and state.cached_stamp==stamp and state.cached_entity==state.entity then return state.cached_source end
  local source=o.snapshot(id,state.entity)
  state.cached_stamp,state.cached_source,state.cached_entity=stamp,source,state.entity
  return source
 end
 local function publish(id,state,receipt,token,action,full)
  local ops,why=state.projection.update(snapshot(id,state),state.entity,math.max(1,state.selection),receipt,token,action)
  if not ops then return nil,why end
  if not o.transport.is_open(id,7)then return{unchanged=true}end
  return o.transport.publish(id,7,full and state.projection.full_ops()or ops,{full=full,priority=true})
 end
 local function select(id,action,args)
  local state=owner(id);if not state then return nil end
  local entity,selection=args.production_entity,args.production_selection
  if type(entity)~='number'or entity~=math.floor(entity)or entity<0 or entity>4294967295
   or type(selection)~='number'or selection~=math.floor(selection)or selection<=state.selection or selection>4294967295
   or action~=1 and action~=2 or action==2 and entity~=0 then return nil,'production_stale_selection'end
  state.entity,state.selection=entity,selection
  return publish(id,state,nil,nil,nil,true)
 end
 local function intent(id,action,args)
  local state=owner(id);local code=ACTION[action]
  if not state or not code or not o.transport.is_open(id,7)then return nil end
  local token=args.request_token
  if type(token)~='number'or token~=math.floor(token)or token<1 or token>16383 then return nil end
  local identity=action..':'..tostring(args.arg_a)..':'..tostring(args.arg_b)..':'..tostring(args.arg_c)
  local prior=state.used[token]
  if prior then if prior.identity~=identity then return nil,'production_nonce_reused'end;return{duplicate=true}end
  local function rejected(error_code)
   local receipt={source_entindex=args.arg_a or state.entity,success=0,error=error_code}
   state.used[token]={identity=identity,receipt=receipt}
   return publish(id,state,receipt,token,code,false)
  end
  if args.arg_a~=state.entity or args.arg_c~=state.selection or state.entity<=0 then return rejected('production_selection_mismatch')end
  local payload={PlayerID=id,source_entindex=state.entity,
   request_id='production_compact_'..tostring(args.session_token or o.generation or 0)..'_'..state.owner_serial..'_'..tostring(id)..'_'..token}
  if action=='production_cancel'then
   payload.job_id=state.projection.job(args.arg_b)
   if payload.job_id==nil then return rejected('research_job_not_found')end
  else
   local definition=factory.definition(args.arg_b)
   if not definition or(action=='production_train')~=(definition.kind=='training')then return rejected('training_definition_invalid')end
   if action=='production_train'then payload.training_id=definition.key else payload.technology_group=definition.key end
  end
  -- Mark before calling the real services: they can synchronously publish
  -- resource/queue changes and re-enter UI subscribers. Never execute twice.
  state.used[token]={identity=identity};state.busy=true
  local ok,receipt=pcall(o.execute,action,payload)
  state.busy=false
  if not current()or players[id]~=state or(o.player and o.player(id)~=state.owner)
   or state.entity~=args.arg_a or state.selection~=args.arg_c then return nil,'production_owner_changed'end
  if not ok or type(receipt)~='table'then receipt={source_entindex=state.entity,success=0,error='production_failed'}end
  state.used[token].receipt=receipt
  return publish(id,state,receipt,token,code,false)
 end
 o.transport.register_view(7,{snapshot=function(id)
  local state=owner(id);if not state then return nil end
  local ops,why=state.projection.update(snapshot(id,state),state.entity,math.max(1,state.selection));if not ops then return nil,why end
  return state.projection.full_ops()
 end,close=function(id)local state=players[id];if state then state.entity=0 end end,
 input_record='production:input',input_action_field='production_action',input_actions={[1]=true,[2]=true},
 input_fields={production_entity=true,production_selection=true},input=select,intent=intent})
 local api={}
 function api.changed(id,payload)
  local state=owner(id);if not state then return false end
  -- Bound clients must never fall back to the large selected-combat event.
  if not o.transport.is_bound(id)then return false end
  if state.entity<=0 or not o.transport.is_open(id,7)or state.busy then return true end
  if payload and payload.source_entindex and tonumber(payload.source_entindex)~=state.entity then return true end
  local result,why=publish(id,state,nil,nil,nil,false);if not result and o.error then o.error(why)end
  return true
 end
 function api.reset()players={}end
 function api.dispose()live=false;players={}end
 function api.inspect(id)local state=players[id];return state and{entity=state.entity,selection=state.selection,metrics=state.projection.inspect()}or{}end
 return api
end
return M
