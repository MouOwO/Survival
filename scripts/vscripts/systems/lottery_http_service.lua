-- Game-side transport/cache only. All rolls, prices and inventory mutations are HTTP-owned.
local profiles=require('systems/player_profile_service')
local adapter=require('systems/archive_http_adapter')
local bundle=require('config/generated/archive_http_bundle')
local bus=require('core/event_bus')
local events=require('core/events')
local delta=require('core/ui_snapshot_delta')
local M={}
local caches,versions,loading,waiters,busy={},{},{},{},{}
local serial,operation=0,0
local session=tostring(DoUniqueString and DoUniqueString('lottery_http') or os.time()):gsub('[^%w_.-]','_')
local function publish(id,snapshots)
    caches[id]=caches[id] or {};versions[id]=versions[id] or {}
    for _,snapshot in ipairs(snapshots or {}) do
        local pool=snapshot.selected_pool_id;local old=caches[id][pool]
        local changes=old and delta.diff(old,snapshot)
        if not changes or #changes>0 then
            serial=serial+1
            if changes then
                local chunks=math.max(1,math.ceil(#changes/12))
                for chunk=1,chunks do
                    local part={};for i=(chunk-1)*12+1,math.min(chunk*12,#changes) do part[#part+1]=changes[i] end
                    bus.emit(events.LOTTERY_CHANGED,{player_id=id,snapshot={snapshot_scope='cache_patch',selected_pool_id=pool,cache_sequence=serial,base_sequence=versions[id][pool],chunk=chunk,chunks=chunks,changes=part}})
                end
            else
                local packet={};for k,v in pairs(snapshot) do packet[k]=v end
                packet.snapshot_scope='cache';packet.cache_sequence=serial
                bus.emit(events.LOTTERY_CHANGED,{player_id=id,snapshot=packet})
            end
            caches[id][pool]=snapshot;versions[id][pool]=serial
        end
    end
end
local function fetch(id,complete)
    waiters[id]=waiters[id] or {};if complete then table.insert(waiters[id],complete) end
    if loading[id] then return end
    local p=profiles.get_provider();local account=p and p.resolve_account_id(id)
    local function done(result)
        loading[id]=nil
        if result.ok then publish(id,result.snapshots) end
        local callbacks=waiters[id];waiters[id]={}
        for _,fn in ipairs(callbacks or {}) do fn(result) end
    end
    if not p or not p.lottery_snapshot or not account then done({ok=false,error='http_profile_required'});return end
    loading[id]=true
    p.lottery_snapshot({account_id=account,config_hash=bundle.hash},done,function(error) done({ok=false,error=error}) end)
end
local function view(id,pool)
    return caches[id] and caches[id][pool]
end
local function submit(payload,kind)
    local id=payload.player_id
    if busy[id] then return {ok=false,error='lottery_player_busy'} end
    local request_id=tostring(payload.request_id or '')
    if kind=='lottery_read' then operation=operation+1;request_id='read_'..operation end
    if #request_id<1 or #request_id>96 or request_id:find('[^%w_:.-]') then return {ok=false,error='lottery_request_id_invalid'} end
    local command={id=session..':'..kind..':'..request_id,kind=kind,pool_id=payload.pool_id,request_id=request_id}
    if kind=='lottery_draw' then command.count=payload.count
    elseif kind=='lottery_exchange' then command.item_id=payload.item_id
    else command.read_action=payload.read_action;command.revision=payload.revision end
    busy[id]=true
    local attempts=0
    local function finish(result)
        busy[id]=nil
        local response=type(result.response)=='table' and result.response or {ok=result.ok,error=result.error}
        response.request_id=payload.request_id;response.pool_id=payload.pool_id
        if not result.ok then response.ok=false;response.error=result.error end
        fetch(id,function()
            response.snapshot=view(id,payload.pool_id)
            if kind=='lottery_read' and not result.ok then response.snapshot=nil end
            if payload.complete then payload.complete(kind=='lottery_read' and {ok=result.ok,snapshot=response.snapshot,error=result.error} or response) end
        end)
    end
    local function attempt()
        attempts=attempts+1
        adapter.submit(id,command,function(result)
            if not result.ok and not result.terminal and attempts<3 then
                require('core/scheduler').after(1,attempt,'lottery_retry_'..id)
            else finish(result) end
        end)
    end
    attempt()
    return {pending=true}
end
function M.init()
    bus.handle_request(events.LOTTERY_SNAPSHOT_REQUEST,function(payload)
        if payload.prefetch==1 then caches[payload.player_id]=nil end
        if payload.read_action and payload.read_action~='' then return submit(payload,'lottery_read') end
        local snapshot=view(payload.player_id,payload.pool_id)
        if snapshot then return {ok=true,snapshot=snapshot} end
        fetch(payload.player_id,function(result)
            if payload.complete then payload.complete({ok=result.ok,error=result.error,snapshot=view(payload.player_id,payload.pool_id)}) end
        end)
        return {pending=true}
    end)
    bus.handle_request(events.LOTTERY_DRAW_REQUEST,function(p)return submit(p,'lottery_draw')end)
    bus.handle_request(events.LOTTERY_EXCHANGE_REQUEST,function(p)return submit(p,'lottery_exchange')end)
    bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(p)
        if not busy[p.player_id] then fetch(p.player_id) end
    end)
end
return M
