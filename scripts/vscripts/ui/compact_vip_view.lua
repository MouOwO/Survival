-- Passive private VIP grade only; reward rules/claims remain in archive.
-- O(P) initial state, O(1) stable profile changes, original12-level evaluation
-- only when the actual recharge total changes. No timer or reward catalogue.
local M={}
function M.new(o)
 local L,T=o.lookup,o.transport
 local record=assert(L.by_key['vip:state'],'vip_wire_record_required')
 local F=L.field_by_name
 local states,live={},true
 local function current()return live and(not o.current or o.current())end
 local function projection(id)
  if not current()then return nil end
  local player=o.player(id);if not player then return nil end
  local state=states[id]
  if not state or state.player~=player then state={player=player};states[id]=state end
  local profile=o.profile(id)
  local known=profile~=nil
  local total=known and o.rewards.recharge_total(profile)or nil
  local changed=state.known~=known or state.total~=total
  if changed then
   state.known,state.total=known,total
   state.level=known and o.rewards.level(profile)or nil
   state.ops={{record=record,field=F.known,value=known and 1 or 0}}
   if known then state.ops[#state.ops+1]={record=record,field=F.count,value=state.level}
   else state.ops[#state.ops+1]={record=record,field=F.count,remove=true}end
  end
  return state,changed
 end
 T.register_view(8,{snapshot=function(id)
  local state=projection(id);return state and state.ops or nil
 end,open=function(id)
  local state=projection(id);if state and o.subscribe then o.subscribe(id,true)end
  return state and state.ops or nil
 end,close=function(id)if o.subscribe then o.subscribe(id,false)end end})
 local api={}
 function api.changed(id)
  if not current()or not T.is_bound(id)then return false end
  if not T.is_open(id,8)then return true end
  local state,changed=projection(id)
  if state and changed then return T.publish(id,8,state.ops,{priority=true})end
  return {unchanged=true}
 end
 function api.reset()
  local old=states;states={}
  for id in pairs(old)do if T.is_open(id,8)and o.subscribe then o.subscribe(id,true)end end
 end
 function api.dispose()live=false;states={}end
 return api
end
return M
