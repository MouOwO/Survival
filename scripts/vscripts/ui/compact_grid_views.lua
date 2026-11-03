-- View 4 bridges typed presentation/input to the existing authoritative router.
-- No alternative placement, ownership, cost, cooldown or commit rule lives here.
local wire=require('ui/compact_wire')
local M={}
local INPUT_FIELDS={grid_session=true,grid_request=true,grid_profile=true,grid_actor=true,grid_ability=true,
 grid_x_hi=true,grid_x_lo=true,grid_y_hi=true,grid_y_lo=true,grid_z_hi=true,grid_z_lo=true}
local EVENTS={[1]='ui_grid_placement_validate',[2]='ui_grid_placement_pose',[3]='ui_grid_placement_preview_end',
 [4]='ui_grid_placement_commit',[5]='ui_grid_placement_pause_area'}
local function integer(value,min,max)return type(value)=='number' and value==math.floor(value) and value>=min and value<=max end
function M.new(o)
 local transport,lookup=o.transport,o.lookup
 local factory=assert(require('ui/compact_grid_projection').new(lookup))
 local entries,capturing,scopes={},{},{}
 local scheduler=o.scheduler or require('core/scheduler')
 local backgrounds,delivered,bulk_modes={},{},{}
 local restore_views={}
 local live=true
 local function active()return live and (not o.current or o.current())end
 local api={}
 local function task(id)return 'grid_static_delivery:'..tostring(id)end
 local function remember(id,ops)
  local values=delivered[id]or{};delivered[id]=values
  for _,op in ipairs(ops)do values[op.record]=values[op.record]or{};values[op.record][op.field]=op.remove and nil or op.value end
 end
 local function delivered_ops(id)
  local out={};for record,row in pairs(delivered[id]or{})do for field,value in pairs(row)do out[#out+1]={record=record,field=field,value=value}end end
  table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end);return out
 end
 local function cancel_background(id)backgrounds[id]=nil;scheduler.cancel(task(id))end
 local function stage_static(id,state,ops)
  cancel_background(id);delivered[id]={};bulk_modes[id]=nil
  local F=lookup.field_by_name;local meta=lookup.by_key['grid:static:meta'];local base=0
  for _,op in ipairs(ops)do if op.record==meta and op.field==F.grid_atlas_base then base=op.value end end
  if base~=0 or #ops<=32 then remember(id,ops);return ops end
  if transport.bulk_static_enabled and transport.bulk_static_enabled(id)and transport.publish_bulk_static then
   local initial,words,metadata={},{},{}
   for _,op in ipairs(ops)do local row=lookup.records[op.record]
    if row and row.kind=='static_word'then if not op.remove then words[tonumber(row.business_id)]=op.value end
    else
     initial[#initial+1]={record=op.record,field=op.field,value=op.record==meta and op.field==F.grid_complete and 0 or op.value,remove=op.remove}
     if op.record==meta then metadata[op.field]=op.value end
    end
   end
   local cells=metadata[F.grid_width]*metadata[F.grid_height]
   assert(cells>=1 and cells<=65536,'grid_bulk_cell_limit')
   local length=math.ceil(cells/4);local bytes={}
   for n=0,length-1 do local word=words[math.floor(n/4)+1]or 0;bytes[n+1]=string.char(math.floor(word/256^(n%4))%256)end
   local raw=table.concat(bytes);initial[#initial+1]={record=meta,field=F.types,value=1}
   local background={state=state,bulk=true,raw=raw,scope=metadata[F.grid_scope],attempts=0}
   backgrounds[id]=background;bulk_modes[id]=true;remember(id,initial)
   local function current()
    return active()and backgrounds[id]==background and entries[id]and entries[id][6]==state and transport.is_open(id,6)
   end
   local function step()
    if not current()then return end
    background.attempts=background.attempts+1
    if background.attempts>128 then backgrounds[id]=nil;print('[CompactGrid] bulk_binding_timeout');return end
    if transport.queue_depth and transport.queue_depth(id,6)>0 then return 0.05 end
    local binding=transport.bulk_binding(id)
    if not binding or not binding.epoch or binding.epoch<1 or not binding.revision or binding.revision<1 then return 0.05 end
    -- Every staged bitmap belongs to the preceding full metadata transaction
    -- (R1). A real K delta may already have reached R2 while we waited for the
    -- queue; it must overlay this original base rather than change its identity.
    local epoch,revision=binding.epoch,1
    local result,why=transport.publish_bulk_static(id,raw,background.scope,{epoch=epoch,base_revision=revision,on_complete=function()
     if not current()then return end
     local latest=transport.bulk_binding(id)
     if not latest or latest.epoch~=epoch then return end
     local final={{record=meta,field=F.grid_complete,value=1}}
     remember(id,final);backgrounds[id]=nil;transport.publish(id,6,final,{priority=false})
    end})
    if not result then backgrounds[id]=nil;print('[CompactGrid] bulk_publish_rejected reason='..tostring(why))end
   end
   scheduler.after(0.05,step,task(id));return initial
  end
  local initial,pending,order={},{},{}
  local background={state=state,pending=pending,order=order,cursor=1,priority={},priority_cursor=1,queued={}}
  for _,op in ipairs(ops)do
   local row=lookup.records[op.record]
   if row and row.kind=='static_word' then pending[op.record]=op;order[#order+1]=op.record
   else
    initial[#initial+1]=op
    if op.record==meta then background[op.field]=op.value end
   end
  end
  for _,op in ipairs(initial)do if op.record==meta and op.field==F.grid_complete then op={record=meta,field=F.grid_complete,value=0};for index,current in ipairs(initial)do if current.record==meta and current.field==F.grid_complete then initial[index]=op end end end end
  remember(id,initial);backgrounds[id]=background
  local function step()
   if not active()or backgrounds[id]~=background or not entries[id]or entries[id][6]~=state or not transport.is_open(id,6)then return end
   if transport.queue_depth and transport.queue_depth(id,6)>0 then return 0.05 end
   local batch={}
   while #batch<4 do
    local record
    while background.priority_cursor<=#background.priority do
     record=background.priority[background.priority_cursor];background.priority_cursor=background.priority_cursor+1
     if pending[record]then break end;record=nil
    end
    if not record then
     while background.cursor<=#order do record=order[background.cursor];background.cursor=background.cursor+1;if pending[record]then break end;record=nil end
    end
    if not record then break end
    batch[#batch+1]=pending[record];pending[record]=nil
   end
   if #batch==0 then
    local final={{record=meta,field=F.grid_complete,value=1}};remember(id,final);transport.publish(id,6,final,{priority=false});backgrounds[id]=nil;return
   end
   remember(id,batch);transport.publish(id,6,batch,{priority=false});return 0.05
  end
  scheduler.after(0.05,step,task(id));return initial
 end
 local function focus(id,x,y)
  local bg=backgrounds[id];if not bg or bg.bulk then return end;local F=lookup.field_by_name
  local size,h=bg[F.grid_size],bg[F.grid_height];if not size or not h then return end
  local gx,gy=math.floor(x/size),math.floor(y/size);local key=gx..':'..gy;if bg.focus==key then return end;bg.focus=key
  local ox,oy,w=bg[F.grid_origin_x],bg[F.grid_origin_y],bg[F.grid_width]
  local radius=math.ceil(((lookup.grid.maps.template_map.preview_visual or{}).radius or 1280)/size)
  for column=math.max(0,gx-ox-radius),math.min(w-1,gx-ox+radius)do
   local y0,y1=math.max(0,gy-oy-radius),math.min(h-1,gy-oy+radius)
   for word=math.floor((column*h+y0)/16),math.floor((column*h+y1)/16)do
    local record=lookup.by_key['grid:static:word:'..(word+1)]
    if bg.pending[record]and not bg.queued[record]then bg.priority[#bg.priority+1]=record;bg.queued[record]=true end
   end
  end
 end
 local function ingest(id,event,payload,view)
  if not active()then return nil,'grid_world_expired' end
  local scope_reset=false
  if event=='ui_grid_placement_profiles'then
   local next_scope=payload.grid_scope_version
   if scopes[id] and scopes[id]~=next_scope then
    scope_reset=true;cancel_background(id);entries[id][4]=factory.initialize()
    if entries[id][6]then
     entries[id][6]=factory.initialize();delivered[id]={}
     local clear=assert(entries[id][6].ingest('ui_grid_placement_static_area',{area='',grid_scope_version=next_scope}))
     remember(id,clear);transport.publish(id,6,clear,{full=true,priority=false})
    end
   end
   scopes[id]=next_scope
  end
  local state=entries[id] and entries[id][view];if not state then return nil,'grid_view_closed' end
  local operations,why=state.ingest(event,payload)
  if not operations then return nil,why end
  if not (capturing[id] and capturing[id][view]) and #operations>0 then
   if view==6 then
    if #operations>32 then
     operations=stage_static(id,state,state.full_ops());return transport.publish(id,6,operations,{full=true,priority=false})
    end
    if bulk_modes[id]then
     -- The bulk baseline is deliberately not thousands of cw receiver fields.
     -- An absent cw field's remove is otherwise a no-op. Explicit zero keeps
     -- the original bitmap semantics and makes it a real indexed delta.
     local converted={};for _,op in ipairs(operations)do local row=lookup.records[op.record]
      if op.remove and row and row.kind=='static_word'and op.field==lookup.field_by_name.grid_word then converted[#converted+1]={record=op.record,field=op.field,value=0}
      else converted[#converted+1]=op end
     end;operations=converted
    end
    remember(id,operations)
   end
   return transport.publish(id,view,operations,{full=scope_reset,priority=event~='ui_grid_placement_static_area' and event~='ui_grid_placement_area'})
  end
  return true
 end
 function api.send(id,event,payload)
  if not active() or not transport.is_bound(id)then return false end
  -- A negotiated client never also receives a large legacy grid DTO. Closed
  -- views own no projector or advisory scan and do not accumulate stale work.
  local view=event=='ui_grid_placement_static_area' and 6 or 4
  if entries[id] and entries[id][view] and transport.is_open(id,view)then
   local okay,why=ingest(id,event,payload,view)
   if not okay and why then print('[CompactGrid] projection_rejected event='..tostring(event)..' reason='..tostring(why))end
  end
  return true
 end
 local function open(id,view)
  if not active()then return nil end
  entries[id]=entries[id]or{};entries[id][view]=factory.initialize();capturing[id]=capturing[id]or{};capturing[id][view]=true
  local ok,why=pcall(view==6 and o.bootstrap_static or o.bootstrap,id)
  capturing[id][view]=nil
  if not ok then entries[id][view]=nil;error(why,0)end
  local operations=entries[id][view].full_ops()
  if view==6 and #operations==0 then operations=assert(entries[id][view].ingest('ui_grid_placement_static_area',{area='',grid_scope_version=scopes[id]or 1}))end
  return view==6 and stage_static(id,entries[id][view],operations)or operations
 end
 transport.register_view(6,{bulk_static=true,open=function(id)return open(id,6)end,snapshot=function(id)
  if not active()then return nil end
  if bulk_modes[id]and entries[id]and entries[id][6]then return stage_static(id,entries[id][6],entries[id][6].full_ops())end
  return entries[id] and entries[id][6] and delivered_ops(id)or open(id,6)
 end,close=function(id)cancel_background(id);delivered[id]=nil;bulk_modes[id]=nil;if entries[id]then entries[id][6]=nil end;if o.close_static then o.close_static(id)end;return true end})
 transport.register_view(4,{open=function(id)return open(id,4)end,snapshot=function(id)
  if not active()then return nil end
  return entries[id] and entries[id][4] and entries[id][4].full_ops() or open(id,4)
 end,close=function(id)
  if entries[id]then entries[id][4]=nil end;if active() and o.close then o.close(id)end;return true
 end,input_fields=INPUT_FIELDS,input_record='grid:input',input_action_field='grid_action',input_actions={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true},
 input=function(id,action,args,revision)
  if not active() or not entries[id] or not entries[id][4] or not transport.is_open(id,4) or not EVENTS[action]then return nil end
  if not integer(args.grid_session,1,4294967295) or not integer(args.grid_request,1,4294967295)then return nil end
  local payload={PlayerID=id,session_id=args.grid_session,request_id=args.grid_request}
  if action==1 or action==2 or action==4 then
   local profile=factory.profile(args.grid_profile)
   if not profile or not integer(args.grid_actor,0,4294967295) or not integer(args.grid_ability,0,4294967295)then return nil end
   payload.ability_name=profile.ability_name;payload.entindex=args.grid_actor;payload.ability_entindex=args.grid_ability
   for _,axis in ipairs({'x','y','z'})do
    local value=wire.float64_from_words(args['grid_'..axis..'_hi'],args['grid_'..axis..'_lo'])
    if value==nil then return nil end;payload[axis]=value
   end
   focus(id,payload.x,payload.y)
  end
  -- incomingRevision is only transport ordering; preview session/request are
  -- independent uint32 counters and never consume reward/payment nonce space.
  return o.dispatch(EVENTS[action],payload,revision)
 end})
 function api.dispose()if not live then return end;live=false;for id in pairs(backgrounds)do cancel_background(id)end;entries,capturing,delivered,bulk_modes={},{},{},{}end
 function api.reset()
  restore_views={};for id in pairs(entries)do restore_views[id]={[4]=transport.is_open(id,4),[6]=transport.is_open(id,6)}end
  for id in pairs(backgrounds)do cancel_background(id)end;entries,capturing,delivered,scopes,bulk_modes={},{},{},{},{}
 end
 function api.restore()
  local pending=restore_views;restore_views={}
  for id,views in pairs(pending)do for _,view in ipairs({4,6})do if views[view]then transport.publish(id,view,open(id,view),{full=true,priority=view==4})end end end
 end
 function api.inspect(id)return entries[id] and entries[id][4] and entries[id][4].inspect()or nil end
 return api
end
return M
