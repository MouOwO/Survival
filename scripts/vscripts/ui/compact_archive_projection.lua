-- Read-only numeric presentation projection. No rewards, writes, timers or I/O.
-- initialize visits R real rows once; update accepts K authoritative changed
-- row objects and an optional changed header. It never scans an old full page.
local M={}
local UINT,SAFE=4294967295,9007199254740991
local function need(v,e) if not v then error(e,0) end end
local function guard(fn,...) local ok,a,b=pcall(fn,...);if ok then return a,b end return nil,tostring(a) end
local function copy(v) if type(v)~="table" then return v end local r={} for k,c in pairs(v) do r[k]=copy(c) end return r end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end return true
end
local function integer(v,max) return type(v)=="number" and v==math.floor(v) and v>=0 and v<=(max or UINT) end
local function path_get(v,p) for k in p:gmatch("[^.]+") do if type(v)~="table" then return nil end v=v[k] end return v end
local function path_remove(v,p)
 local parts={} for k in p:gmatch("[^.]+") do parts[#parts+1]=k end
 for i=1,#parts-1 do v=v[parts[i]];if type(v)~="table" then return end end v[parts[#parts]]=nil
end
local qualities={"N","R","SR","SSR","UR"}
local function distribution(page,rows,initial)
 local groups,total,probs,qprobs={},0,{},{}
 for _,q in ipairs(qualities) do groups[q]={remaining=0,weight=page.weights[q] or 0,entries={}};qprobs[q]=0 end
 for _,t in ipairs(page.rows) do local s=t.static
  if s.draw_enabled==1 then
   local n=math.max(0,s.target-(initial and 0 or rows[t.record].count or 0))
   if n>0 then local g=groups[s.quality];need(g,"archive_quality_unknown");g.remaining=g.remaining+n;g.entries[#g.entries+1]={record=t.record,remaining=n} end
  end
 end
 for _,q in ipairs(qualities) do local g=groups[q];if g.remaining>0 and g.weight>0 then total=total+g.weight end end
 for _,q in ipairs(qualities) do local g=groups[q];if g.remaining>0 and g.weight>0 then
  local p=g.weight/total;qprobs[q]=p
  for _,e in ipairs(g.entries) do probs[e.record]=p*e.remaining/g.remaining end
 end end
 return probs,qprobs
end
local function formatted(t,values)
 local r=copy(t.static);for name in pairs(t.dynamic) do if name~="fragment_total" then r[name]=values[name] end end
 local f=t.formatter
 if f.preview_condition and values.preview_only==1 then r.unlock_condition=f.preview_condition end
 if f.name=="boss" then r.name=f.name_base.."（"..r.target.."次）" end
 if f.description=="social" then r.description=f.description_base.."（每件）\n已拥有"..r.count.."件，效果按数量叠加"
 elseif f.description=="building" then r.description=f.description_base.."\n当前等级："..r.level.."/"..r.target.."\n每级消耗："..r.cost.."信仰值\n"..(r.level>=r.target and "已满级" or r.level==0 and "点击激活" or "点击升级")
 elseif f.description=="work" then r.description=f.description_base.."\n激活消耗："..r.cost.."软妹币\n"..(r.level>=r.target and "已激活，永久生效" or "点击此格激活；每项可激活一次")
 elseif f.description=="fragment" then r.description="当前Lv"..r.level.."，累计获得"..values.fragment_total.."片。每20片晋升1级。\n"..f.description_tail end
 return r
end
local function make(lookup)
 local C=lookup.archive_projection;need(C and lookup.by_key and lookup.field_by_name,"archive_lookup_required")
 local F=lookup.field_by_name;local pages,global_names={},{},{};local zero={}
 for _,name in ipairs(C.zero_fields) do zero[name]=true end
 local function rec(key) local n=lookup.by_key[key];need(n and lookup.records[n] and not lookup.records[n].tombstone,"archive_record_missing:"..key);return n end
 for category,source in pairs(C.pages) do
  local p=copy(source);p.root=rec("archive:category:"..category);p.by_id={};p.by_record={};p.weights=nil
  for _,t in ipairs(p.rows) do t.record=rec(t.key);p.by_id[t.static.id]=t;p.by_record[t.record]=t
   local name=t.static.name or t.formatter.name_base
   if category=="friend" or category=="ex" or category=="wife" or category=="concubine" or category=="beast" then
    local key=category.."\0"..name;need(not global_names[key],"archive_duplicate_social_name");global_names[key]=t.record
   end
  end
  for _,rule in ipairs(C.social_rules) do if rule.pool_id==category then p.weights={} for _,q in ipairs(qualities) do p.weights[q]=rule["quality_weight_"..q:lower()] end end end
  pages[category]=p
 end
 local factory={}
 function factory.initialize(snapshot)
  return guard(function()
   need(type(snapshot)=="table" and snapshot.ok==true,"archive_snapshot_required")
   local page=pages[snapshot.category_id];need(page,"archive_category_unknown")
   local state,values,row_values={}, {}, {};local known=1
   local social_remaining={}
   local metrics={row_visits=0,header_visits=0,registry_scans=1,ops=0}
   local function validate_value(name,value)
    local id=F[name];local field=id and lookup.fields[id];need(field,"archive_field_unknown:"..name)
    need(integer(value,name=="count" and SAFE or field.max) and value>=field.min,"archive_value_invalid:"..name)
   end
   local function extract(t,row)
    need(type(row)=="table" and row.id==t.static.id,"archive_row_identity_invalid")
    local v={};for name,field in pairs(t.dynamic) do
     local n=row[name]
     if name=="fragment_total" then n=tonumber(tostring(row.description):match("^当前Lv%d+，累计获得(%d+)片。")) end
     if n==nil then need(name=="preview_only" or snapshot.category_id=="commerce_goods" and row.count_known==0 and (name=="count" or name=="owned" or name=="unlocked" or name=="completed"),"archive_dynamic_missing:"..name)
     else validate_value(field,n);v[name]=n end
    end
    local expected=formatted(t,v)
    if page.weights then expected.draw_probability=row.draw_probability;expected.initial_draw_probability=row.initial_draw_probability;expected.quality_draw_probability=row.quality_draw_probability end
    need(equal(expected,row),"archive_unmapped_row:"..row.id)
    return v
   end
   local function header_values(header)
    metrics.header_visits=metrics.header_visits+1
    need(header.ok==true and header.category_id==snapshot.category_id,"archive_header_identity_invalid")
    need(equal(header.categories,C.categories),"archive_categories_changed")
    local h=copy(header);h.rows=nil;h.categories=nil;h.daily_limits=nil;h.last_draw=nil
    local v={};for path,name in pairs(page.header_paths) do local n=path_get(h,path);validate_value(name,n);v[name]=n;path_remove(h,path) end
    path_remove(h,"social.rarity_probabilities");path_remove(h,"social.rarity_base_probabilities")
    need(equal(h,page.header),"archive_unmapped_header")
    local target=0
    if header.last_draw then
     local last=header.last_draw;need(type(last.pool_id)=="string" and type(last.name)=="string","archive_last_draw_invalid")
     target=global_names[last.pool_id.."\0"..last.name];need(target,"archive_last_draw_item_unknown")
    end
    v.target_record=target;return v
   end
   local supplied={}
   for _,row in ipairs(snapshot.rows or {}) do
    metrics.row_visits=metrics.row_visits+1
    local t=page.by_id[row.id];need(t and not supplied[t.record],"archive_unknown_or_duplicate_row")
    supplied[t.record]=true;row_values[t.record]=extract(t,row)
    if row.count_known==0 then known=0 end
   end
   for _,t in ipairs(page.rows) do if not supplied[t.record] then need(page.filtered,"archive_row_missing:"..t.static.id);row_values[t.record]={count=0,visible=0} else if page.filtered then row_values[t.record].visible=1 end end end
   local root=header_values(snapshot)
   local function verify_probabilities(header,rows)
    if not page.weights then return end
    local p,q=distribution(page,rows,false);local initial,base=distribution(page,rows,true)
    for _,row in ipairs(header.rows or {}) do local t=page.by_id[row.id]
     need(row.draw_probability==(p[t.record] or 0) and row.initial_draw_probability==(initial[t.record] or 0) and row.quality_draw_probability==(q[row.quality] or 0),"archive_probability_mismatch")
    end
    need(equal(header.social.rarity_probabilities,q) and equal(header.social.rarity_base_probabilities,base),"archive_quality_probability_mismatch")
    return initial,base
   end
   local initial_probabilities,initial_qualities=verify_probabilities(snapshot,row_values)
   if page.weights then
    for _,q in ipairs(qualities) do social_remaining[q]=0 end
    for _,t in ipairs(page.rows) do if t.static.draw_enabled==1 then social_remaining[t.static.quality]=social_remaining[t.static.quality]+math.max(0,t.static.target-row_values[t.record].count) end end
   end
   local function encoded(record,name,value,target)
    if name=="count" and value~=nil then
     local hi=math.floor(value/4294967296);local lo=value-hi*4294967296
     encoded(record,"count_hi",hi,target);value=lo
    end
    if value==nil then return end
    validate_value(name,value)
    if known==1 and record~=page.root and ((value==0 and zero[name]) or name=="known" and value==1 or name=="count_hi" and value==0) then return end
    target[record]=target[record] or {};target[record][F[name]]=value
   end
   local function project_root(v,target)
    target[page.root]={[F.known]=known,[F.zero_mask]=known==1 and C.zero_mask or 0}
    for name,n in pairs(v) do encoded(page.root,name,n,target) end
   end
   project_root(root,values)
   for _,t in ipairs(page.rows) do for name,n in pairs(row_values[t.record]) do encoded(t.record,t.dynamic[name] or name,n,values) end end
   local function flatten(v) local out={} for record,row in pairs(v) do for field,n in pairs(row) do out[#out+1]={record=record,field=field,value=n} end end table.sort(out,function(a,b) return a.record==b.record and a.field<b.field or a.record<b.record end);return out end
   local initial_ops=flatten(values);metrics.ops=#initial_ops
   local api={}
   -- changed_rows contains actual changed row objects, never just IDs into an
   -- unindexed freshly allocated snapshot. Caller provides a header only when
   -- its authoritative fields changed. Empty changes perform no native calls.
   function api.update(header,changed_rows)
    return guard(function()
     local staged,changed={},{};local next_rows={};local visits=0
     for _,row in ipairs(changed_rows or {}) do
      visits=visits+1;local t=page.by_id[row.id];need(t and not changed[t.record],"archive_unknown_or_duplicate_row")
      local v=extract(t,row);need((v.count_known==0 and 0 or 1)==known or v.count_known==nil,"archive_known_scope_changed_requires_full")
      if page.filtered then v.visible=(v.count or 0)>0 and 1 or 0 end
      changed[t.record]=true;next_rows[t.record]=v
      staged[t.record]={};for name,n in pairs(v) do encoded(t.record,t.dynamic[name] or name,n,staged) end
     end
     if header then project_root(header_values(header),staged);changed[page.root]=true end
     local next_remaining
     if page.weights and (visits>0 or header) then
      next_remaining=copy(social_remaining)
      for record,v in pairs(next_rows) do local t=page.by_record[record]
       if t.static.draw_enabled==1 then local q=t.static.quality;next_remaining[q]=next_remaining[q]+math.max(0,t.static.target-v.count)-math.max(0,t.static.target-row_values[record].count) end
      end
      local total,qprobs=0,{}
      for _,q in ipairs(qualities) do if next_remaining[q]>0 and page.weights[q]>0 then total=total+page.weights[q] end end
      for _,q in ipairs(qualities) do qprobs[q]=next_remaining[q]>0 and page.weights[q]>0 and page.weights[q]/total or 0 end
      for _,row in ipairs(changed_rows or {}) do local t=page.by_id[row.id];local q=row.quality;local remaining=t.static.draw_enabled==1 and math.max(0,t.static.target-row.count) or 0
       local p=remaining>0 and qprobs[q]>0 and qprobs[q]*remaining/next_remaining[q] or 0
       need(row.draw_probability==p and row.initial_draw_probability==(initial_probabilities[t.record] or 0) and row.quality_draw_probability==qprobs[q],"archive_probability_mismatch")
      end
      if header then need(equal(header.social.rarity_probabilities,qprobs) and equal(header.social.rarity_base_probabilities,initial_qualities),"archive_quality_probability_mismatch") end
     end
     local ops={}
     for record in pairs(changed) do local old,new=values[record] or {},staged[record] or {}
      for field,n in pairs(new) do if old[field]~=n then ops[#ops+1]={record=record,field=field,value=n} end end
      for field in pairs(old) do if new[field]==nil then ops[#ops+1]={record=record,field=field,remove=true} end end
     end
     for record in pairs(changed) do values[record]=staged[record] end
     for record,v in pairs(next_rows) do row_values[record]=v end
     if next_remaining then social_remaining=next_remaining end
     metrics={row_visits=visits,header_visits=header and 1 or 0,probability_visits=next_remaining and 5+visits or 0,registry_scans=0,ops=#ops};return ops,metrics
    end)
   end
   function api.full_ops() return flatten(values) end
   function api.inspect() return {category=snapshot.category_id,known=known,metrics=copy(metrics)} end
   return api,initial_ops
  end)
 end
 return factory
end
function M.new(lookup) return guard(make,lookup) end
return M
