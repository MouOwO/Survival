-- Explicit Tools diagnostic. Require/default start is inert. Start after
-- isolate_writes() but before four-owner preparation to catch BUILDER_READY.
-- No gameplay patches, native removal wrappers, attack listeners or spawning.
local M={}
local KEY,TASK='SURVIVAL_BUILDER_LIFECYCLE_PROBE','manual_builder_lifecycle_probe'
local function bus() return require('core/event_bus') end
local function events() return require('core/events') end
local function numeric(v) return type(v)=='number' and v==v and math.abs(v)<math.huge and v or nil end
local function call(unit,name)
    local ok,v=pcall(function() return unit and unit[name] and unit[name](unit) end)
    if ok then return v,true end;return nil,false
end
local function mode() return GameRules and select(1,call(GameRules,'GetGameModeEntity')) end
local function now() return GameRules and numeric(call(GameRules,'GetGameTime')) end
local function current(s)
    return s and _G[KEY]==s and s.mode==mode() and s.guard==_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION
        and s.guard.mode==s.mode and s.bus_generation==bus().get_generation()
end
local function inspect(unit)
    if not unit then return {present=false} end
    local null,known=call(unit,'IsNull')
    if not known or null then return {present=false,is_null=null==true,native_null_known=known} end
    local row={present=true,entindex=numeric(call(unit,'entindex')),unit_name=call(unit,'GetUnitName'),
        health=numeric(call(unit,'GetHealth')),max_health=numeric(call(unit,'GetMaxHealth')),
        native_owner=numeric(call(unit,'GetPlayerOwnerID'))}
    if type(row.unit_name)~='string' then row.unit_name=nil end
    local alive,alive_known=call(unit,'IsAlive');row.alive,row.alive_known=alive==true,alive_known
    local invulnerable,invulnerable_known=call(unit,'IsInvulnerable')
    row.invulnerable,row.invulnerable_known=invulnerable==true,invulnerable_known
    local ok,origin=pcall(function() return unit:GetAbsOrigin() end)
    row.native_origin_valid=ok and origin~=nil
    if row.native_origin_valid then
        local valid,p=pcall(function() return {x=numeric(origin.x),y=numeric(origin.y),z=numeric(origin.z)} end)
        if valid and p.x and p.y and p.z then row.position=p else row.native_origin_valid=false end
    end
    local ok_owner,owner=pcall(require('systems/player_context_service').owner_player_id,unit,true)
    row.context_owner=ok_owner and numeric(owner) or nil
    return row
end
local function copy(source)
    if type(source)~='table' then return source end
    local r={};for k,v in pairs(source) do r[k]=copy(v) end;return r
end
local function record(s,id,kind,extra)
    if s.status~='running' or not current(s) then return end
    if id~=nil and (type(id)~='number' or id<0 or id>3 or id~=math.floor(id)) then return end
    s.total=s.total+1
    local row={sequence=s.total,kind=kind,player_id=id,game_time=now(),native_state=numeric(call(GameRules,'State_Get'))}
    for k,v in pairs(extra or {}) do row[k]=v end
    s.trace[(s.total-1)%256+1]=row
    if id~=nil then s.counts[id][kind]=(s.counts[id][kind] or 0)+1 end
    if s.print_events then
        print(string.format('[BUILDER_LIFECYCLE] event=%s owner=%s entity=%s alive=%s hp=%s origin_valid=%s attacker=%s:%s',
            kind,tostring(id),tostring(row.body and row.body.entindex or row.entindex),
            tostring(row.body and row.body.alive),tostring(row.body and row.body.health),
            tostring(row.body and row.body.native_origin_valid),tostring(row.attacker and row.attacker.unit_name),
            tostring(row.attacker and row.attacker.entindex)))
    end
end
local function signature(row)
    return table.concat({tostring(row.present),tostring(row.alive),tostring(row.native_origin_valid),
        tostring(row.context_owner),tostring(row.entindex)},':')
end
local function observe(s,id,unit,kind)
    local body=inspect(unit)
    local watched=s.watched[id]
    if watched and body.present and body.alive and body.native_origin_valid then watched.last_alive=copy(body) end
    if watched and watched.signature==signature(body) and kind=='body_transition' then return end
    if watched then watched.signature=signature(body) end
    record(s,id,kind,{body=body,last_alive=watched and copy(watched.last_alive) or nil})
