-- Selection identity is independent of business/transaction nonces.
local M={}
function M.new(o)
 local factory=assert(require("ui/compact_selected_projection").new(o.lookup))
 local compact_factory=assert(require("ui/compact_selected_projection").new(o.lookup,{derive_aliases=true}))
 local active,live,failures={},true,{}
 local function current()return live and(not o.current or o.current())end
 local function aliases(id)return o.transport.selected_aliases_enabled and o.transport.selected_aliases_enabled(id)end
 local api={}
 local function unknown()return assert(factory.initialize({},0,1)).full_ops()end
 local function input(id,action,args)
  if not current()or not o.allowed(id)then return nil end
  local entity,token=args.selected_entity,args.selected_token
  if type(entity)~="number"or entity~=math.floor(entity)or entity<0 or entity>4294967295
   or type(token)~="number"or token~=math.floor(token)or token<1 or token>4294967295 then return nil end
  local prior=active[id];if prior and token<=prior.token then return nil,"selected_stale_input"end
  if action~=1 and action~=2 or action==2 and entity~=0 then return nil end
  if prior then prior.pending=nil end
  local source=action==1 and o.snapshot(id,entity)or nil
  local valid_source=source and source.success==1
  if action==1 and prior and prior.entity==entity and prior.aliases==aliases(id)then
   local delta=prior.state.update(source or{},token)
   if delta then
    prior.token=token;failures[id]=nil
    o.selected(id,valid_source and entity or nil)
    if #delta>0 then o.transport.publish(id,5,delta,{priority=true})end
    return true
   end
   -- Invalid data retains the existing explicit error/full recovery path.
  end
  local own_factory=aliases(id)and compact_factory or factory
  local state,ops=own_factory.initialize(source or{},entity,token)
  if not state then
   failures[id]=tostring(ops):match("^([^:]+:[^:]+)")or"selected_projection_rejected"
   state,ops=assert(own_factory.initialize({error_code=2},entity,token))
  else failures[id]=nil end
  active[id]={entity=entity,token=token,state=state,aliases=aliases(id)}
  o.selected(id,action==1 and valid_source and entity or nil)
  local first,later=state.split_ops()
  o.transport.publish(id,5,first,{full=true,priority=true})
  if #later>0 then o.transport.publish(id,5,later,{priority=true})end
  return true
 end
 o.transport.register_view(5,{derive_selected_aliases=true,
  open=function(id)
   local s=active[id];if s and s.aliases~=aliases(id)then active[id]=nil;o.selected(id,nil);return unknown()end
  end,
  on_idle=function(id)
   local s=active[id];if not current()or not s or not s.pending then return end
   local source=s.pending;s.pending=nil;api.changed(id,source)
  end,snapshot=function(id)if not current()then return nil end local s=active[id];return s and s.state.full_ops()or unknown()end,
  close=function(id)if current()then active[id]=nil;o.selected(id,nil)end end,
  input_record="selected:input",input_action_field="selected_action",input_actions={[1]=true,[2]=true},
  input_fields={selected_entity=true,selected_token=true},input=input})
 function api.changed(id,source)
  if not current()or not o.transport.is_open(id,5)then return nil end
  local s=active[id];if not s or tonumber(source.entindex)~=s.entity then return nil end
  s.pending=nil
  local ops,why=s.state.update(source)
  if not ops then
   failures[id]=tostring(why):match("^([^:]+:[^:]+)")or"selected_projection_rejected"
   ops=assert(s.state.update({success=0,error_code=2}))
  else failures[id]=nil end
  if #ops>0 then return o.transport.publish(id,5,ops,{priority=true})end
  return{unchanged=true}
 end
 -- Keep legacy/initial output until compatible Open AND selection exist.
 -- Busy output keeps one latest source, flushed on transport completion.
 function api.owner_hero_changed(id,source)
  if not current()or not o.allowed(id)then return nil end
  local mode=o.transport.owner_stats_mode and o.transport.owner_stats_mode(id)or "pending"
  if mode=="legacy"then return false end
  if mode~="compact"then return nil end
  -- Capability belongs to this player/session, visibility belongs to the view.
  -- Closing a modern HUD must never reactivate large legacy broadcasts.
  if not o.transport.is_open(id,5)then return true end
  local s=active[id];if not s then return true end
  if s.entity~=tonumber(source.entindex)then return true end
  if o.transport.queue_depth(id,5)>0 then s.pending=source;return true end
  api.changed(id,source);return true
 end
 function api.reset()for id in pairs(active)do o.selected(id,nil)end active={}end
 function api.dispose()live=false;api.reset()end
 function api.inspect()return{failures=failures}end
 return api
end
return M
