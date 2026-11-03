-- Presentation projection only. Original grid/build/relocation validators keep
-- authority. A shared schema index is built once; each player stores only live
-- fields and nonzero two-bit area words, never 4,096 preallocated payload rows.
local wire=require('ui/compact_wire')
local M={}
local function need(value,why)if not value then error(why,0)end end
local function integer(value,min,max)return type(value)=='number' and value==math.floor(value) and value>=min and value<=max end
local function finite(value)return type(value)=='number' and value==value and math.abs(value)<math.huge end
local function equal(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function guard(fn,...)local ok,a,b=pcall(fn,...);if ok then return a,b end;return nil,tostring(a)end
function M.new(lookup)
 return guard(function()
  local G,F=assert(lookup.grid),assert(lookup.field_by_name)
  local map_name=type(GetMapName)=='function' and GetMapName() or 'template_map'
  local map_code=map_name=='template_map' and 2 or map_name=='survival_c6' and 3 or 1
  local map_config=assert(G.maps[map_code==2 and 'template_map' or map_code==3 and 'survival_c6' or 'default'])
  local function rec(key)local id=lookup.by_key[key];need(id and lookup.records[id] and not lookup.records[id].tombstone,'grid_record_missing:'..key);return id end
  local ids={state=rec('grid:state'),validation=rec('grid:validation'),commit=rec('grid:commit')}
  local profiles,profile_records,errors={},{},{}
  for _,profile in ipairs(G.profiles)do profiles[profile.ability_name]=profile;profile_records[profile.ability_name]=rec('grid:profile:'..profile.ability_name)end
  for index,text in ipairs(G.errors)do errors[text]=index-1 end
  local areas={}
  for _,kind in ipairs({'area','static'})do
   local group={meta=rec('grid:'..kind..':meta'),words={},max=kind=='area' and 256 or 4096}
   for index=1,group.max do group.words[index]=rec('grid:'..kind..':word:'..index)end
   areas[kind]=group
  end
  local local_bases={}
  for _,candidate in ipairs(G.atlases or {})do
   if candidate.map==map_name and candidate.requires_current_live_scan==true and candidate.authority==false
    and (candidate.binding_matches_source==true or candidate.runtime_source_compatible==true)
    and candidate.projection_signature==G.projection_signature then
    local parts={};for part in (candidate.area..'|'):gmatch('(.-)|')do parts[#parts+1]=part end
    if parts[1]=='3' and #parts==8 then
     local base={id=candidate.id,header=table.concat(parts,'|',1,7),words={}}
     for index=1,math.ceil(#parts[8]/8)do local value=0;for nibble=0,7 do local digit=tonumber(parts[8]:sub((index-1)*8+nibble+1,(index-1)*8+nibble+1),16)or 0;value=value+digit*16^nibble end;base.words[index]=value end
     local_bases[#local_bases+1]=base
    end
   end
  end
  local cells={};for index=1,16 do cells[index]=rec('grid:cell:'..index)end
  local layouts={};for _,key in ipairs({'min_display','max_display','min_build','max_build','plane'})do layouts[key]=rec('grid:layout:'..key)end
  local factory={}
  function factory.initialize()
   local values,area_words,area_sources,metrics={}, {area={},static={}}, {}, {updates=0,changed_fields=0,area_words=0,stable=0}
   local api={}
   local function ingest(event,payload)
    need(type(payload)=='table','grid_payload_required')
    local staged={}
    local function put(id,name,value)
     local field=F[name];need(field,'grid_field_missing:'..name)
     if type(value)=='boolean'then value=value and 1 or 0 end
     local key=id*256+field
     staged[key]={record=id,field=field,value=value,remove=value==nil or nil}
    end
    local function double(id,axis,value)
     if value==nil then put(id,'grid_'..axis..'_hi',nil);put(id,'grid_'..axis..'_lo',nil);return end
     local parts=assert(wire.float64_words(value));put(id,'grid_'..axis..'_hi',parts.hi);put(id,'grid_'..axis..'_lo',parts.lo)
    end
    local function error_code(text)return errors[tostring(text or '')] or 1 end
    local function base(id)
     put(id,'known',1);put(id,'grid_scope',assert(tonumber(payload.grid_scope_version)))
     put(id,'grid_session',tonumber(payload.session_id));put(id,'grid_request',tonumber(payload.request_id))
    end
    local next_words,next_sources={},{}
    local function area(kind,source,complete)
     local group=areas[kind];local text=tostring(source or '')
     if kind=='static'then put(group.meta,'grid_scope',assert(tonumber(payload.grid_scope_version)))end
     local finished=complete==true or complete==1
     local previous=area_sources[kind]
     if previous and previous.text==text and previous.complete==finished then return end
     next_sources[kind]={text=text,complete=finished}
     local parts={};for part in (text..'|'):gmatch('(.-)|')do parts[#parts+1]=part end
     local words={}
     if text=='' then put(group.meta,'known',0);if kind=='static'then put(group.meta,'grid_atlas_base',0)end
     else
      need(parts[1]=='3' and #parts==8,'grid_area_format_required')
      local size,x,y,width,height,z=tonumber(parts[2]),tonumber(parts[3]),tonumber(parts[4]),tonumber(parts[5]),tonumber(parts[6]),tonumber(parts[7])
      need(integer(size,1,65536) and integer(x,-2147483647,2147483647) and integer(y,-2147483647,2147483647)
       and integer(width,1,65536) and integer(height,1,65536) and width*height<=group.max*16 and finite(z),'grid_area_bounds_invalid')
      need(#parts[8]==math.ceil(width*height/2) and not parts[8]:find('[^0-9a-fA-F]'),'grid_area_word_count_invalid')
      put(group.meta,'known',1);put(group.meta,'grid_size',size);put(group.meta,'grid_origin_x',x);put(group.meta,'grid_origin_y',y)
      put(group.meta,'grid_width',width);put(group.meta,'grid_height',height);double(group.meta,'z',z)
      local base
      if kind=='static' and finished then
       local header=table.concat(parts,'|',1,7)
       for _,candidate in ipairs(local_bases)do if candidate.header==header then base=candidate;break end end
       put(group.meta,'grid_atlas_base',base and base.id or 0)
       metrics.static_base=base and base.id or 0
      end
      for index=1,math.ceil(width*height/16)do
       local value=0
       for nibble=0,7 do
        local at=(index-1)*8+nibble+1;local digit=at<=#parts[8] and tonumber(parts[8]:sub(at,at),16) or 0
        need(digit%4~=3 and math.floor(digit/4)~=3,'grid_area_state_invalid')
        value=value+digit*16^nibble
       end
       if value~=(base and base.words[index]or 0)then words[index]=value end
       metrics.area_words=metrics.area_words+1
      end
     end
     if kind=='static'then local count=0;for _ in pairs(words)do count=count+1 end;metrics.static_overrides=count end
     put(group.meta,'grid_complete',complete==true or complete==1)
     for index,value in pairs(words)do put(group.words[index],'grid_word',value)end
     for index in pairs(area_words[kind])do if words[index]==nil then put(group.words[index],'grid_word',nil)end end
     next_words[kind]=words
    end
    if event=='ui_grid_placement_profiles' then
     put(ids.state,'known',1);put(ids.state,'grid_layout_ready',payload.layout_ready~=0)
     put(ids.state,'grid_map',map_code)
     put(ids.state,'grid_scope',assert(tonumber(payload.grid_scope_version)));put(ids.state,'grid_error',error_code(payload.error))
     if payload.layout_ready~=0 then
      need(equal(payload.profiles,G.profiles),'grid_static_profiles_changed')
      if payload.cell_size~=nil then need(payload.cell_size==map_config.cell_size,'grid_static_cell_size_changed')end
      if payload.preview_visual~=nil then need(equal(payload.preview_visual,map_config.preview_visual),'grid_static_visual_changed')end
      local layout=assert(payload.static_grid)
      for name,bounds in pairs({display=layout.bounds,build=layout.build_bounds})do
       need(type(bounds)=='table','grid_layout_bounds_required')
       double(layouts['min_'..name],'x',bounds.min_x);double(layouts['min_'..name],'y',bounds.min_y)
       double(layouts['max_'..name],'x',bounds.max_x);double(layouts['max_'..name],'y',bounds.max_y)
      end
      double(layouts.plane,'z',layout.height)
     end
    elseif event=='ui_grid_placement_validation' then
     local id=ids.validation;base(id)
     local profile=profiles[payload.ability_name];need(profile,'grid_profile_unknown')
     put(id,'grid_profile',profile_records[payload.ability_name]);put(id,'success',payload.success==1)
     put(id,'grid_error',error_code(payload.error))
     for _,key in ipairs({'anchor_x','anchor_y','request_anchor_x','request_anchor_y'})do put(id,'grid_'..key,tonumber(payload[key]))end
     local width,height=profile.grid_footprint_x,profile.grid_footprint_y
     local list=payload.cells or {};need(#list==0 or #list==width*height and #list<=16,'grid_cell_shape_changed')
     local mask=0
     for index,cell in ipairs(list)do
      local origin_x=(tonumber(payload.anchor_x) or 0)-math.floor(width/2)
      local origin_y=(tonumber(payload.anchor_y) or 0)-math.floor(height/2)
      local size=map_config.cell_size
      need(cell.x==(origin_x+math.floor((index-1)/height)+0.5)*size
       and cell.y==(origin_y+(index-1)%height+0.5)*size,'grid_cell_coordinate_changed')
      if cell.ok==true or cell.ok==1 then mask=mask+2^(index-1)end
      double(cells[index],'z',cell.z~=payload.world_z and cell.z or nil)
     end
     for index=#list+1,16 do double(cells[index],'z',nil)end
     put(id,'grid_cell_count',#list);put(id,'grid_cell_mask',mask)
     local size=map_config.cell_size
     for _,axis in ipairs({'x','y'})do
      local footprint=axis=='x' and width or height
      local derived=((tonumber(payload['anchor_'..axis]) or 0)+(footprint%2)*0.5)*size
      double(id,axis,payload['world_'..axis]~=derived and payload['world_'..axis] or nil)
     end
     double(id,'z',payload.world_z)
     area('area',payload.area,payload.area_complete)
    elseif event=='ui_grid_placement_area' then
     base(areas.area.meta);put(areas.area.meta,'grid_profile',profile_records[payload.ability_name])
     area('area',payload.area,payload.complete)
    elseif event=='ui_grid_placement_static_area' then area('static',payload.area,true)
    elseif event=='ui_grid_placement_commit_result' then
     base(ids.commit);put(ids.commit,'success',payload.success==1);put(ids.commit,'grid_error',error_code(payload.error))
    else error('grid_event_unknown',0)end
    local out={}
    for _,op in pairs(staged)do
     local old=values[op.record] and values[op.record][op.field]
     if old~=op.value then out[#out+1]=op end
    end
    table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end)
    for _,op in ipairs(out)do
     local row=values[op.record] or {};values[op.record]=row;row[op.field]=op.value
     if not next(row)then values[op.record]=nil end
    end
    for kind,words in pairs(next_words)do area_words[kind]=words end
    for kind,source in pairs(next_sources)do area_sources[kind]=source end
    metrics.updates=metrics.updates+1;metrics.changed_fields=metrics.changed_fields+#out
    if #out==0 then metrics.stable=metrics.stable+1 end
    return out
   end
   function api.ingest(event,payload)return guard(ingest,event,payload)end
   function api.full_ops()
    local out={};for id,row in pairs(values)do for field,value in pairs(row)do out[#out+1]={record=id,field=field,value=value}end end
    table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end);return out
   end
   function api.inspect()return metrics end
   return api
  end
  function factory.profile(record)local row=lookup.records[record];return row and row.domain=='grid' and row.kind=='profile' and profiles[row.business_id] or nil end
  return factory
 end)
end
return M
