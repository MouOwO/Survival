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
local catalog,active_hash,catalog_loading,catalog_waiters=nil,bundle.hash,false,{}
local catalog_serial=0
local catalog_session,catalog_generation,require_expected_hash=nil,0,false
local seed_ok,seed=pcall(require,'config/generated/lottery_catalog_manifest')
local seed_md5=seed_ok and type(seed)=='table' and seed.config_hash==bundle.hash and type(seed.catalog_md5)=='string'
    and #seed.catalog_md5==32 and not seed.catalog_md5:find('[^0-9a-f]') and seed.catalog_md5 or nil
local session=tostring(DoUniqueString and DoUniqueString('lottery_http') or os.time()):gsub('[^%w_.-]','_')
local function catalog_scope()
    local current_session=tostring(require('systems/match_setup_service').get_session_id() or '')
    if current_session~=catalog_session then
        catalog_session=current_session;catalog_generation=catalog_generation+1
        catalog,active_hash,catalog_loading,catalog_waiters=nil,bundle.hash,false,{}
        catalog_serial,require_expected_hash=0,false
        caches,versions,loading,waiters,busy={},{},{},{},{}
        owners,epochs,published_epochs,full_required={},{},{},{}
    end
    return current_session
end
local function identity(id)
    catalog_scope()
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
local function stamp(snapshot,owner,hash)
    snapshot.account_id=owner.account;snapshot.session_id=owner.session
    snapshot.profile_mode=owner.mode;snapshot.config_hash=hash or active_hash
    snapshot.catalog_md5=catalog and catalog.catalog_md5 or nil
    return snapshot
