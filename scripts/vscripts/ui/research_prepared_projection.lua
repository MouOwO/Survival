-- Read-only first-paint facts, not a production/transaction snapshot.
-- Only learning prerequisites + levels. Costs, automation, queues and jobs
-- remain on the selected authoritative production view7.
local M={}
local function uint(value,max)return type(value)=='number'and value>=0 and value<=max and value==math.floor(value)end
function M.new(L)
 local F,R=L.field_by_name,L.by_key['production:state'];local rows={}
 for _,row in ipairs(L.production.research)do
  if row.mapping.building_id=='building_advanced_research_lab'then
   rows[#rows+1]={id=assert(L.by_key['production:research:'..row.group]),name=row.ability_name,max=row.definition.max_level}
  end
 end
 assert(#rows==10,'prepared_research_scope_changed')
 local factory={}
 function factory.initialize()
  local values,stamp,entity,serial={},nil,nil,nil
  local api={}
  function api.update(source,next_entity,next_serial)
   assert(uint(next_entity,4294967295)and uint(next_serial,4294967295)and next_serial>0,'prepared_binding_invalid')
   local next_stamp=source and source._prepared_stamp
   if stamp~=nil and stamp==next_stamp and entity==next_entity and serial==next_serial then return{}end
   local staged={}
   local function put(id,field,value)staged[id*256+field]={record=id,field=field,value=value}end
   local present=source and source.learning
   put(R,F.known,present and 1 or 0);put(R,F.production_entity,next_entity);put(R,F.production_selection,next_serial)
   if present then
    local count=0;for _ in pairs(present)do count=count+1 end;assert(count==#rows,'prepared_scope_incomplete')
    for _,row in ipairs(rows)do
     local value=present[row.name]
     assert(type(value)=='table'and uint(value.current_level,row.max)
      and(value.prerequisite_met==0 or value.prerequisite_met==1),'prepared_learning_invalid')
     put(row.id,F.level,value.current_level);put(row.id,F.production_flags,value.prerequisite_met*2)
    end
   end
   -- Validate every field before changing the old baseline.
   local out={}
   for key,old in pairs(values)do if not staged[key]then out[#out+1]={record=old.record,field=old.field,remove=true}end end
   for key,row in pairs(staged)do local old=values[key];if not old or old.value~=row.value then out[#out+1]=row end end
   table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end)
   values,stamp,entity,serial=staged,next_stamp,next_entity,next_serial;return out
  end
  function api.full_ops()local out={}for _,row in pairs(values)do out[#out+1]=row end;table.sort(out,function(a,b)return a.record==b.record and a.field<b.field or a.record<b.record end);return out end
  return api
 end
 return factory
end
return M
