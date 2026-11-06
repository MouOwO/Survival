-- Presentation only. No roll, probability, persistence, coupon debit or send.
-- One inventory index per genuine profile initialization; updates read K keys.
local M={}
local config=require("config/lottery_config")
local aliases=require("config/content_id_aliases")
local stackables=require("systems/archive_stackable_items")
local catalog_manifest=require("config/generated/lottery_catalog_manifest")
local MAX,BASE=9007199254740991,4294967296
local quality={n=1,r=2,sr=3,ssr=4,ur=5,[""]=0}
M.error_text={[0]="",[1]="抽奖未完成，请重试",[2]="档案尚未载入",[3]="抽奖券不足",[4]="奖池尚未解锁",
 [5]="操作处理中，请稍后重试",[6]="奖池版本已更新，请重新进入",[7]="到账尚未确认，请稍后查询",
 [8]="奖池配置尚未同步，请稍候"}
local errors={http_profile_required=2,profile_not_loaded=2,http_profile_wire_invalid=7,lottery_ticket_insufficient=3,lottery_pool_locked=4,
 lottery_player_busy=5,archive_busy=5,lottery_config_refresh_required=6,lottery_config_hash_mismatch=6}
local function need(v,e)if not v then error(e,0)end end
local function integer(v,min,max)return type(v)=="number" and v==v and v==math.floor(v) and v>=min and v<=max end
local function number(v)if v==nil then return 0 end v=tonumber(v);need(integer(v,0,MAX),"lottery_count_invalid");return v end
local function guard(fn,...)local ok,a,b=pcall(fn,...);if ok then return a,b end return nil,tostring(a)end
local function make(L)
 need(type(L)=="table" and L.by_key and L.field_by_name,"lottery_lookup_required")
 local F=L.field_by_name
 local function rec(key)local id=L.by_key[key];need(id and L.records[id] and not L.records[id].tombstone,"lottery_record_missing:"..key);return id end
 for _,key in ipairs({"known","count","count_hi","tickets","tickets_hi","draws","draws_hi","unlocked","unlock_progress",
  "update_unread","notice_unread","owned_count","owned_count_hi","owned","at_max_owned","balance","balance_hi",
  "progress","progress_hi","level","pending","enabled","request_token","success","terminal","error_code","target_record",
  "quality_code","guarantee_satisfied","reward_count","duplicate","converted_points","converted_points_hi","granted_count","overflow_count"})do need(F[key],"lottery_field_missing:"..key)end
 local state_rec,receipt_rec=rec("lottery:state"),rec("lottery:receipt")
 local pools,pool_by_record,item_by_record,all_items,currency={},{},{},{},{}
 for _,pool in ipairs(config.pool_order)do
  local p={id=pool.id,record=rec("lottery:pool:"..pool.id),source=pool,members={},allowed={}}
  p.revision=catalog_manifest.pool_revisions and catalog_manifest.pool_revisions[pool.id]
  need(type(p.revision)=="string"and p.revision~="","lottery_catalog_revision_missing:"..pool.id)
  pools[pool.id]=p;pool_by_record[p.record]=pool.id
  for _,item in ipairs(pool.items)do
   local id=rec("lottery:item:"..item.id);p.members[#p.members+1]=item.id;p.allowed[id]=true
   all_items[item.id]={record=id,source=item};item_by_record[id]=item.id
  end
  currency[pool.ticket_content_id]=rec("lottery:currency:"..pool.ticket_content_id)
 end
 local slots={};for i=1,10 do slots[i]=rec("lottery:result:"..i)end
 local factory={}
 function factory.pool_id(record)return pool_by_record[record]end
 function factory.initialize(profile,context)
  return guard(function()
   local values,groups,raw_values,totals={}, {}, {}, {}
   local identity,revision,known,metrics=nil,nil,false,{initializations=1,inventory_entries_scanned=0,inventory_reads=0,items=0,pools=0}
   local intents,used={},{}
   local function stage()
    local order,writes={},{}
    local function put(r,name,value)local f=F[name];need(f,"lottery_field_missing:"..name);local key=tostring(r)..":"..tostring(f);if not writes[key]then order[#order+1]=key end;writes[key]={record=r,field=f,value=value}end
    local function big(r,name,v)put(r,name,v%BASE);put(r,name.."_hi",math.floor(v/BASE))end
    local function commit()
     local ops={};for _,key in ipairs(order)do local w=writes[key];local row=values[w.record]
      if not row or row[w.field]~=w.value then if not row then row={};values[w.record]=row end;row[w.field]=w.value
       ops[#ops+1]=w.value==nil and {record=w.record,field=w.field,remove=true}or{record=w.record,field=w.field,value=w.value}
      end
     end;return ops
    end
    return put,big,commit
   end
   local function validate(p)
    need(type(p)=="table" and type(p.save)=="table" and p.account_id~=nil,"lottery_profile_required")
    need(integer(p.revision,0,MAX),"lottery_profile_revision_invalid")
    local id=tostring(p.account_id)..":"..tostring(p.mode)..":"..tostring(p.match_session_id)
    need(not identity or id==identity,"lottery_identity_changed");need(not revision or p.revision>=revision,"lottery_stale_profile");return id
   end
   local function index_inventory(p)
    for raw,v in pairs(p.save.content_inventory or{})do
     metrics.inventory_entries_scanned=metrics.inventory_entries_scanned+1
     local id=aliases.canonical(raw)
     if all_items[id]or currency[id]then groups[id]=groups[id]or{};groups[id][raw]=true;raw_values[raw]=number(v);totals[id]=(totals[id]or 0)+raw_values[raw]end
    end
   end
   local function refresh_inventory(p,raw_ids)
    local impacted,next_groups,next_totals={},{},{};local inventory=p.save.content_inventory or{}
    need(#raw_ids<=128,"lottery_changeset_limit")
    local size=0;for key in pairs(raw_ids)do need(integer(key,1,#raw_ids),"lottery_changeset_sparse");size=size+1 end
    need(size==#raw_ids,"lottery_changeset_sparse")
    for _,raw in ipairs(raw_ids)do need(type(raw)=="string","lottery_inventory_key_invalid");local id=aliases.canonical(raw)
     if all_items[id]or currency[id]then
      if not next_groups[id]then next_groups[id]={};for prior in pairs(groups[id]or{})do next_groups[id][prior]=true end end
      next_groups[id][raw]=true;next_groups[id][id]=true;impacted[id]=true
     end
    end
    for id in pairs(impacted)do local total=0;for raw in pairs(next_groups[id])do metrics.inventory_reads=metrics.inventory_reads+1;total=total+number(inventory[raw]);need(total<=MAX,"lottery_inventory_overflow")end;next_totals[id]=total end
    return impacted,next_totals,next_groups
   end
   local function write_item(id,put,big,overrides)
    local item=all_items[id];if not item then return end;metrics.items=metrics.items+1
    local src=item.source;local unique=src.item_type=="积分道具"and not stackables.definition(id)
    local cap=unique and 1 or src.max_owned;local n=overrides and overrides[id]or totals[id]or 0;if unique then n=math.min(n,cap)end
    put(item.record,"known",1);big(item.record,"owned_count",n);put(item.record,"owned",n>0 and 1 or 0);put(item.record,"at_max_owned",cap>0 and n>=cap and 1 or 0)
   end
   local function headers(p,put,big,ctx,overrides)
    local archive=p.save.archive or{};local state=archive.lottery_state or{};local stats=p.save.gameplay_stats or{}
    put(state_rec,"known",1);put(state_rec,"pending",ctx and ctx.pending==true and 1 or 0);put(state_rec,"enabled",ctx and ctx.enabled==false and 0 or 1)
    big(state_rec,"balance",number(((archive.commerce or{}).balances or{}).shop_points));big(state_rec,"progress",math.max(number(stats.starjoy_points),number(stats.starjoy_points_earned)));put(state_rec,"level",number(stats.map_level))
    for _,source in ipairs(config.pool_order)do local pool=pools[source.id];metrics.pools=metrics.pools+1;local s=(state.pools or{})[source.id]or{}
     local status=config.unlock_status(source,state)
     put(pool.record,"known",1);big(pool.record,"tickets",number((p.save.content_inventory or{})[source.ticket_content_id]));big(pool.record,"draws",number(s.draws))
     put(pool.record,"unlocked",status.unlocked and 1 or 0);put(pool.record,"unlock_progress",number(status.unlock_progress));put(pool.record,"update_unread",s.details_revision~=pool.revision and 1 or 0);put(pool.record,"notice_unread",s.notice_revision~=pool.revision and 1 or 0)
    end
    for id,r in pairs(currency)do put(r,"known",1);big(r,"owned_count",overrides and overrides[id]or totals[id]or 0)end
   end
   local api={}
   function api.update(p,changes,ctx)return guard(function()
    local id=validate(p);need(known,"lottery_reinitialize_required");need(type(changes)=="table","lottery_changeset_required")
    local allowed={inventory=true,headers=true,unrelated=true};for key in pairs(changes)do need(allowed[key],"lottery_unknown_changeset:"..tostring(key))end
    need(changes.inventory==nil or type(changes.inventory)=="table","lottery_inventory_changes_required")
    metrics={inventory_entries_scanned=0,inventory_reads=0,items=0,pools=0}
    local put,big,commit=stage()
    local next_totals,next_groups
    if changes.inventory then local impacted;impacted,next_totals,next_groups=refresh_inventory(p,changes.inventory);for key in pairs(impacted)do write_item(key,put,big,next_totals)end end
    if changes.headers or changes.inventory then headers(p,put,big,ctx,next_totals)else
     if ctx then put(state_rec,"pending",ctx.pending==true and 1 or 0);put(state_rec,"enabled",ctx.enabled==false and 0 or 1)end
    end
    local ops=commit();for key,value in pairs(next_totals or{})do totals[key]=value;groups[key]=next_groups[key]end
    identity,revision=id,p.revision;return ops,metrics
   end)end
   function api.full_ops(pool_id)
    local allowed={[state_rec]=true,[receipt_rec]=true};for _,p in pairs(pools)do allowed[p.record]=true end;for _,r in pairs(currency)do allowed[r]=true end
    local pool=pools[pool_id];need(pool,"lottery_pool_invalid");for _,id in ipairs(pool.members)do allowed[all_items[id].record]=true end
    for _,r in ipairs(slots)do allowed[r]=true end
    local out={};for r in pairs(allowed)do for f,v in pairs(values[r]or{})do out[#out+1]={record=r,field=f,value=v}end end
    table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end);return out
   end
   function api.filter(pool_id,ops)
    local allow=pools[pool_id].allowed
    local out={};for _,op in ipairs(ops)do if not item_by_record[op.record]or allow[op.record]then out[#out+1]=op end end;return out
   end
   function api.bind_intent(token,pool_id,count)
    need(integer(token,1,16383)and pools[pool_id]and(count==1 or count==10),"lottery_intent_invalid")
    need(not used[token],"lottery_intent_token_reused");used[token]=true;intents[token]={pool=pool_id,count=count};return true
   end
   function api.receipt(token,response,applied)
    return guard(function()
     local intent=intents[token];need(intent,"lottery_intent_unknown");need(type(response)=="table","lottery_receipt_required")
     local success=response.ok==true and applied==true;local pending=response.pending==true or response.ok==true and not applied
     local put,big,commit=stage();local results=response.results;local compact_receipt
     if success then
      need(response.pool_id==intent.pool and response.count==intent.count and type(results)=="table" and #results==intent.count,"lottery_receipt_mismatch")
      -- Validate the entire receipt before staging any resulting field.
      for index=1,intent.count do local item=results[index]
       need(type(item)=="table"and all_items[item.id]and pools[intent.pool].allowed[all_items[item.id].record]
        and quality[item.quality]~=nil and item.quality==all_items[item.id].source.quality,"lottery_receipt_item_unknown")
       number(item.owned_count);number(item.converted_points)
       if item.granted_count~=nil then need(integer(item.granted_count,0,4294967295),"lottery_receipt_quantity_invalid")end
       if item.overflow_count~=nil then need(integer(item.overflow_count,0,4294967295),"lottery_receipt_quantity_invalid")end
      end
      compact_receipt={pool=intent.pool,token=token,count=intent.count,results={},
       guarantee_quality=quality[response.guarantee_quality or ""]or 0,guarantee_satisfied=response.guarantee_satisfied==true}
      for _,item in ipairs(results)do compact_receipt.results[#compact_receipt.results+1]={record=all_items[item.id].record,
       owned_count=number(item.owned_count),duplicate=item.duplicate==true,converted_points=number(item.converted_points),
       granted_count=item.granted_count,overflow_count=item.overflow_count}end
      for i,item in ipairs(results)do local r=slots[i];put(r,"known",1);put(r,"target_record",all_items[item.id].record);put(r,"reward_count",1);big(r,"owned_count",number(item.owned_count));put(r,"duplicate",item.duplicate==true and 1 or 0);big(r,"converted_points",number(item.converted_points));put(r,"granted_count",item.granted_count);put(r,"overflow_count",item.overflow_count)end
      for i=#results+1,10 do put(slots[i],"known",0)end
     end
     put(receipt_rec,"known",1);put(receipt_rec,"request_token",token);put(receipt_rec,"target_record",pools[intent.pool].record);put(receipt_rec,"count",intent.count);put(receipt_rec,"success",success and 1 or 0);put(receipt_rec,"pending",pending and 1 or 0);put(receipt_rec,"terminal",not pending and 1 or 0)
     put(receipt_rec,"error_code",success and 0 or pending and 7 or errors[response.error]or 1);put(receipt_rec,"quality_code",quality[response.guarantee_quality or""]or 0);put(receipt_rec,"guarantee_satisfied",success and response.guarantee_satisfied==true and 1 or 0)
     if not pending then intents[token]=nil end;return commit(),compact_receipt
    end)
   end
   function api.inspect()return {known=known,revision=revision,metrics=metrics}end
   local put,big,commit=stage()
   if profile then identity=validate(profile);revision=profile.revision;known=true;index_inventory(profile);headers(profile,put,big,context);for id in pairs(all_items)do write_item(id,put,big)end
   else put(state_rec,"known",0)end
   return api,commit()
  end)
 end
 return factory
end
function M.new(lookup)return guard(make,lookup)end
function M.command_changes(command,result)
 command=command or{};local response=result and result.response or{};local kind=command.kind
 if kind=="lottery_draw"then
  if type(response.unique_points_reconciliation)=="table" and (tonumber(response.unique_points_reconciliation.changed_items)or 0)>0 then return{initialize=true}end
  if type(response.results)~="table"then return{initialize=true}end
  local ids,set={},{};local function add(id)if type(id)=="string"and not set[id]then set[id]=true;ids[#ids+1]=id end end
  local pool=config.pools[command.pool_id];if pool then add(pool.ticket_content_id)end
  for _,row in ipairs(response.results)do if type(row)~="table"then return{initialize=true}end;add(row.id)end
  return {headers=true,inventory=ids}
 end
 if kind=="lottery_read"or kind=="online_checkpoint"or kind=="clear"or kind=="standard_clear"or kind=="mode_clear"
  or kind=="rich_clear"or kind=="cold_clear"or kind=="scourge_clear"or kind=="endless_progress"or kind=="starjoy_reconcile"
  or kind=="title_equip"or kind=="title_reconcile"or kind=="building_upgrade"or kind=="work_upgrade"then return{headers=true}end
 -- One genuine full replacement from an operation with no authoritative key
 -- list. Explicit cold initialization; never a periodic full/diff fallback.
 return {initialize=true}
end
return M
