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
local initialized_world
local catalog,active_hash,catalog_loading,catalog_waiters=nil,bundle.hash,false,{}
local catalog_serial=0
local catalog_session,catalog_generation,require_expected_hash=nil,0,false
local seed_ok,seed=pcall(require,'config/generated/lottery_catalog_manifest')
local seed_md5=seed_ok and type(seed)=='table' and seed.config_hash==bundle.hash and type(seed.catalog_md5)=='string'
    and #seed.catalog_md5==32 and not seed.catalog_md5:find('[^0-9a-f]') and seed.catalog_md5 or nil
local session=tostring(DoUniqueString and DoUniqueString('lottery_http') or os.time()):gsub('[^%w_.-]','_')
local pool_ids={map=true,cultivation=true,dragon_knight=true,summer=true}
local compact_transport,compact_factory,compact_lookup,compact_refresh
local compact_states,compact_failures={},{}
local function compact_bound(id)
    if not compact_transport then local ok,t=pcall(require,'ui/compact_ui_transport');if ok then compact_transport=t end end
    return compact_transport and compact_transport.is_bound and compact_transport.is_bound(id) or false
end
local function catalog_scope()
    local current_session=tostring(require('systems/match_setup_service').get_session_id() or '')
    if current_session~=catalog_session then
        catalog_session=current_session;catalog_generation=catalog_generation+1
        catalog,active_hash,catalog_loading,catalog_waiters=nil,bundle.hash,false,{}
        catalog_serial,require_expected_hash=0,false
        caches,versions,loading,waiters,busy={},{},{},{},{}
        owners,epochs,published_epochs,full_required={},{},{},{}
        compact_states,compact_failures={},{}
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
        compact_states[id]=nil
        compact_failures[id]=nil
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
    -- The compact adapter reads authoritative profile keys. Do not construct
    -- legacy diffs/catalogue events for a negotiated integer-only client.
    if compact_bound(id) then return end
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
                    if compact_bound(id)then
                        if compact_refresh then compact_refresh(id,nil,{headers=true})end
                    else full_required[id]=true;fetch(id,nil,true)end
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
    local started=type(GetSystemTimeMS)=='function' and GetSystemTimeMS() or nil
    local job={owner=owner,kind=kind,hash=active_hash};busy[id]=job
    local function timing(stage)
        if started and kind=='lottery_draw' then
            print('[LOTTERY_TIMING] stage='..stage..' elapsed_ms='..tostring(math.max(0,GetSystemTimeMS()-started)))
        end
    end
    local attempts=0
    local function finish(result)
        if busy[id]~=job or not current(id,owner) then return end
        timing('settlement_ack')
        busy[id]=nil
        local response=type(result.response)=='table' and result.response or {ok=result.ok,error=result.error}
        response.request_id=payload.request_id;response.pool_id=payload.pool_id
        if not result.ok then response.ok=false;response.error=result.error end
        if payload.compact_token and compact_bound(id) then
            if compact_refresh then
                compact_refresh(id,result.profile and (result.profile.account_profile or result.profile),
                    require('ui/compact_lottery_projection').command_changes(command,result),
                    {token=payload.compact_token,response=response,applied=result.ok==true and result.lottery_profile_applied==true})
            end
            if payload.complete then payload.complete({ok=response.ok,pending=response.pending,terminal=response.terminal,error=response.error,compact_handled=true}) end
            timing('compact_receipt_ready')
            return
        end
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
        -- Fast path uses only this authenticated, successfully applied commit.
        -- Fixed <=4 pool projections; no inventory/HUD scan and no extra HTTP.
        local projected=result.lottery_snapshots
        local valid_projection=result.ok and result.lottery_profile_applied==true
            and job.hash==active_hash and result.snapshot_config_hash==job.hash
            and type(projected)=='table' and #projected>=1 and #projected<=4
        local selected,seen=nil,{}
        if valid_projection then
            for _,snapshot in ipairs(projected) do
                local pool=type(snapshot)=='table' and snapshot.selected_pool_id
                if not pool_ids[pool] or seen[pool] then
                    valid_projection=false;break
                end
                seen[pool]=true
                if pool==payload.pool_id then selected=snapshot end
            end
            valid_projection=valid_projection and selected~=nil
        end
        if valid_projection then
            epochs[id]=(epochs[id] or 0)+1
            loading[id]=nil -- Late older reads no longer own this generation.
            for _,snapshot in ipairs(projected) do stamp(snapshot,owner,job.hash) end
            publish(id,projected);published_epochs[id]=epochs[id]
            response.snapshot=view(id,payload.pool_id)
            local callbacks=waiters[id] or {};waiters[id]={}
            for _,fn in ipairs(callbacks) do if current(id,owner) then fn({ok=true,snapshots=projected}) end end
            if payload.complete then payload.complete(response) end
            timing('receipt_snapshot_ready')
            return
        end
        fetch(id,function(refreshed)
            timing('fallback_snapshot_ready')
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
    local own_world=bus.get_generation and bus.get_generation() or bus
    if initialized and initialized_world==own_world then return end
    if initialized then
        local scheduler=require('core/scheduler')
        if scheduler.cancel then scheduler.cancel('lottery_catalog_poll') end
        -- Invalidate old asynchronous catalogue/profile work even if a Tools
        -- reload retained the same textual match-session value.
        catalog_session=nil;catalog_scope()
    end
    initialized,initialized_world=true,own_world
    local function current_world()
        return initialized_world==own_world and (not bus.get_generation or bus.get_generation()==own_world)
    end
    local function request(name,handler)
        bus.handle_request(name,function(payload)
            if not current_world() then return nil,'lottery_world_expired' end
            return handler(payload)
        end)
    end
    local function subscribe(name,handler)
        bus.subscribe(name,function(payload)if current_world() then return handler(payload) end end)
    end
    request(events.LOTTERY_SNAPSHOT_REQUEST,function(payload)
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
    request(events.LOTTERY_DRAW_REQUEST,function(p)return submit(p,'lottery_draw')end)
    request(events.LOTTERY_EXCHANGE_REQUEST,function(p)return submit(p,'lottery_exchange')end)
    request(events.LOTTERY_READ_ACK_REQUEST,function(p)
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
    request(events.LOTTERY_CATALOG_REQUEST,function(p)
        catalog_for(tostring(p.md5 or ''),p.complete);return {pending=true}
    end)
    request(events.LOTTERY_CACHE_RESYNC_REQUEST,function(p)
        full_required[p.player_id]=true
        -- Explicit invalidation (including a completed redemption) must retire
        -- an older in-flight read, not reuse its pre-redemption inventory.
        fetch(p.player_id,nil,true)
        return {pending=true}
    end)
    subscribe(events.PLAYER_PROFILE_CHANGED,function(p)
        if p and p.player_id~=nil then
            local job=busy[p.player_id]
            if compact_bound(p.player_id) then
                local context=require('ui/compact_profile_context').current(p.player_id)
                -- The submit completion owns its validated receipt and exact K
                -- keys. The synchronous profile event must not send it twice.
                if job and (job.kind=='lottery_draw' or job.kind=='lottery_read') then return end
                local cached=compact_states[p.player_id]
                if not context and cached and cached.projection.inspect().revision==p.revision then return end
                local current_profile=context and context.profile
                if not current_profile then
                    current_profile=profiles.get_account_profile and profiles.get_account_profile(p.player_id)
                        or profiles.get_profile and profiles.get_profile(p.player_id)
                end
                if compact_refresh then compact_refresh(p.player_id,current_profile,
                    context and context.compact_lottery_changes or {initialize=true}) end
                return
            end
            if job and job.kind=='lottery_read' and p.reason=='archive_lottery_read' then return end
            fetch(p.player_id,nil,true)
        end
    end)
    local provider=profiles.get_provider()
    if provider and type(provider.lottery_catalog)=='function' then
        check_catalog()
        require('core/scheduler').every(30,function()if current_world() then check_catalog() end end,'lottery_catalog_poll')
    end
end
function M.active_config_hash() catalog_scope();return active_hash end
local function compact_setup()
    if compact_factory then return true end
    local ok,lookup=pcall(require,'config/generated/ui_static_catalog_lookup')
    if not ok then return false end
    local factory,why=require('ui/compact_lottery_projection').new(lookup)
    if not factory then return false,why end
    compact_factory,compact_lookup=factory,lookup;return true
end
local function compact_catalog_ready()
    return seed_ok and type(seed)=='table'and type(seed.catalog_md5)=='string'
        and catalog and catalog.session_id==catalog_session and catalog.catalog_md5==seed.catalog_md5
end
local function compact_unknown()
    if not compact_setup()then return nil end
    local r=compact_lookup.by_key['lottery:state'];local f=compact_lookup.field_by_name
    local code=catalog and 6 or 2
    return {{record=r,field=f.known,value=0},{record=r,field=f.enabled,value=0},{record=r,field=f.error_code,value=code}},code
end
local function compact_entry(id,profile,replace)
    local owner=scope(id);if not owner or not compact_setup()then return nil end
    local entry=compact_states[id]
    if not entry or replace then
        profile=profile or (profiles.get_account_profile and profiles.get_account_profile(id)or profiles.get_profile(id))
        local projection,why=compact_factory.initialize(profile,{pending=busy[id]~=nil})
        if not projection then return nil,why end
        local intents=entry and entry.intents or{}
        entry={projection=projection,owner=owner,profile=profile,intents=intents,used_tokens=entry and entry.used_tokens or{},
            nonce_prefix=entry and entry.nonce_prefix or tostring(DoUniqueString and DoUniqueString('compact_lottery')or(session..'_'..tostring(operation+1))):gsub('[^%w_.-]','_')}
        for token,intent in pairs(intents)do projection.bind_intent(token,intent.pool,intent.count)end -- <=1 active authoritative operation.
        compact_states[id]=entry
    end
    return entry
end
local function compact_publish(id,entry,ops,full)
    for index,pool in ipairs(require('config/lottery_config').pool_order)do local view=200+index
        if compact_transport.is_open(id,view)then
            local selected=full and entry.projection.full_ops(pool.id)or entry.projection.filter(pool.id,ops)
            if #selected>0 then compact_transport.publish(id,view,selected,{full=full==true,priority=true})end
        end
    end
end
compact_refresh=function(id,profile,changes,receipt)
    if not compact_catalog_ready()then
        local ops,code=compact_unknown();if not ops then return nil end
        if compact_failures[id]~=code then
            compact_failures[id]=code;compact_states[id]=nil
            for index in ipairs(require('config/lottery_config').pool_order)do local view=200+index
                if compact_transport.is_open(id,view)then compact_transport.publish(id,view,ops,{full=true,priority=true})end
            end
        end
        return nil,'lottery_config_refresh_required'
    end
    local cold=compact_states[id]==nil or compact_failures[id]~=nil;compact_failures[id]=nil
    local entry=compact_entry(id,profile,false);if not entry then return nil end
    local ops,full={},cold
    if profile then
        if changes and changes.initialize then entry=compact_entry(id,profile,true);if not entry then return nil end;full=true
        else
            local reason;ops,reason=entry.projection.update(profile,changes or{headers=true},{pending=busy[id]~=nil})
            if not ops then return nil,reason end;entry.profile=profile
        end
    end
    if receipt and receipt.token~=0 then
        local intent=entry.intents[receipt.token]
        if not intent then return nil,'lottery_intent_unknown'end
        local result,why=entry.projection.receipt(receipt.token,receipt.response,receipt.applied)
        if not result then return nil,why end
        for _,op in ipairs(result)do ops[#ops+1]=op end
        if receipt.response.pending~=true and (receipt.response.ok~=true or receipt.applied)then entry.intents[receipt.token]=nil end
    end
    compact_publish(id,entry,ops,full);return true
end
function M.compact_open(id,pool)
    if not compact_bound(id) or not pool_ids[pool]then return nil end
    scope(id)
    if not compact_catalog_ready()then local ops,code=compact_unknown();compact_failures[id]=code;return ops end
    local entry=compact_entry(id);return entry and entry.projection.full_ops(pool)or nil
end
function M.compact_pool(record)
    if not compact_setup()then return nil end;return compact_factory.pool_id(record)
end
function M.compact_draw(id,pool,count,token,complete)
    if not compact_bound(id)or not pool_ids[pool]or(count~=1 and count~=10)or type(token)~='number'or token~=math.floor(token)or token<1 or token>16383 then return{ok=false,error='lottery_intent_invalid'}end
    if not compact_catalog_ready()then return{ok=false,error='lottery_config_refresh_required'}end
    local entry=compact_entry(id);if not entry then return{ok=false,error='http_profile_required'}end
    if entry.used_tokens[token]then return{ok=false,error='lottery_intent_token_reused'}end
    if next(entry.intents)then return{ok=false,error='lottery_player_busy'}end
    entry.projection.bind_intent(token,pool,count)
    local intent={pool=pool,count=count};entry.intents[token]=intent
    entry.used_tokens[token]=true
    local result=submit({player_id=id,pool_id=pool,count=count,request_id=entry.nonce_prefix..'_'..token,
        compact_token=token,expected_config_hash=active_hash,complete=complete},'lottery_draw')
    if not result.pending then compact_refresh(id,nil,nil,{token=token,response=result,applied=false})end
    return result
end
function M.compact_read(id,pool,action)
    local config=require('config/lottery_config');local definition=config.pools[pool]
    local actions={[1]='visit',[2]='details',[3]='notice'}
    if not compact_bound(id)or not definition or not actions[action]or not compact_catalog_ready()then return nil end
    return submit({player_id=id,pool_id=pool,read_action=actions[action],revision=definition.revision,
        compact_token=0,complete=function()end},'lottery_read')
end
return M
