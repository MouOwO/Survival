-- Candidate only: bounded, private, read-only research preparation.
-- Only foreign same-team advanced labs need prepared learning facts. Owned
-- labs already have authoritative native rows; no duplicate preparation.
local M={}
local BASIC,ADVANCED='building_research_lab','building_advanced_research_lab'
local function integer(n,lo,hi)return type(n)=='number'and n==math.floor(n)and n>=lo and n<=hi end
function M.new(o)
 assert(integer(o.max_players,1,4),'prepared_player_capacity_unsupported')
 assert(o.basic_limit==1 and o.advanced_limit==1,'prepared_building_capacity_unsupported')
 local bus=o.bus or require('core/event_bus')
 local events=require('core/events')
 local research_events=require('research/research_event_names')
 local factory=o.factory or assert(require('ui/research_prepared_projection').new(o.lookup))
 local F,R=o.lookup.field_by_name,o.lookup.by_key['production:state']
 local clock=o.clock or require('core/performance_clock').new()
 local world=bus.get_generation();local live=true
 local buildings,basic,advanced,players={},{},{},{}
 local dirty,queue,head,scheduled,running={},{},1,false,false
 local metrics={index_visits=0,identity_events=0,work_items=0,snapshots=0,published=0,hints=0,duplicates=0,invalid=0,passes=0,max_pass_work=0,max_pass_ms=0,errors=0}
 local api={}
 local function current()return live and bus.get_generation()==world and(not o.current or o.current())end
 local function identity(id)
  if not current()or not integer(id,0,o.max_players-1)or not o.allowed(id)then return nil end
  return o.player(id)
 end
 local function owner(id,create)
  local handle=identity(id);local p=players[id]
  if p and p.handle~=handle then players[id]=nil;p=nil end
  if not handle then return nil end
  if not p and create then p={id=id,handle=handle,team=o.team(id),slots={},rebirth=o.rebirth(id),levels=o.levels and o.levels(id)or{}};players[id]=p end
  if p and p.team~=o.team(id)then players[id]=nil;return owner(id,create)end
  return p
 end
 local function valid_pair(p,s)
  return current()and players[p.id]==p and identity(p.id)==p.handle and o.team(p.id)==p.team and p.slots[s.view]==s
 end
 local function desired(p,view)
  if view<12 or view>15 or view-12==p.id then return nil end
  local index=advanced[view-12]
  if not index or index.count~=1 then return nil end
  local row=index.row
  if not row or buildings[row.entity]~=row or row.team~=p.team or not o.valid_unit(row.unit,row.entity)then return nil end
  return row
 end
 local function get_slot(p,view)
  local s=p.slots[view]
  if not s then s={view=view,serial=0,probed=false,row=nil,source=nil,projection=factory.initialize()};p.slots[view]=s end
  return s
 end
 local function hint(p,s,known)
  if not valid_pair(p,s)or not s.probed or o.transport.is_open(p.id,s.view)then return end
  if not known and not s.announced then return end -- Empty startup slots emit nothing.
  local key=(known and tostring(s.row.entity)or'0')..':'..s.serial
  if s.hint_key==key then return end
  local ops={{record=R,field=F.known,value=known and 1 or 0},
   {record=R,field=F.production_entity,value=known and s.row.entity or 0},
   {record=R,field=F.production_selection,value=s.serial}}
  local result=o.transport.publish(p.id,s.view,ops,{full=true,priority=false})
  if result then s.hint_key=key;s.announced=known;metrics.hints=metrics.hints+1 end
 end
 local function advance(s)
  s.serial=s.serial+1;assert(s.serial<=4294967295,'prepared_identity_exhausted')
 end
 local function reconcile(p,s)
  if not valid_pair(p,s)then return end
  local row=desired(p,s.view)
  local changed=s.row~=row
  if changed then advance(s);s.row=row;s.source=nil;s.projection=factory.initialize();s.hint_key=nil end
  if not row then
   if changed then
    local ops=assert(s.projection.update({},0,s.serial))
    if o.transport.is_open(p.id,s.view)then
     o.transport.publish(p.id,s.view,s.projection.full_ops(),{full=true,priority=false})
     metrics.published=metrics.published+1
    else hint(p,s,false)end
   end
   return
  end
  if s.serial==0 then advance(s)end
  local stamp=o.stamp(p.id,row.entity)
  if not changed and s.source and s.stamp==stamp then metrics.duplicates=metrics.duplicates+1;hint(p,s,true);return end
  metrics.snapshots=metrics.snapshots+1
  local source=o.snapshot(p.id,row.entity,row.unit)
  -- Snapshot production may synchronously invalidate identity or retire world.
  if not valid_pair(p,s)or desired(p,s.view)~=row or s.row~=row then return end
  assert(type(source)=='table'and type(source.learning)=='table','prepared_private_source_required')
  local ops=assert(s.projection.update(source,row.entity,s.serial))
  s.source,s.stamp=source,stamp
  if o.transport.is_open(p.id,s.view)then
   if #ops>0 or changed then
    o.transport.publish(p.id,s.view,changed and s.projection.full_ops()or ops,{full=changed,priority=false})
    metrics.published=metrics.published+1
   end
  else hint(p,s,true)end
 end
 local drain
 local function schedule()
  if scheduled or running or not current()or head>#queue then return end
  scheduled=true
  o.after(function()scheduled=false;drain()end)
 end
 drain=function()
  if running or not current()then return end
  running=true;local began=clock();local work=0
  while head<=#queue and work<2 and(work==0 or(clock()-began)*1000<1)do
   local job=queue[head];head=head+1
   if dirty[job.key]==job then
    dirty[job.key]=nil
    if valid_pair(job.p,job.s)then
     work=work+1;metrics.work_items=metrics.work_items+1
     local ok,why=pcall(reconcile,job.p,job.s)
     if not ok then metrics.errors=metrics.errors+1;running=false;schedule();error(why,0)end
    end
   end
  end
  running=false;metrics.passes=metrics.passes+1
  metrics.max_pass_work=math.max(metrics.max_pass_work,work)
  metrics.max_pass_ms=math.max(metrics.max_pass_ms,(clock()-began)*1000)
  if head>#queue then queue={};head=1 else schedule()end
 end
 local function enqueue(p,s)
  if not s.probed and not o.transport.is_open(p.id,s.view)then return end
  local key=p.id..':'..s.view;local old=dirty[key]
  if old and old.p==p and old.s==s then return end
  local job={key=key,p=p,s=s};dirty[key]=job;queue[#queue+1]=job
  -- One coalesced continuation only while changed pairs exist; no idle think.
  schedule()
 end
 local function affected(row)
  if row.kind==BASIC then
   local p=owner(row.owner,false);local s=p and p.slots[11]
   if s then enqueue(p,s)end
  else
   for _,p in pairs(players)do
    local s=p.slots[12+row.owner]
    if p.team==row.team and s then enqueue(p,s)end
   end
  end
 end
 local function detach(row)
  buildings[row.entity]=nil;local index=(row.kind==BASIC and basic or advanced)[row.owner]
  if index then
   index.members[row.entity]=nil;index.count=index.count-1;index.row=nil
   if index.count==1 then local _,remaining=next(index.members);index.row=remaining end
  end
  affected(row)
 end
 function api.building(payload)
  if not current()or type(payload)~='table'then return false end
  local kind=payload.building_id;if kind~=ADVANCED then return false end
  local id,entity=tonumber(payload.player_id),tonumber(payload.entindex)
  local prior=integer(entity,1,4294967295)and buildings[entity]
  if prior and(prior.unit~=payload.unit or prior.owner~=id or prior.team~=payload.team or prior.kind~=kind)then detach(prior);prior=nil end
  if not integer(id,0,o.max_players-1)or not integer(entity,1,4294967295)or not payload.unit
   or not o.valid_unit(payload.unit,entity)then metrics.invalid=metrics.invalid+1;return false,'prepared_identity_unsupported'end
  if prior and prior.unit==payload.unit and prior.owner==id and prior.team==payload.team and prior.kind==kind then return false end
  if prior then detach(prior)end
  local row={entity=entity,unit=payload.unit,owner=id,team=payload.team,kind=kind}
  buildings[entity]=row;local indexes=kind==BASIC and basic or advanced
  local index=indexes[id]or{members={},count=0};indexes[id]=index;index.members[entity]=row;index.count=index.count+1
  index.row=index.count==1 and row or nil
  metrics.identity_events=metrics.identity_events+1;affected(row)
  return index.count==1,index.count~=1 and'prepared_duplicate_owner_lab'or nil
 end
 function api.destroy(payload)
  if not current()or type(payload)~='table'then return end
  local row=buildings[tonumber(payload.entindex)]
  if row and payload.unit==row.unit then detach(row)end
 end
 function api.changed(payload)
  local id=tonumber(payload and payload.player_id);local p=owner(id,false);if not p then return end
  local source=tonumber(payload.source_entindex)
  if source then
   local row=buildings[source];if not row then return end
   local view=row.kind==BASIC and row.owner==id and 11 or row.kind==ADVANCED and row.team==p.team and 12+row.owner
   local s=view and p.slots[view];if s then enqueue(p,s)end
  else for _,s in pairs(p.slots)do if s.row or desired(p,s.view)then enqueue(p,s)end end end
 end
 function api.progression(payload)
  local p=owner(tonumber(payload and payload.player_id),false);if not p then return end
  local level=tonumber(payload.rebirth_level)
  if level==nil and(payload.reason=='star_blessing_attributes_per_second'or payload.reason=='archive_building_minute_growth')then return end
  if level==nil then level=(o.current_rebirth or o.rebirth)(p.id)end
  if level==p.rebirth then return end;p.rebirth=level
  if o.invalidate_learning then o.invalidate_learning(p.id)end
  api.changed(payload)
 end
 function api.level_changed(payload)
  local p=owner(tonumber(payload and payload.player_id),false)
  if not p then return end
  local tech,level=payload.tech_id,tonumber(payload.level)
  if type(tech)=='string'and level then
   if p.levels[tech]==level then return end;p.levels[tech]=level
  end
  if o.invalidate_learning then o.invalidate_learning(p.id)end
  api.changed(payload)
 end
 function api.disconnect(payload)
  local id=tonumber(payload and payload.player_id);if not integer(id,0,o.max_players-1)then return end;players[id]=nil
  for key,job in pairs(dirty)do if job.p.id==id then dirty[key]=nil end end
 end
 function api.dispose()
  live=false;players={};dirty={};queue={};head=1;scheduled=false;o.cancel()
 end
 function api.reset()
  dirty={};queue={};head=1;scheduled=false;o.cancel()
  -- Same-world service reinitialization retains live subscriptions. A real
  -- new world is disposed and constructs a different service/transport scope.
  for _,p in pairs(players)do
   if identity(p.id)==p.handle then
    p.rebirth=o.rebirth(p.id);p.levels=o.levels and o.levels(p.id)or{}
    for _,s in pairs(p.slots)do if s.row or desired(p,s.view)then enqueue(p,s)end end
   end
  end
 end
 function api.inspect()return{metrics=metrics,queued=#queue-head+1,scheduled=scheduled,world=world}end
 for view=12,15 do
  local view_id=view
  o.transport.register_view(view_id,{
   background_snapshot=true,
   snapshot=function(id)
    local p=owner(id,false);local s=p and p.slots[view_id]
    if not s or not s.source or not s.row or desired(p,view_id)~=s.row then return nil end
    return s.projection.full_ops()
   end,
   probe=function(id)
    local p=owner(id,true);if not p then return end
    if view_id-12==id then return end
    local s=get_slot(p,view_id);s.probed=true
    if desired(p,view_id)or s.row or s.announced then enqueue(p,s)end
   end,
   close=function(id)local p=players[id];if p then p.slots[view_id]=nil end end,
  })
 end
 local function subscribe(event,fn)bus.subscribe(event,function(p)if current()then fn(p)end end)end
 subscribe(events.BUILDING_CREATED,api.building);subscribe(events.BUILDING_CHANGED,api.building);subscribe(events.BUILDING_DESTROYED,api.destroy)
 subscribe(research_events.LEVEL_CHANGED,api.level_changed)
 subscribe(events.HERO_PROGRESSION_CHANGED,api.progression)
 subscribe(events.PLAYER_DISCONNECTED,api.disconnect);subscribe(events.PLAYER_DEFEATED,api.disconnect)
 -- One initialization inventory read; no per-ready/player/selection world scan.
 for _,row in ipairs(o.list()or{})do metrics.index_visits=metrics.index_visits+1;api.building(row)end
 return api
end
return M
