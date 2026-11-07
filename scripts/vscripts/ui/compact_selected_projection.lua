-- Display-only scalar projection. Combat/armor math remains in original DTO.
local wire=require("ui/compact_wire")
local layout=require("ui/selected_stats_schema")
local M={}
local function need(v,e)if not v then error(e,0)end end
local function guard(fn,...)local ok,a,b=pcall(fn,...);if ok then return a,b end return nil,tostring(a)end
local function parts(path)local out={}for p in path:gmatch("[^.]+")do out[#out+1]=tonumber(p)or p end return out end
local function get(value,path)for _,key in ipairs(path)do if type(value)~="table"then return nil end;value=value[key]end return value end
-- Exact aliases authored by combat_stat_projection.for_ui, never new combat math.
local derived_aliases={['stat_tooltips.attack.minimum']=true,['stat_tooltips.attack.maximum']=true,
 ['stat_tooltips.attributes.strength']=true,['stat_tooltips.attributes.agility']=true,['stat_tooltips.attributes.intellect']=true}
function M.new(L,options)return guard(function()
 local F=L.field_by_name;local root=assert(L.by_key["selected:state"]);local rows={};local zero_records={};local critical,versions={},{}
 for index=1,math.ceil(#layout.numeric_paths/32)do zero_records[index]=assert(L.by_key["selected:zero:"..index]);critical[zero_records[index]]=true end
 for _,kind in ipairs({"number","text"})do for index,path in ipairs(kind=="number"and layout.numeric_paths or layout.text_paths)do
  local r=assert(L.by_key["selected:metric:"..path],"selected_metric_missing:"..path);if not(options and options.derive_aliases and derived_aliases[path])then rows[#rows+1]={path=path,keys=parts(path),record=r,kind=kind,group=math.floor((index-1)/32)+1,power=2^((index-1)%32)}end
  if kind=="text"or not path:find("%.")or path:match("^building_stat_details%.[a-z]+_bonus$")or path:match("^building_stat_details%.[a-z]+_pct$")or path:match("^building_stat_details%.[a-z]+_base$")then critical[r]=true end
  if path=="refresh_version"or path=="refresh_sequence"then versions[r]=true end
 end end
 local texts=assert(L.selected and L.selected.text_by_value,"selected_text_index_missing")
 for _,name in ipairs({"known","success","error_code","pending","selected_entity","selected_token","selected_value_hi","selected_value_lo","selected_value_int","zero_mask","target_record"})do need(F[name],"selected_field_missing:"..name)end
 local factory={}
 function factory.initialize(snapshot,entity,token)
  return guard(function()
   need(type(entity)=="number"and entity==math.floor(entity)and entity>=0 and entity<=4294967295,"selected_entity_invalid")
   need(type(token)=="number"and token==math.floor(token)and token>=1 and token<=4294967295,"selected_token_invalid")
   local values={};local api={};local visits=0;local unknown_text={}
   function api.update(source,next_token)
    return guard(function()
     -- Same-entity refresh preserves the established baseline. Stage the new
     -- selection token with the validated delta; an invalid source cannot
     -- advance identity or partially commit display fields.
     if next_token~=nil then need(type(next_token)=="number"and next_token==math.floor(next_token)and next_token>token and next_token<=4294967295,"selected_token_invalid")end
     local write_token=next_token or token
     local writes,zero_masks={},{};unknown_text={};local function put(r,f,value)writes[#writes+1]={record=r,field=f,value=value}end
     local known=type(source)=="table"and source.success==1 and tonumber(source.entindex)==entity
     put(root,F.known,known and 1 or 0);put(root,F.success,known and 1 or 0);put(root,F.error_code,known and 0 or source and source.error_code==2 and 2 or 1)
     put(root,F.selected_entity,entity);put(root,F.selected_token,write_token)
     visits=0
     if known then
      local speed=(source.stat_tooltips or{}).attack_speed or{}
      need(#(speed.interval_reductions or{})<=8 and #(speed.speed_bonuses or{})<=8,"selected_tooltip_array_limit")
      for _,row in ipairs(rows)do visits=visits+1;local value=get(source,row.keys)
      if row.kind=="number"then
       local hi,lo,int
       if value~=nil then
        value=tonumber(value);need(value and value==value and math.abs(value)<math.huge,"selected_nonfinite:"..row.path)
        if value==0 and 1/value~=-math.huge then zero_masks[row.group]=(zero_masks[row.group]or 0)+row.power
        elseif value==math.floor(value)and value>=-2147483647 and value<=2147483647 then int=value
        else local words=wire.float64_words(value);need(words,"selected_number_invalid:"..row.path);hi,lo=words.hi,words.lo end
       end
       put(row.record,F.selected_value_hi,hi);put(row.record,F.selected_value_lo,lo);put(row.record,F.selected_value_int,int)
      else
       local r,text_known
       if value~=nil then need(type(value)=="string","selected_text_type:"..row.path)
        if value==""then r=0 else local key=texts[value];r=type(key)=="number"and key or key and L.by_key[key]
         if not r then r=0;text_known=0;unknown_text[#unknown_text+1]=row.path end
        end
       end
       put(row.record,F.target_record,r);put(row.record,F.known,text_known)
      end
     end
     for index,r in ipairs(zero_records)do put(r,F.zero_mask,zero_masks[index]or 0)end
     end
     -- All static IDs/numbers validate before any dynamic state is committed.
     local ops,changed,meaningful={},{},false;for _,w in ipairs(writes)do local key=w.record*256+w.field;local old=values[key]
      if not old or old.value~=w.value then
       if w.value==nil then if old then changed[#changed+1]={key=key,write=w};ops[#ops+1]={record=w.record,field=w.field,remove=true};meaningful=meaningful or not versions[w.record]end
       else changed[#changed+1]={key=key,write=w};ops[#ops+1]={record=w.record,field=w.field,value=w.value};meaningful=meaningful or not versions[w.record]end
      end
     end
     -- A source recomputation version alone is not changed display data. Keep
     -- its last-sent baseline until a meaningful delta carries the latest one.
     if not meaningful then return{},{fixed_metric_visits=visits,static_catalogue_scans=0}end
     for _,change in ipairs(changed)do values[change.key]=change.write.value~=nil and change.write or nil end
     token=write_token
     return ops,{fixed_metric_visits=visits,static_catalogue_scans=0}
    end)
   end
   function api.full_ops()local out={}for _,w in pairs(values)do out[#out+1]={record=w.record,field=w.field,value=w.value}end
    table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end);return out end
   function api.split_ops()
    local first,later={},{}
    for _,op in ipairs(api.full_ops())do local out=(op.record==root or critical[op.record])and first or later
     out[#out+1]=op
    end
    first[#first+1]={record=root,field=F.pending,value=#later>0 and 1 or 0}
    if #later>0 then later[#later+1]={record=root,field=F.pending,value=0}end
    return first,later
   end
   function api.inspect()return{entity=entity,token=token,fixed_metric_visits=visits,metrics=#rows,unknown_text_fields=unknown_text}end
   local ops,why=api.update(snapshot);need(ops,why);return api,ops
  end)
 end
 return factory
end)end
return M
