-- Selection identity is independent of business/transaction nonces.
local M={}
function M.new(o)
 local factory=assert(require("ui/compact_selected_projection").new(o.lookup))
 local active,live,failures={},true,{}
 local function current()return live and(not o.current or o.current())end
 local function unknown()return assert(factory.initialize({},0,1)).full_ops()end
 local function input(id,action,args)
  if not current()or not o.allowed(id)then return nil end
  local entity,token=args.selected_entity,args.selected_token
  if type(entity)~="number"or entity~=math.floor(entity)or entity<0 or entity>4294967295
   or type(token)~="number"or token~=math.floor(token)or token<1 or token>4294967295 then return nil end
  local prior=active[id];if prior and token<=prior.token then return nil,"selected_stale_input"end
  if action~=1 and action~=2 or action==2 and entity~=0 then return nil end
  local source=action==1 and o.snapshot(id,entity)or nil
  local valid_source=source and source.success==1
  local state,ops=factory.initialize(source or{},entity,token)
  if not state then
   failures[id]=tostring(ops):match("^([^:]+:[^:]+)")or"selected_projection_rejected"
   state,ops=assert(factory.initialize({error_code=2},entity,token))
  else failures[id]=nil end
  active[id]={entity=entity,token=token,state=state}
  o.selected(id,action==1 and valid_source and entity or nil)
  local first,later=state.split_ops()
  o.transport.publish(id,5,first,{full=true,priority=true})
  if #later>0 then o.transport.publish(id,5,later,{priority=true})end
  return true
 end
 o.transport.register_view(5,{snapshot=function(id)if not current()then return nil end local s=active[id];return s and s.state.full_ops()or unknown()end,
  close=function(id)if current()then active[id]=nil;o.selected(id,nil)end end,
  input_record="selected:input",input_action_field="selected_action",input_actions={[1]=true,[2]=true},
  input_fields={selected_entity=true,selected_token=true},input=input})
 local api={}
 function api.changed(id,source)
  if not current()or not o.transport.is_open(id,5)then return nil end
  local s=active[id];if not s or tonumber(source.entindex)~=s.entity then return nil end
  local ops,why=s.state.update(source)
  if not ops then
   failures[id]=tostring(why):match("^([^:]+:[^:]+)")or"selected_projection_rejected"
   ops=assert(s.state.update({success=0,error_code=2}))
  else failures[id]=nil end
  if #ops>0 then return o.transport.publish(id,5,ops,{priority=true})end
  return{unchanged=true}
 end
 function api.reset()for id in pairs(active)do o.selected(id,nil)end active={}end
 function api.dispose()live=false;api.reset()end
 function api.inspect()return{failures=failures}end
 return api
end
return M
