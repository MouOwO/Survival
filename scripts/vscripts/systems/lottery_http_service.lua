-- Game-side transport/cache only. All rolls, prices and inventory mutations are HTTP-owned.
local profiles=require('systems/player_profile_service')
local adapter=require('systems/archive_http_adapter')
local bundle=require('config/generated/archive_http_bundle')
local bus=require('core/event_bus')
local events=require('core/events')
local delta=require('core/ui_snapshot_delta')
local M={}
local caches,versions,loading,waiters,busy={},{},{},{},{}
local owners,epochs,published_epochs,full_required={},{},{},{}
local serial,operation,initialized=0,0,false
local session=tostring(DoUniqueString and DoUniqueString('lottery_http') or os.time()):gsub('[^%w_.-]','_')
local function identity(id)
    local provider=profiles.get_provider()
    local account=provider and provider.resolve_account_id(id)
    local setup=require('systems/match_setup_service')
    local match_session=setup.get_session_id()
    local mode=type(setup.get_profile_mode)=='function'
        and setup.get_profile_mode() or setup.get_mode()
    if not account or not match_session or (mode~='pure' and mode~='standard') then return nil end
    return {account=account,session=match_session,mode=mode,provider=provider}
end
local function same(a,b)
    return a and b and a.account==b.account and a.session==b.session and a.mode==b.mode
end
local function scope(id)
    local owner=identity(id)
    if not same(owners[id],owner) then
        -- Late replies belong to their original player/session, never a reused slot.
        caches[id],versions[id],loading[id],waiters[id],busy[id]=nil,nil,nil,nil,nil
        epochs[id],published_epochs[id],full_required[id]=0,nil,nil
        owners[id]=owner
    end
    return owner
end
local function current(id,owner)
    return same(owners[id],owner) and same(identity(id),owner)
end
local function publish(id,snapshots)
    caches[id]=caches[id] or {};versions[id]=versions[id] or {}
    for _,snapshot in ipairs(snapshots or {}) do
        local pool=snapshot.selected_pool_id
        local old=not full_required[id] and caches[id][pool]
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
    full_required[id]=nil
end
local fetch
fetch=function(id,complete,refresh)
    local owner=scope(id)
    if not owner then
        if complete then complete({ok=false,error='http_profile_required'}) end
        return
    end
    waiters[id]=waiters[id] or {}
    if complete then table.insert(waiters[id],complete) end
    if refresh then epochs[id]=(epochs[id] or 0)+1 end
    -- Coalesce events, but retain their epoch so an older read cannot satisfy them.
    if loading[id] or busy[id] then return end
    local job={owner=owner,epoch=epochs[id] or 0}
    loading[id]=job
    local function done(result)
        if loading[id]~=job then return end
        if not current(id,owner) then scope(id);return end
        loading[id]=nil
        if job.epoch~=(epochs[id] or 0) then fetch(id);return end
        if result.ok then
            publish(id,result.snapshots)
            published_epochs[id]=job.epoch
        end
        local callbacks=waiters[id];waiters[id]={}
        for _,fn in ipairs(callbacks or {}) do
            if current(id,owner) then fn(result) end
        end
    end
    if type(owner.provider.lottery_snapshot)~='function' then done({ok=false,error='http_profile_required'});return end
    owner.provider.lottery_snapshot({account_id=owner.account,config_hash=bundle.hash},done,function(error) done({ok=false,error=error}) end)
end
local function view(id,pool)
    return caches[id] and caches[id][pool]
end
local function submit(payload,kind)
    local id=payload.player_id
    local owner=scope(id)
    if not owner then return {ok=false,error='http_profile_required'} end
    if busy[id] then return {ok=false,error='lottery_player_busy'} end
    local request_id=tostring(payload.request_id or '')
    if kind=='lottery_read' then operation=operation+1;request_id='read_'..operation end
    if #request_id<1 or #request_id>96 or request_id:find('[^%w_:.-]') then return {ok=false,error='lottery_request_id_invalid'} end
    local command={id=session..':'..kind..':'..request_id,kind=kind,pool_id=payload.pool_id,request_id=request_id}
    if kind=='lottery_draw' then command.count=payload.count
    elseif kind=='lottery_exchange' then command.item_id=payload.item_id
    else command.read_action=payload.read_action;command.revision=payload.revision end
    local job={owner=owner};busy[id]=job
    local attempts=0
    local function finish(result)
        if busy[id]~=job or not current(id,owner) then return end
        busy[id]=nil
        local response=type(result.response)=='table' and result.response or {ok=result.ok,error=result.error}
        response.request_id=payload.request_id;response.pool_id=payload.pool_id
        if not result.ok then response.ok=false;response.error=result.error end
        fetch(id,function(refreshed)
            -- Do not report a stale cached balance as the post-command snapshot.
            response.snapshot=refreshed.ok and view(id,payload.pool_id) or nil
            if kind=='lottery_read' and not result.ok then response.snapshot=nil end
            if payload.complete then payload.complete(kind=='lottery_read' and {ok=result.ok,snapshot=response.snapshot,error=result.error} or response) end
        end,true)
    end
    local function attempt()
        if busy[id]~=job or not current(id,owner) then return end
        attempts=attempts+1
        adapter.submit(id,command,function(result)
            if busy[id]~=job or not current(id,owner) then return end
            if not result.ok and not result.terminal and attempts<3 then
                require('core/scheduler').after(1,attempt,'lottery_retry_'..id)
            else finish(result) end
        end)
    end
    attempt()
    return {pending=true}
end
function M.init()
    if initialized then return end;initialized=true
    bus.handle_request(events.LOTTERY_SNAPSHOT_REQUEST,function(payload)
        local id=payload.player_id
        local owner=scope(id)
        if not owner then return {ok=false,error='http_profile_required'} end
        if payload.prefetch==1 then full_required[id]=true end
        if payload.read_action and payload.read_action~='' then return submit(payload,'lottery_read') end
        local snapshot=view(id,payload.pool_id)
        if payload.prefetch~=1 and snapshot and published_epochs[id]==(epochs[id] or 0)
            and not loading[id] and not busy[id] then return {ok=true,snapshot=snapshot} end
        fetch(id,function(result)
            if payload.complete then payload.complete({ok=result.ok,error=result.error,snapshot=result.ok and view(id,payload.pool_id) or nil}) end
        end,payload.prefetch==1)
        return {pending=true}
    end)
    bus.handle_request(events.LOTTERY_DRAW_REQUEST,function(p)return submit(p,'lottery_draw')end)
    bus.handle_request(events.LOTTERY_EXCHANGE_REQUEST,function(p)return submit(p,'lottery_exchange')end)
    bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(p)
        if p and p.player_id~=nil then fetch(p.player_id,nil,true) end
    end)
end
return M
