-- Compact archive subscriptions. Only Open initializes one current R-row page.
-- Indexed commerce inventory changes project K rows through the existing
-- ownership adapter. Unknown source replacements rebuild only active pages;
-- they are explicit bounded cold work, never mislabeled incremental work.
local M={}
local function copy(v) if type(v)~="table" then return v end local r={} for k,c in pairs(v) do r[k]=copy(c) end return r end
local function need(v,e) if not v then error(e,0) end end
local function make(o)
 local lookup,transport=o.lookup,o.transport
 local live=true
 local function is_current() return live and (not o.is_current or o.is_current()) end
 local projector=assert(require("ui/compact_archive_projection").new(lookup))
 local goods=require("config/generated/archive_commerce_goods")
 local goods_view=require("systems/archive_commerce_goods")
 local ownership,vip,starjoy={},{},{}
 for _,item in ipairs(goods.rows) do if item.enabled~=false then
  if item.kind=="product" or item.kind=="vip" then
   ownership[item.ownership_id]=ownership[item.ownership_id] or {};table.insert(ownership[item.ownership_id],item.id)
   if item.kind=="vip" then vip[item.ownership_id]=vip[item.ownership_id] or {};table.insert(vip[item.ownership_id],item.id) end
  elseif item.kind=="starjoy" then starjoy[#starjoy+1]=item.id end
 end end
 local active,generation={},0
 local intents,acks,finished,intent_sizes,watching,complete={},{},{},{},{},nil
 local function ack_ops(player,category,ops)
  local saved=acks[player] and acks[player][category];if not saved then return ops end
  local root=lookup.by_key["archive:category:"..category];local F=lookup.field_by_name
  for _,name in ipairs({"request_token","success","terminal","error_code","arg_a"}) do
   if saved[name]~=nil then ops[#ops+1]={record=root,field=F[name],value=saved[name]} end
  end
  return ops
 end
 local metrics={opens=0,full_rows=0,changed_rows=0,full_rebuilds=0,closed_updates=0,snapshot_calls=0,unmapped_changes=0}
 local categories,view_ids={},{}
 for index,category in ipairs(lookup.archive_projection.categories) do categories[index]=category.id;view_ids[category.id]=100+index end
 local function rebuild(player,category)
  local state=active[player] and active[player][category];if not state then return nil end
  metrics.snapshot_calls=metrics.snapshot_calls+1
  local page=o.snapshot(player,category)
  if not page or page.ok~=true then return nil end
  page.daily_limits=nil
  local instance,ops=projector.initialize(page);need(instance,ops)
  state.instance=instance;state.header=copy(page);state.header.rows=nil
  state.revision=page.revision;state.profile_known=instance.inspect().known
  metrics.full_rows=metrics.full_rows+#page.rows;return ack_ops(player,category,ops)
 end
 local function source_record(category,id)
  local row=lookup.records[id];return row and not row.tombstone and row.domain=="archive" and row.category==category and row.kind=="row" and row or nil
 end
 local function intent(player,category,action,args)
  local state=active[player] and active[player][category];if not state then return nil,"archive_view_closed" end
  local row=args.arg_a and source_record(category,args.arg_a)
  local nonce="ca_"..player.."_"..state.generation.."_"..args.request_token
  local function execute(kind,id,level)
   intents[player]=intents[player] or {}
   local old=intents[player][nonce]
   if old then need(old.kind==kind and old.id==id and old.level==level,"archive_intent_token_conflict");return old.result end
   need((intent_sizes[player] or 0)<64,"archive_intent_capacity")
   local entry={category=category,token=args.request_token,kind=kind,id=id,level=level};intents[player][nonce]=entry
   intent_sizes[player]=(intent_sizes[player] or 0)+1
   local result=o.intent(player,kind,id,level,nonce,args.request_token)
   entry.result=result;if type(result)=="table" then complete(player,category,nonce,result) end
   return result
  end
  if action=="archive_title" then
   need(category=="titles" and (args.arg_a==0 or row),"archive_title_intent_invalid")
   return execute("title",row and row.business_id or "")
  end
  need(action=="archive_action","archive_intent_invalid")
  if category=="building" or category=="work" or category=="fragment" then
   need(row,"archive_item_intent_invalid")
   if category~="fragment" then need(type(args.arg_b)=="number" and args.arg_b==math.floor(args.arg_b) and args.arg_b>=0,"archive_expected_level_invalid") end
   return execute(category,row.business_id,args.arg_b)
  end
  need(category=="friend" or category=="ex" or category=="wife" or category=="concubine" or category=="beast","archive_action_not_supported")
  return execute("social",category)
 end
 for _,category in ipairs(categories) do local own=category
  transport.register_view(view_ids[own],{
   open=function(player)
    if not is_current() then return nil,"archive_world_expired" end
    generation=generation+1;active[player]={[own]={generation=generation}}
    if watching[player] then watching[player][own]=nil end
    metrics.opens=metrics.opens+1;return rebuild(player,own)
   end,
   snapshot=function(player)
    if not is_current() then return nil,"archive_world_expired" end
    local s=active[player] and active[player][own]
    if not s then return nil end
    return s.instance and ack_ops(player,own,s.instance.full_ops()) or rebuild(player,own)
   end,
   probe=function(player)
    if not is_current() then return nil,"archive_world_expired" end
    watching[player]=watching[player] or {};watching[player][own]=true
    local ops=ack_ops(player,own,{})
    if #ops>0 then return transport.publish(player,view_ids[own],ops,{full=true}) end
    return true
   end,
   close=function(player) if not is_current() then return nil,"archive_world_expired" end;if watching[player] then watching[player][own]=nil end;if active[player] then active[player][own]=nil;if not next(active[player]) then active[player]=nil end end return true end,
   intent=function(player,action,args)if not is_current() then return nil,"archive_world_expired" end;return intent(player,own,action,args)end})
 end
 local api={}
 complete=function(player,category,nonce,result)
  if not is_current() then return nil,"archive_world_expired" end
  local entry=intents[player] and intents[player][nonce]
  if not entry or entry.category~=category or type(result)~="table" then return nil,"archive_intent_unknown" end
  local pending=result.pending==true or result.pending==1
  local terminal=result.terminal==true or result.ok==true and not pending
  if entry.kind~="social" then terminal=not pending and result.terminal~=false end
  if not terminal then pending=true end
  local profile=o.profile and o.profile(player)
  local revision=profile and tonumber(profile.revision) or tonumber(result.revision) or 0
  need(revision>=0 and revision==math.floor(revision) and revision<=4294967295,"archive_ack_revision_invalid")
  local value={request_token=entry.token,success=result.ok==true and terminal and not pending and 1 or 0,
   pending=pending and 1 or 0,terminal=terminal and 1 or 0,error_code=result.ok==true and 0 or 1,arg_a=revision}
  acks[player]=acks[player] or {};local old=acks[player][category] or {};local F=lookup.field_by_name
  local root=lookup.by_key["archive:category:"..category];local ops={}
  for name,n in pairs(value) do if old[name]~=n then ops[#ops+1]={record=root,field=F[name],value=n} end end
  acks[player][category]=value;entry.result=result
  if terminal and not entry.finished then
   entry.finished=true;finished[player]=finished[player] or {cursor=0,ring={}};local f=finished[player];f.cursor=f.cursor%32+1
   local previous=f.ring[f.cursor];if previous then intents[player][previous]=nil;intent_sizes[player]=intent_sizes[player]-1 end;f.ring[f.cursor]=nonce
  end
  if #ops>0 and (active[player] and active[player][category] or watching[player] and watching[player][category]) then transport.publish(player,view_ids[category],ops) end
  return true
 end
 api.complete=complete
 function api.changed(player,profile,changes)
  if not is_current() then return nil,"archive_world_expired" end
  local views=active[player];if not views then metrics.closed_updates=metrics.closed_updates+1;return {closed=true,rows=0} end
  need(type(profile)=="table" and type(profile.save)=="table","archive_profile_required")
  changes=changes or {};local visited=0
  for category,state in pairs(views) do
   if state.revision~=profile.revision or changes.pending_changed then
    local pending_only=changes.pending_changed==true and state.instance~=nil
    for key in pairs(changes) do if key~="pending_changed" then pending_only=false end end
    local precise=pending_only or category=="commerce_goods" and type(changes.content_inventory)=="table" and not changes.replace and state.instance and state.profile_known==1
    if precise then
     -- The declared changeset must cover every changed source. Unknown source
     -- paths are never silently ignored as a supposedly precise update.
     for key in pairs(changes) do if key~="content_inventory" and key~="vip_claimed" and key~="starjoy_reward_level" and key~="pending_changed" then precise=false end end
    end
    if precise then
     local ids,set,rows={},{},{}
     local function add(id) if not set[id] then set[id]=true;ids[#ids+1]=id end end
     for _,raw in ipairs(changes.content_inventory or {}) do for _,id in ipairs(ownership[raw] or {}) do add(id) end end
     for _,raw in ipairs(changes.vip_claimed or {}) do for _,id in ipairs(vip[raw] or {}) do add(id) end end
     if changes.starjoy_reward_level then for _,id in ipairs(starjoy) do add(id) end end
     for _,id in ipairs(ids) do rows[#rows+1]=assert(goods_view.project_one(profile,id));visited=visited+1 end
     local header=copy(state.header);header.revision=profile.revision
     if o.header then header=o.header(player,category,profile,header) end
     local ops,reason=state.instance.update(header,rows)
     if not ops then precise=false else
      state.revision=profile.revision;state.header=header;metrics.changed_rows=metrics.changed_rows+#rows
      transport.publish(player,view_ids[category],ops);state.last_error=nil
     end
    end
    if not precise then
     metrics.unmapped_changes=metrics.unmapped_changes+1;metrics.full_rebuilds=metrics.full_rebuilds+1
     -- At most one currently subscribed page per callback. This is a genuine
     -- profile replacement cold rebuild, with an observable R-row metric.
     local ops=rebuild(player,category)
     if ops then transport.publish(player,view_ids[category],ops,{full=true}) end
    end
   end
  end
  return {rows=visited}
 end
 function api.disconnect(player) active[player]=nil;intents[player]=nil;acks[player]=nil;finished[player]=nil;intent_sizes[player]=nil;watching[player]=nil end
 function api.reset() active={};intents={};acks={};finished={};intent_sizes={};watching={} end
 function api.dispose() live=false;api.reset() end
 function api.inspect() return copy(metrics) end
 function api.view(category)return view_ids[category]end
 return api
end
function M.new(options)return make(options)end
local current,current_world
function M.init()
 local bus=require("core/event_bus")
 local own_world=bus.get_generation()
 if current and current_world==own_world then return current end
 if current then current.dispose() end
 current,current_world=nil,own_world
 local archive=require("systems/archive_service")
 local profiles=require("systems/player_profile_service")
 current=make({lookup=require("config/generated/ui_static_catalog_lookup"),transport=require("ui/compact_ui_transport"),snapshot=archive.snapshot,pending=archive.has_pending,
  is_current=function() return bus.get_generation()==own_world end,
  profile=function(player)return profiles.get_account_profile and profiles.get_account_profile(player) or profiles.get_profile(player)end,
  header=function(player,category,profile,header)
   if archive.compact_header then return archive.compact_header(player,category,profile,header) end
   header.pending=archive.has_pending(player) and 1 or 0;header.has_pass=require("systems/archive_calendar").has_pass(profile) and 1 or 0;return header
  end,
  intent=function(player,kind,id,level,nonce)
   if kind=="title" then return archive.equip_title(player,id)
   elseif kind=="building" then return archive.building_upgrade(player,id,level)
   elseif kind=="work" then return archive.work_upgrade(player,id,level)
   elseif kind=="fragment" then return archive.promote(player,id,nonce)
   elseif kind=="social" then return archive.social_draw(player,id,nonce) end
  end})
 return current
end
function M.changed(...)return M.init().changed(...)end
function M.complete(...)return M.init().complete(...)end
function M.disconnect(...)if current then return current.disconnect(...)end end
return M
