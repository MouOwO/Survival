-- The existing archive transaction remains the only reward authority. This
-- adapter replaces the private display DTO and aliases its original nonce.
local M={}
local MAX=9007199254740991
local last_archive_login,next_login_period=nil,0
local function integer(v,min,max)return type(v)=='number'and v==math.floor(v)and v>=min and v<=max end
local function yes(v)return v==true or v==1 end
local function valid_config(row,P)
 return row and row.reward_id==P.tier_id and row.track==P.tier_id and row.period=='day'
  and row.monthly_only==false and row.auto_claim==false
  and type(row.base_item_ids)=='table'and #row.base_item_ids==1 and row.base_item_ids[1]==P.ticket_id
  and type(row.base_counts)=='table'and #row.base_counts==1 and tonumber(row.base_counts[1])==P.ticket_count
  and #(row.pass_item_ids or{})==0 and #(row.pass_counts or{})==0
end
function M.new(o)
 local L,T=o.lookup,o.transport;local P=assert(L.public_beta,'public_beta_static_required')
 assert(P.ticket_id=='special_lottery_ticket'and P.ticket_count==2,'public_beta_fixed_reward_invalid')
 local F=L.field_by_name;local root=assert(L.by_key['public_beta:state']);local receipt=assert(L.by_key['public_beta:receipt'])
 local states,retired,live={},{},true
 local function current()return live and(not o.current or o.current())end
 local function state_for(id,reopen)
  if not current()then return nil end
  if retired[id]then if not reopen then return nil end;retired[id]=nil end
  local player=o.player(id);if not player then return nil end
  local state=states[id]
  if not state or state.player~=player then state={player=player,values={},tokens={},requests={}};states[id]=state end
  return state
 end
 local function project(id,state,result,profile,full)
  local snapshot=o.snapshot(id,profile)
  assert(type(snapshot.login_key)=='string'and #snapshot.login_key>0,'public_beta_archive_login_required')
  if snapshot.login_key~=last_archive_login then
   assert(next_login_period<4294967295,'public_beta_login_period_exhausted')
   next_login_period=next_login_period+1;last_archive_login=snapshot.login_key
  end
  if state.login_key~=snapshot.login_key then state.login_key=snapshot.login_key;state.tokens={};state.requests={}end
  local staged={};local function put(r,name,value)staged[r*256+assert(F[name],'public_beta_field_missing:'..name)]={record=r,field=F[name],value=value}end
  local function uint(r,name,high,value)
   assert(integer(value,0,MAX),'public_beta_integer_invalid:'..name)
   put(r,name,value%4294967296);put(r,high,math.floor(value/4294967296))
  end
  local valid=valid_config(o.config(),P)and type(snapshot)=='table'and snapshot.ticket_id==P.ticket_id and snapshot.ticket_count==P.ticket_count
  local known=valid and yes(snapshot.ok)
  put(root,'known',known and 1 or 0)
  if known then
   put(root,'period',next_login_period)
   local day=tonumber(snapshot.day_key);assert(integer(day,0,4294967295),'public_beta_day_invalid')
   put(root,'public_beta_flags',(yes(snapshot.active)and 1 or 0)+(yes(snapshot.eligible)and 2 or 0)
    +(yes(snapshot.claimed)and 4 or 0)+(yes(snapshot.claim_pending)and 8 or 0)+(yes(snapshot.read_only)and 16 or 0))
   put(root,'day',day);put(root,'refresh_at',snapshot.refresh_at)
   -- A source sequence/revision change alone is not changed gift content.
   -- Carry their newest exact values with the next meaningful publication.
   uint(root,'source_revision','source_revision_hi',snapshot.revision)
   uint(root,'count','count_hi',snapshot.sequence)
   if not result or not state.requests[result.request_id]then result=snapshot.claim_result end
   local token=result and state.requests[result.request_id]
   if token then
    put(receipt,'known',1);put(receipt,'request_token',token)
    local date=result.day_key and tonumber(result.day_key)
    if date then assert(integer(date,0,4294967295),'public_beta_receipt_day_invalid');put(receipt,'day',date)end
    put(receipt,'success',yes(result.ok)and 1 or 0);put(receipt,'pending',yes(result.pending)and 1 or 0);put(receipt,'terminal',yes(result.terminal)and 1 or 0)
    -- The current UI deliberately displays a generic retry message. Internal
    -- errors never become runtime strings or a client-side success signal.
    put(receipt,'error_code',yes(result.ok)and 0 or 1)
   end
  end
  local changed=false
  local revision_fields={[F.source_revision]=true,[F.source_revision_hi]=true,[F.count]=true,[F.count_hi]=true}
  for key,old in pairs(state.values)do if not staged[key]and not revision_fields[old.field]then changed=true;break end end
  if not changed then for key,row in pairs(staged)do local old=state.values[key];if not revision_fields[row.field]and(not old or old.value~=row.value)then changed=true;break end end end
  if not changed and not full then return{},snapshot end
  local ops={}
  for key,old in pairs(state.values)do if not staged[key]then ops[#ops+1]={record=old.record,field=old.field,remove=true}end end
  for key,row in pairs(staged)do local old=state.values[key];if row.value~=nil and(not old or old.value~=row.value)then ops[#ops+1]=row end end
  for key,row in pairs(staged)do if row.value==nil then staged[key]=nil end end
  state.values=staged
  table.sort(ops,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end)
  return ops,snapshot
 end
 local function full_ops(state)local out={}for _,row in pairs(state.values)do out[#out+1]=row end;table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end);return out end
 local function publish(id,state,result,profile)
  local ops=project(id,state,result,profile,false)
  if #ops==0 or not T.is_open(id,10)then return{unchanged=true}end
  return T.publish(id,10,ops,{priority=true})
 end
 T.register_view(10,{snapshot=function(id)
  local state=state_for(id,true);if not state then return nil end
  project(id,state,nil,nil,true);if o.subscribe then o.subscribe(id,true)end
  return full_ops(state)
 end,close=function(id)if o.subscribe then o.subscribe(id,false)end end,
 intent=function(id,action,args)
  if action~='public_beta_claim'or not current()or not T.is_open(id,10)then return nil end
  local state=state_for(id);if not state then return nil end
  local token,session=args.request_token,args.session_token
  if not integer(token,1,16383)or not integer(session,1,16383)then return nil end
  if state.transport_session~=session then state.transport_session=session;state.tokens={};state.requests={}end
  local old=state.tokens[token]
  if old then return publish(id,state)end
  local nonce='beta_cw_'..session..'_'..id..'_'..token
  state.tokens[token]=nonce;state.requests[nonce]=token
  local result
  if not valid_config(o.config(),P)then result={request_id=nonce,ok=false,terminal=true,error='public_beta_configuration_invalid'}
  else result=o.claim(id,nonce)end
  if not current()or states[id]~=state or o.player(id)~=state.player then return nil,'public_beta_owner_changed'end
  return publish(id,state,result)
 end})
 local api={}
 function api.changed(id,result,profile)
  if not current()or not T.is_bound(id)then return false end
  if retired[id]then return true end
  if not T.is_open(id,10)then return true end
  local state=state_for(id);if state then return publish(id,state,result,profile)end
  return true
 end
 function api.reset()
  local old=states;states={}
  for id in pairs(old)do if T.is_open(id,10)and o.subscribe then o.subscribe(id,true)end end
 end
 function api.dispose()live=false;states={};retired={}end
 function api.disconnect(id)states[id]=nil;retired[id]=true;if o.subscribe then o.subscribe(id,false)end end
 function api.inspect(id)return{has_owner=states[id]~=nil,retired=retired[id]==true}end
 return api
end
return M
