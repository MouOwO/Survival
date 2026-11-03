-- Private presentation only. Costs, jobs and cancellation remain in the worker
-- and research services. One immutable index; bounded 8+19+7 dynamic records.
local wire=require('ui/compact_wire')
local M={}
local MAX=9007199254740991
local function need(v,e)if not v then error(e,0)end end
local function guard(fn,...)local ok,a,b=pcall(fn,...);if ok then return a,b end return nil,tostring(a)end
local function number(v,min,max)return type(v)=='number'and v==math.floor(v)and v>=min and v<=max end
function M.new(L)return guard(function()
 local P,F=assert(L.production,'production_seed_required'),assert(L.field_by_name)
 local function record(key)return assert(L.by_key[key],'production_record_missing:'..key)end
 local root=record('production:state');local options,research,jobs,receipts={},{},{},{}
 local by_record,by_group,errors,statuses={},{},{},{}
 for index,text in ipairs(P.errors)do errors[text]=index-1 end
 for index,text in ipairs(P.status_codes)do statuses[text]=index-1 end
 for _,row in ipairs(P.training)do local id=record('production:training:'..row.training_id);options[row.training_id]=id;by_record[id]={kind='training',key=row.training_id}end
 for _,row in ipairs(P.research)do local id=record('production:research:'..row.group);research[row.ability_name]=id;by_group[row.group]=id;by_record[id]={kind='research',key=row.group,ability_name=row.ability_name}end
 for n=1,7 do jobs[n]=record('production:job:'..n)end
 for n=1,8 do receipts[n]=record('production:receipt:'..n)end
 local factory={}
 function factory.definition(id)return by_record[id]end
 function factory.initialize()
  local values,handles,reverse,next_handle,history={},{},{},0,{}
  local last_stamp,last_entity,last_selection
  local metrics={updates=0,stable=0,record_visits=0,changed_fields=0}
  local api={}
  function api.job(handle)return reverse[handle]end
  local function handle(job,alive_handles)
   if not job or job.job_id==nil then return nil end
   local key=tostring(job.job_id);local value=handles[key]
   if not value then next_handle=next_handle+1;need(next_handle<=4294967295,'production_job_handle_exhausted');value=next_handle;handles[key]=value end
   reverse[value]=job.job_id;alive_handles[key]=value;return value
  end
  function api.update(source,entity,selection,receipt,token,action)
   return guard(function()
    need(number(entity,0,4294967295)and number(selection,1,4294967295),'production_binding_invalid')
    local stamp=source and source._production_stamp
    local stable=stamp~=nil and stamp==last_stamp and entity==last_entity and selection==last_selection
    if stable and not receipt then metrics.updates=metrics.updates+1;metrics.stable=metrics.stable+1;return{}end
    local staged={};local function put(id,name,value)
     local field=assert(F[name],'production_field_missing:'..name);if type(value)=='boolean'then value=value and 1 or 0 end
     staged[id*256+field]={record=id,field=field,value=value}
    end
    local function uint(id,name,value,hi)
     value=tonumber(value)or 0;need(number(value,0,MAX),'production_integer_invalid:'..name)
     put(id,name,value%4294967296);put(id,hi or name..'_hi',math.floor(value/4294967296))
    end
    local function clock(id,name,value)
     local words=assert(wire.float64_words(tonumber(value)or 0),'production_clock_invalid')
     put(id,'production_'..name..'_hi',words.hi);put(id,'production_'..name..'_lo',words.lo)
    end
    local function error_code(text)return errors[tostring(text or '')]or 1 end
    local function stage_receipt(index,row)
     local id=receipts[index]
     put(id,'known',1);put(id,'request_token',row.token);put(id,'action_code',row.action);put(id,'production_entity',row.entity);put(id,'production_selection',row.selection)
     put(id,'success',row.success);put(id,'terminal',1);put(id,'production_flags',row.queued and 1 or 0);put(id,'production_refunded',row.refunded);put(id,'error_code',error_code(row.error))
    end
    if receipt then
     need(number(token,1,16383)and number(action,8,11),'production_receipt_binding_invalid')
     local index=(token-1)%8+1
     history[index]={token=token,action=action,entity=receipt.source_entindex or entity,selection=selection,
      success=receipt.success==1,queued=receipt.queued==1,refunded=receipt.refunded==1,error=receipt.error or receipt.error_code or''}
     if stable then
      stage_receipt(index,history[index]);local out={}
      for key,row in pairs(staged)do local old=values[key];if not old or old.value~=row.value then out[#out+1]=row;values[key]=row end end
      table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end)
      metrics.updates=metrics.updates+1;metrics.changed_fields=metrics.changed_fields+#out;return out
     end
    end
    local training=source and source.training;local r=source and source.research
    local kind=type(training)=='table'and type(training.options)=='table'and 1 or type(r)=='table'and 2 or 0
    put(root,'known',kind>0);put(root,'production_entity',entity);put(root,'production_selection',selection);put(root,'production_kind',kind)
    -- Clear stale record fields when the selected entity/type changes. This is
    -- a fixed-size view, never an entity/world or full catalogue scan.
    local previous=values[root*256+F.production_entity]
    local changed_entity=not previous or previous.value~=entity
    if changed_entity then handles,reverse,next_handle={},{},0 end
    reverse={};local alive_handles={}
    if kind>0 then
     local state=kind==1 and training or r
     put(root,'production_revision',tonumber(kind==1 and state.queue_revision or state.sequence)or 0)
     put(root,'production_capacity',tonumber(state.queue_capacity or state.capacity)or 7)
     put(root,'production_queue_count',tonumber(state.queue_count)or 0)
     put(root,'error_code',error_code(state.blocked_reason));put(root,'automatic',state.auto_enabled==1)
     for _,key in ipairs({'started','finish','duration','next'})do clock(root,key,state[key=='next'and'next_start_at'or key=='duration'and'duration'or key..'_at'])end
     if kind==1 then
      need(#training.options==#P.training,'production_training_shape_changed')
      for _,row in ipairs(training.options)do
       local id=options[row.training_id];need(id,'production_training_unknown');metrics.record_visits=metrics.record_visits+1
       uint(id,'count',row.count);put(id,'production_max_count',row.max_count);put(id,'production_queued_count',row.queued_count or 0)
       put(id,'production_flags',(row.available==1 and 1 or 0)+(row.prerequisite_met==1 and 2 or 0)+(row.completed==1 and 4 or 0))
       put(id,'error_code',error_code(row.reason))
      end
     else
      for name,row in pairs(r.abilities_by_name or{})do
       local id=research[name];need(id,'production_research_unknown');metrics.record_visits=metrics.record_visits+1
       put(id,'known',1);put(id,'level',row.current_level or 0);put(id,'production_reserved_level',row.reserved_level or(r.reserved_levels or{})[by_record[id].key]or 0)
       local status=statuses[tostring(row.research_status_code or'')];need(status~=nil,'production_status_unknown')
       put(id,'production_status',status)
       put(id,'production_flags',(row.available==1 and 1 or 0)+(row.prerequisite_met==1 and 2 or 0)+(row.completed==1 and 4 or 0)+(row.auto_research_enabled==1 and 8 or 0)+(row.auto_research_available==1 and 16 or 0))
       uint(id,'wood',row.cost_wood);uint(id,'gold',row.cost_gold)
      end
     end
     local list={};local head=kind==1 and training.active_job or r.active_job
     local blocked=kind==1 and training.blocked_head or r.blocked_head
     if head and head.job_id~=nil then list[#list+1]={job=head,state=1}
     elseif blocked and blocked.job_id~=nil then list[#list+1]={job=blocked,state=2}end
     for _,job in ipairs(state.queued or{})do list[#list+1]={job=job,state=3}end
     need(#list<=7,'production_queue_capacity_changed')
     for index,item in ipairs(list)do
      local job,id=item.job,jobs[index];local definition=kind==1 and options[job.training_id]or research[job.ability_name]
      if not definition and kind==2 then definition=by_group[job.technology_group or job.group]end
      need(definition,'production_job_definition_unknown');metrics.record_visits=metrics.record_visits+1
      put(id,'production_job_handle',handle(job,alive_handles));put(id,'production_job_state',item.state);put(id,'target_record',definition);put(id,'level',job.target_level or job.level or 0)
      clock(id,'started',item.state==1 and(kind==2 and r.started_at or job.started_at)or job.started_at)
      clock(id,'finish',item.state==1 and(kind==2 and r.finish_at or job.finish_at)or job.finish_at)
      clock(id,'duration',kind==2 and r.duration or job.duration)
     end
     -- Fields on unused records are removed below, including deleted jobs.
    end
    for index,row in pairs(history)do stage_receipt(index,row)end
    local out={}
    for key,old in pairs(values)do if not staged[key]then out[#out+1]={record=old.record,field=old.field,remove=true}end end
    for key,row in pairs(staged)do local old=values[key];if row.value~=nil and(not old or old.value~=row.value)then out[#out+1]={record=row.record,field=row.field,value=row.value}end end
    for key,row in pairs(staged)do if row.value==nil then staged[key]=nil end end
    table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end)
    values=staged;handles=alive_handles;last_stamp,last_entity,last_selection=stamp,entity,selection;metrics.updates=metrics.updates+1;metrics.changed_fields=metrics.changed_fields+#out;if #out==0 then metrics.stable=metrics.stable+1 end
    return out
   end)
  end
  function api.full_ops()local out={}for _,row in pairs(values)do out[#out+1]={record=row.record,field=row.field,value=row.value}end;table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end);return out end
  function api.inspect()return metrics end
  return api
 end
 return factory
end)end
return M