end
function M.start(options)
    options=options or {}
    if options.enabled~=true then return {ok=false,error='probe_default_off'} end
    assert(IsServer and IsServer() and IsInToolsMode and IsInToolsMode(),'Tools server only')
    assert(GetMapName()=='template_map','template_map only')
    assert(not _G[KEY] or _G[KEY].status~='running','Stop the earlier lifecycle observer first')
    local guard=assert(_G.SURVIVAL_REAL_GAME_STRESS_ISOLATION,'Call isolate_writes before this observer')
    assert(mode() and guard.mode==mode(),'Current isolated world required')
    local duration=options.duration_seconds or 600
    assert(type(duration)=='number' and duration>=10 and duration<=1800,'Bounded 10..1800 second diagnostic required')
    local s={mode=mode(),guard=guard,bus_generation=bus().get_generation(),status='running',started=now(),
        duration=duration,print_events=options.print_events~=false,watched={},counts={},trace={},total=0,subscriptions={}}
    for id=0,3 do s.counts[id]={} end
    _G[KEY]=s
    local function subscribe(name,fn) s.subscriptions[#s.subscriptions+1]=bus().subscribe(events()[name],function(p)
        if current(s) and s.status=='running' then fn(p) end
    end) end
    subscribe('BUILDER_READY',function(p)
        local id=tonumber(p.player_id);if not id or id<0 or id>3 or id~=math.floor(id) then return end
        local unit=p.builder or p.unit
        local old=s.watched[id]
        s.watched[id]={unit=unit,entindex=numeric(call(unit,'entindex'))}
        observe(s,id,unit,old and 'builder_replaced' or 'builder_ready')
    end)
    subscribe('ENGINE_ENTITY_KILLED',function(p)
        local index=numeric(p.victim_entindex) or numeric(call(p.victim,'entindex'))
        for id,w in pairs(s.watched) do if w.unit==p.victim or (p.victim==nil and index==w.entindex) then
            record(s,id,'builder_native_death',{body=inspect(w.unit),entindex=index,
                attacker=inspect(p.attacker),last_alive=copy(w.last_alive),native_keys_present=p.keys~=nil})
        end end
    end)
    for _,name in ipairs({'PLAYER_DEFEATED','PLAYER_DISCONNECTED','HERO_READY','HERO_SUMMONED','HERO_REMOVED'}) do
        local label=name:lower()
        subscribe(name,function(p)
            local id=tonumber(p.player_id);if not id or id<0 or id>3 or id~=math.floor(id) then return end
            record(s,id,label,{entindex=numeric(p.entindex),defeat_cleanup=p.defeat_cleanup==true,
                body=s.watched[id] and inspect(s.watched[id].unit) or nil})
        end)
    end
    for _,name in ipairs({'BUILDING_CREATED','BUILDING_DESTROYED'}) do
        local label=name:lower()
        subscribe(name,function(p)
            if p.building_id~='wall' and p.building_id~='main_city' then return end
            record(s,tonumber(p.player_id),label,{building_id=p.building_id,entindex=numeric(p.entindex),
                body=s.watched[tonumber(p.player_id)] and inspect(s.watched[tonumber(p.player_id)].unit) or nil})
        end)
    end
    require('core/scheduler').every(1,function()
        if _G[KEY]~=s then return false end
        if not current(s) or s.status~='running' then M.stop('world_or_bus_changed');return false end
        if now()-s.started>=s.duration then M.stop('duration_complete');return false end
        for id,w in pairs(s.watched) do observe(s,id,w.unit,'body_transition') end
        return true
    end,TASK)
    return {ok=true,status='running',diagnostic_only=true,interval_seconds=1,no_attack_observation=true,
        start_before_builder_preparation=true,native_removal_hook=false}
end
function M.snapshot()
    local s=assert(_G[KEY],'Enable the observer first')
    local result={status=s.status,current_world=current(s),event_total=s.total,trace_dropped=math.max(0,s.total-256),
        scope='tools_diagnostic_builder_lifecycle_only',network_clients_verified=false,owners={},events={},stop_reason=s.stop_reason}
    if not current(s) then return result end
    for id=0,3 do
        local w=s.watched[id]
        local response=bus().request(events().BUILDER_GET_REQUEST,{player_id=id}) or {}
        result.owners[#result.owners+1]={player_id=id,events=copy(s.counts[id]),registered_entindex=w and w.entindex,
            cached_body=inspect(w and w.unit),last_alive=w and copy(w.last_alive),
            formal_ok=response.ok==true,formal_current=inspect(response.ok and response.builder or nil),
            formal_error=type(response.error)=='string' and response.error:sub(1,120) or nil,
            player_defeated=require('systems/player_context_service').is_defeated(id)}
    end
    for i=math.max(1,s.total-255),s.total do result.events[#result.events+1]=copy(s.trace[(i-1)%256+1]) end
    return result
end
function M.stop(reason)
    local s=_G[KEY];if not s then return false end
    for _,sub in ipairs(s.subscriptions) do bus().unsubscribe(sub) end;s.subscriptions={}
    if s.status=='running' then require('core/scheduler').cancel(TASK);s.status='stopped';s.stop_reason=reason or 'explicit_stop' end
    return true
end
return M