end
local function publish(id,snapshots)
    caches[id]=caches[id] or {};versions[id]=versions[id] or {}
    for _,snapshot in ipairs(snapshots or {}) do
        stamp(snapshot,owners[id],snapshot.config_hash or active_hash)
        local pool=snapshot.selected_pool_id
        local old=not full_required[id] and caches[id][pool]
        local changes=old and delta.diff(old,snapshot)
        if not changes or #changes>0 then
            serial=serial+1
            if changes then
                local chunks=math.max(1,math.ceil(#changes/12))
                for chunk=1,chunks do
                    local part={};for i=(chunk-1)*12+1,math.min(chunk*12,#changes) do part[#part+1]=changes[i] end
                    bus.emit(events.LOTTERY_CHANGED,{player_id=id,snapshot=stamp({snapshot_scope='cache_patch',selected_pool_id=pool,cache_sequence=serial,base_sequence=versions[id][pool],chunk=chunk,chunks=chunks,changes=part},owners[id],snapshot.config_hash)})
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
    local job={owner=owner,epoch=epochs[id] or 0,hash=active_hash}
    loading[id]=job
    local function done(result)
        if loading[id]~=job then return end
        if not current(id,owner) then scope(id);return end
        loading[id]=nil
        if job.epoch~=(epochs[id] or 0) or job.hash~=active_hash then fetch(id);return end
        if result.ok then
            if result.config_hash and result.config_hash~=job.hash then
                result={ok=false,error='lottery_config_hash_mismatch'}
            else
                for _,snapshot in ipairs(result.snapshots or {}) do stamp(snapshot,owner,job.hash) end
            end
        end
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
    owner.provider.lottery_snapshot({account_id=owner.account,config_hash=job.hash},done,function(error) done({ok=false,error=error}) end)
end
local function view(id,pool)
    local cached=caches[id] and caches[id][pool]
    if not cached then return nil end
    -- Receipt replies can arrive after a newer push. Include the version on a
    -- separate view; the version itself must never become a diff-base field.
    local snapshot={};for key,value in pairs(cached) do snapshot[key]=value end
    snapshot.cache_sequence=versions[id] and versions[id][pool]
    return snapshot
end
local function valid_hash(value,length)
    return type(value)=='string' and #value==length and not value:find('[^0-9a-f]')
end
local function check_catalog(complete,force_body)
    local match_session=catalog_scope()
    if complete then catalog_waiters[#catalog_waiters+1]=complete end
    if catalog_loading then return end
    local provider=profiles.get_provider()
    if not provider or type(provider.lottery_catalog)~='function' then
        local callbacks=catalog_waiters;catalog_waiters={}
        for _,fn in ipairs(callbacks) do fn({ok=false,error='lottery_catalog_provider_required'}) end
        return
    end
    catalog_loading=true
    local generation=catalog_generation
    local function done(result)
        if generation~=catalog_generation or match_session~=catalog_scope() then return end
        catalog_loading=false
        local accepted=result and result.ok and valid_hash(result.catalog_md5,32) and valid_hash(result.config_hash,64)
        if accepted and result.unchanged then
            accepted=(catalog and catalog.catalog_md5==result.catalog_md5)
                or (not catalog and seed_md5==result.catalog_md5)
        elseif accepted then
            accepted=type(result.catalog_json)=='string' and #result.catalog_json>0
                and #result.catalog_json<=2097152 and not result.catalog_json:find('[\128-\255]')
        end
        if accepted then
            local changed=not catalog or catalog.catalog_md5~=result.catalog_md5 or catalog.config_hash~=result.config_hash
            if result.config_hash~=bundle.hash or (catalog and catalog.catalog_md5~=result.catalog_md5)
                or (not catalog and seed_md5 and seed_md5~=result.catalog_md5) then require_expected_hash=true end
            if not result.unchanged then
                catalog={ok=true,catalog_md5=result.catalog_md5,config_hash=result.config_hash,catalog_json=result.catalog_json}
            else
                catalog=catalog or {ok=true,catalog_md5=result.catalog_md5}
                catalog.config_hash=result.config_hash
            end
            catalog.session_id=match_session
            catalog.unchanged=catalog.catalog_json==nil
            active_hash=result.config_hash
            catalog.catalog_sequence=catalog_serial
            if changed then
                catalog_serial=catalog_serial+1
                catalog.catalog_sequence=catalog_serial
                bus.emit(events.LOTTERY_CATALOG_CHANGED,{catalog=catalog})
                -- Refresh every player's private projection in the background.
                -- Clients gate transactions until this same hash arrives.
                local ids={};for id in pairs(owners) do ids[#ids+1]=id end
                for _,id in ipairs(ids) do
                    full_required[id]=true
                    fetch(id,nil,true)
                end
            end
        else result={ok=false,error=result and result.error or 'lottery_catalog_invalid'} end
        local callbacks=catalog_waiters;catalog_waiters={}
        for _,fn in ipairs(callbacks) do fn(accepted and catalog or result) end
    end
    provider.lottery_catalog({md5=not force_body and (catalog and catalog.catalog_md5 or seed_md5) or ''},done,function(error) done({ok=false,error=error}) end)
end
local function catalog_for(md5,complete)
    catalog_scope()
    local function reply(result)
        if not result or not result.ok then complete(result or {ok=false,error='lottery_catalog_invalid'});return end
        if md5~=result.catalog_md5 and not result.catalog_json then check_catalog(reply,true);return end
        local response={ok=true,catalog_md5=result.catalog_md5,config_hash=result.config_hash,
            catalog_sequence=result.catalog_sequence,session_id=result.session_id,unchanged=md5==result.catalog_md5}
        if not response.unchanged then response.catalog_json=result.catalog_json end
        complete(response)
    end
    if catalog then reply(catalog) else check_catalog(reply) end
end
local function submit(payload,kind)
    local id=payload.player_id
    local owner=scope(id)
    if not owner then return {ok=false,error='http_profile_required'} end
    if kind~='lottery_read' then
        local expected=tostring(payload.expected_config_hash or '')
        if (expected~='' and expected~=active_hash) or (expected=='' and require_expected_hash) then
            return {ok=false,error='lottery_config_refresh_required',request_id=payload.request_id,pool_id=payload.pool_id}
        end
    end
    if busy[id] then return {ok=false,error='lottery_player_busy'} end
    local request_id=tostring(payload.request_id or '')
    if kind=='lottery_read' then operation=operation+1;request_id='read_'..operation end
    if #request_id<1 or #request_id>96 or request_id:find('[^%w_:.-]') then return {ok=false,error='lottery_request_id_invalid'} end
    local command={id=session..':'..kind..':'..request_id,kind=kind,pool_id=payload.pool_id,request_id=request_id}
    if kind=='lottery_draw' then command.count=payload.count
    elseif kind=='lottery_exchange' then command.item_id=payload.item_id
    else command.read_action=payload.read_action;command.revision=payload.revision end
    local job={owner=owner,kind=kind,hash=active_hash};busy[id]=job
    local attempts=0
    local function finish(result)
        if busy[id]~=job or not current(id,owner) then return end
        busy[id]=nil
        local response=type(result.response)=='table' and result.response or {ok=result.ok,error=result.error}
        response.request_id=payload.request_id;response.pool_id=payload.pool_id
        if not result.ok then response.ok=false;response.error=result.error end
        if kind=='lottery_read' then
            -- A read receipt changes only unread metadata. It does not need
            -- another account/catalog HTTP read after the authoritative write.
            local snapshot=view(id,payload.pool_id)
            if result.ok and snapshot and job.hash==active_hash then
                local copies={}
                for _,old in pairs(caches[id] or {}) do
                    local copy={};for k,v in pairs(old) do copy[k]=v end
                    local function update(pool)
                        local changed={};for k,v in pairs(pool or {}) do changed[k]=v end
                        if changed.id==payload.pool_id and changed.revision==payload.revision then
                            if payload.read_action=='details' then changed.update_unread=false end
                            if payload.read_action=='notice' then changed.notice_unread=false end
                        end
                        return changed
                    end
                    copy.selected_pool=update(old.selected_pool);copy.pools={}
                    for _,pool in ipairs(old.pools or {}) do copy.pools[#copy.pools+1]=update(pool) end
                    copies[#copies+1]=copy
                end
                publish(id,copies);snapshot=view(id,payload.pool_id)
            end
            if job.hash~=active_hash or published_epochs[id]~=(epochs[id] or 0) then
                -- An independent purchase/profile update during this receipt
                -- still requires its authoritative dynamic refresh.
                fetch(id,function(refreshed)
                    if payload.complete then payload.complete({ok=result.ok,
                        snapshot=refreshed.ok and view(id,payload.pool_id) or nil,
                        error=result.error or (not refreshed.ok and refreshed.error or nil)}) end
                end)
            elseif payload.complete then payload.complete({ok=result.ok,snapshot=snapshot,error=result.error}) end
            return
        end
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
        end,job.hash)
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
    bus.handle_request(events.LOTTERY_READ_ACK_REQUEST,function(p)
        local owner=scope(p.player_id)
        local complete=p.complete
        local function header(result)
            if result and not result.snapshot and current(p.player_id,owner) then
                -- Busy/transport failures still belong to this request's
                -- identity, so the client can release its pending read ack.
                result.snapshot=stamp({selected_pool_id=p.pool_id,
                    cache_sequence=versions[p.player_id] and versions[p.player_id][p.pool_id]},owner)
            end
            return result
        end
        p.complete=function(result)if complete then complete(header(result)) end end
        local result=submit(p,'lottery_read')
        if not (result and result.pending) then header(result) end
        return result
    end)
    bus.handle_request(events.LOTTERY_CATALOG_REQUEST,function(p)
        catalog_for(tostring(p.md5 or ''),p.complete);return {pending=true}
    end)
    bus.handle_request(events.LOTTERY_CACHE_RESYNC_REQUEST,function(p)
        full_required[p.player_id]=true
        fetch(p.player_id,nil,false)
        return {pending=true}
    end)
    bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(p)
        if p and p.player_id~=nil then
            local job=busy[p.player_id]
            if job and job.kind=='lottery_read' and p.reason=='archive_lottery_read' then return end
            fetch(p.player_id,nil,true)
        end
    end)
    local provider=profiles.get_provider()
    if provider and type(provider.lottery_catalog)=='function' then
        check_catalog()
        require('core/scheduler').every(30,function()check_catalog()end,'lottery_catalog_poll')
    end
end
function M.active_config_hash() catalog_scope();return active_hash end
return M
