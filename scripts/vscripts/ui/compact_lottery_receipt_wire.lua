-- Successful lottery receipt encoding only. No roll, reward, storage or timer.
-- Lua 5.1 encoder counterpart of lottery_receipt_payload.js.
-- API: Create(catalogue).Encode(view, revision, receipt, changes) -> raw string.
-- Catalogue index O(N) once; encoding O(K + G log G + R), G<=128, R<=10.
local M={}
local UINT,SAFE=4294967295,9007199254740991
local GROUPS={
 state={"known","pending","enabled","balance","balance_hi","progress","progress_hi","level"},
 pool={"known","tickets","tickets_hi","draws","draws_hi","unlocked","unlock_progress","update_unread","notice_unread"},
 currency={"known","owned_count","owned_count_hi"},
 item={"known","owned_count","owned_count_hi","owned","at_max_owned"},
}
local function need(ok,why)if not ok then error(why,0)end end
local function integer(n,min,max)
 return type(n)=="number" and n==n and n%1==0 and n>=min and n<=max
end
local function uint(n,max)
 need(integer(n,0,max or UINT),"receipt_integer_invalid")
 local out={}
 repeat
  local b=n%128;n=math.floor(n/128)
  out[#out+1]=string.char(b+(n>0 and 128 or 0))
 until n==0
 return table.concat(out)
end
local function js_truthy(v)
 return v~=nil and v~=false and v~=0 and v~="" and not(type(v)=="number" and v~=v)
end
function M.Create(catalogue)
 need(type(catalogue)=="table","receipt_schema_required")
 local C=catalogue.Data or catalogue
 -- The server lookup keeps only immutable duplicate-display defaults and pool
 -- membership, not complete descriptions/images. Build these indices once.
 if C.lottery_receipt then
  local seed=C.lottery_receipt
  need(seed.wire_version==1,"receipt_lookup_version_invalid")
  local definitions,snapshots={},{}
  for id,points in pairs(seed.duplicate_points)do definitions["lottery:item:"..id]={definition={duplicate_points=points}}end
  for _,p in ipairs(seed.pools)do
   local items={};for _,id in ipairs(p.items)do items[#items+1]={id=id}end
   snapshots[#snapshots+1]={selected_pool_id=p.id,items=items}
  end
  C={sha256=C.sha256,fields=C.fields,records=C.records,definitions=definitions,
   auxiliary={lottery_public={snapshots=snapshots}}}
 end
 need(type(C.sha256)=="string" and #C.sha256==64 and not C.sha256:find("[^a-f0-9]"),"receipt_schema_required")
 local R,ByKey,F,N,P={},{},{},{},{}
 local index_visits=0
 for _,field in pairs(C.fields)do F[field.name]=field.id;N[field.id]=field.name;index_visits=index_visits+1 end
 for _,row in pairs(C.records)do
  if not js_truthy(row.tombstone)then R[row.id]=row;ByKey[row.key]=row.id end
  index_visits=index_visits+1
 end
 for i,snapshot in ipairs(C.auxiliary.lottery_public.snapshots)do
  local allowed={}
  for _,row in ipairs(snapshot.items)do
   local id=ByKey["lottery:item:"..row.id]
   -- JS allows the absent mapping as an unusable property; valid records are
   -- required separately before any item can be encoded.
   if id~=nil then allowed[id]=true end
  end
  P[200+i]={id=snapshot.selected_pool_id,record=ByKey["lottery:pool:"..snapshot.selected_pool_id],allowed=allowed}
 end
 local function record(id)
  local value=R[id];need(value and value.domain=="lottery","receipt_record_invalid");return value
 end
 local function group(id,view)
  local value=record(id)
  local kind=value.key=="lottery:state" and "state" or value.kind
  need(GROUPS[kind] and value.key~="lottery:receipt","receipt_state_record_forbidden")
  if view~=nil and kind=="item"then need(P[view]and P[view].allowed[id],"receipt_item_not_in_pool")end
  return GROUPS[kind]
 end
 local function pool(view)need(P[view],"receipt_view_invalid");return P[view]end
 local function item(view,id)
  local selected=pool(view);local row=record(id)
  need(selected.allowed[id] and row.kind=="item","receipt_item_not_in_pool")
  local definition=C.definitions[row.key]
  need(definition and definition.definition,"receipt_item_definition_missing")
  return definition.definition
 end
 local function default_points(view,row)
  local definition=item(view,row.record)
  local n=row.duplicate and (js_truthy(definition.duplicate_points) and definition.duplicate_points or 0) or 0
  need(integer(n,0,SAFE),"receipt_static_points_invalid");return n
 end
 local function groups(changes,view)
  need(type(changes)=="table" and #changes<=384,"receipt_changes_limit")
  local indexed,order={},{}
  for _,op in ipairs(changes)do
   local fields,name=group(op.record,view),N[op.field]
   local at
   for i,field in ipairs(fields)do if field==name then at=i;break end end
   need(at~=nil,"receipt_state_field_forbidden")
   local entry=indexed[op.record]
   if not entry then
    entry={record=op.record,set=0,remove=0,values={}};indexed[op.record]=entry;order[#order+1]=entry
   end
   need(entry.values[at]==nil,"receipt_duplicate_state_field")
   entry.values[at]=op
   local bit=2^(at-1)
   if js_truthy(op.remove)then entry.remove=entry.remove+bit
   else
    need(integer(op.value,0,UINT),"receipt_state_value_invalid")
    entry.set=entry.set+bit
   end
  end
  need(#order<=128,"receipt_groups_limit")
  table.sort(order,function(a,b)return a.record<b.record end)
  return order
 end
 local api={Schema=C.sha256}
 function api.Encode(view,revision,receipt,changes)
  pool(view)
  need(integer(revision,2,2097151),"receipt_revision_invalid")
  need(type(receipt)=="table" and(receipt.count==1 or receipt.count==10)
   and type(receipt.results)=="table" and #receipt.results==receipt.count,"receipt_count_invalid")
  need(integer(receipt.guarantee_quality,0,5)and type(receipt.guarantee_satisfied)=="boolean","receipt_guarantee_invalid")
  local gs=groups(changes,view)
  local out={string.char(1),uint(revision),uint(receipt.count),
   uint(receipt.guarantee_quality+(receipt.guarantee_satisfied and 8 or 0)),uint(#gs)}
  for _,entry in ipairs(gs)do
   out[#out+1]=uint(entry.record);out[#out+1]=uint(entry.set);out[#out+1]=uint(entry.remove)
   for i in ipairs(group(entry.record))do
    local op=entry.values[i]
    if op and not js_truthy(op.remove)then out[#out+1]=uint(op.value)end
   end
  end
  for index=1,receipt.count do local row=receipt.results[index]
   need(type(row)=="table","receipt_row_invalid")
   item(view,row.record)
   need(integer(row.owned_count,0,SAFE)and integer(row.converted_points,0,SAFE)
    and type(row.duplicate)=="boolean","receipt_row_invalid")
   local owned=row.owned_count~=1
   local converted=row.converted_points~=default_points(view,row)
   local granted=row.granted_count~=nil
   local overflow=row.overflow_count~=nil
   local flags=(row.duplicate and 1 or 0)+(owned and 2 or 0)+(converted and 4 or 0)
    +(granted and 8 or 0)+(overflow and 16 or 0)
   out[#out+1]=uint(row.record);out[#out+1]=uint(flags)
   if owned then out[#out+1]=uint(row.owned_count,SAFE)end
   if converted then out[#out+1]=uint(row.converted_points,SAFE)end
   if granted then out[#out+1]=uint(row.granted_count)end
   if overflow then out[#out+1]=uint(row.overflow_count)end
  end
  local raw=table.concat(out);need(#raw<=2048,"receipt_body_limit");return raw
 end
 function api.Inspect()return {initial_registry_visits=index_visits,steady_registry_visits=0}end
 return api
end
return M
