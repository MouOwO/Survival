-- Synthetic accounts and IO only; actual service, bus, delta, schema/projection.
package.path='scripts/vscripts/?.lua;'..package.path
local candidate=arg[1] or 'scripts/vscripts/systems/lottery_http_service.lua'
local events=require('core/events')
local bundle=require('config/generated/archive_http_bundle')
local seed=require('config/generated/lottery_catalog_manifest')
local lookup=require('config/generated/ui_static_catalog_lookup')
local results={}
local function fixture()
    local f={catalog={},reads={},messages={},bound={},accounts={[0]='100',[1]='101'},revisions={[0]=1,[1]=1},
        session='synthetic_world_1',generation=1,timers={},native=0,transactions=0,callbacks=0}
    local handlers,subscribers={},{}
    local provider={resolve_account_id=function(id)f.native=f.native+1;return f.accounts[id]end,
        lottery_catalog=function(p,done,failed)f.catalog[#f.catalog+1]={p=p,done=done,failed=failed}end,
        lottery_snapshot=function(p,done,failed)f.reads[#f.reads+1]={p=p,done=done,failed=failed}end}
    local function profile(id)return {schema_version=1,account_id=f.accounts[id],revision=f.revisions[id],mode='standard',match_session_id=f.session,
        save={archive={},gameplay_stats={},content_inventory={lottery_ticket=9,special_lottery_ticket=9}}}end
    package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
        get_account_profile=profile,get_profile=profile,
        is_authenticated_for_account=function(id,a)return a==f.accounts[id]end,
        is_loaded_for_account=function(id,a)return a==f.accounts[id]end}
    package.loaded['systems/match_setup_service']={get_session_id=function()return f.session end,
        get_mode=function()return 'standard'end,get_profile_mode=function()return 'standard'end}
    package.loaded['systems/archive_http_adapter']={submit=function()f.transactions=f.transactions+1;error('no mutation expected')end}
    package.loaded['core/event_bus']={get_generation=function()return f.generation end,
        handle_request=function(k,cb)handlers[k]=cb end,subscribe=function(k,cb)subscribers[k]=cb end,
        emit=function(k,p)if k==events.LOTTERY_CHANGED then f.messages[#f.messages+1]=p end end}
    package.loaded['ui/compact_ui_transport']={is_bound=function(id)return f.bound[id]==true end,
        is_open=function()return false end,publish=function()error('closed compact view must not publish')end}
    package.loaded['ui/compact_profile_context']={current=function()return nil end}
    package.loaded['core/scheduler']={every=function(n,cb,key)assert(n==30);f.timers[key]=cb end,
        after=function()error('no new timer expected')end,cancel=function(key)f.timers[key]=nil end}
    GetSystemTimeMS=function()return 100 end
    DoUniqueString=function()return 'synthetic_local' end
    f.service=assert(loadfile(candidate))();f.service.init()
    function f.event(id)subscribers[events.PLAYER_PROFILE_CHANGED]({player_id=id,revision=f.revisions[id],account_id=f.accounts[id]})end
    function f.ready(index,hash,md5)
        f.catalog[index or #f.catalog].done({ok=true,config_hash=hash or bundle.hash,
            catalog_md5=md5 or seed.catalog_md5,unchanged=not hash and not md5,catalog_json='{}'})
    end
    function f.snapshot(index,tickets,hash)
        local rows={}
        for _,pool in ipairs({'map','cultivation','dragon_knight','summer'})do
            rows[#rows+1]={selected_pool_id=pool,tickets=tickets or 9,pools={},items={}}
        end
        f.reads[index or #f.reads].done({ok=true,config_hash=hash or bundle.hash,snapshots=rows})
    end
    function f.request(id,kind,complete)
        return handlers[kind or events.LOTTERY_SNAPSHOT_REQUEST]({player_id=id,pool_id='map',
            complete=complete or function()f.callbacks=f.callbacks+1 end})
    end
    function f.poll()f.timers.lottery_catalog_poll()end
    function f.reset(same_session)
        f.generation=f.generation+1
        if not same_session then f.session='synthetic_world_'..f.generation end
        f.service.init()
    end
    return f
end
local function test(name,run)
    local f=fixture();run(f);assert(f.transactions==0)
    results[#results+1]=name
end

test('unknown_ready_and_changes_zero_legacy',function(f)
    f.event(0);local stable_native=f.native
    for _=1,100 do f.event(0)end
    assert(f.native==stable_native,'stable unknown revision must not repeat identity reads')
    assert(#f.catalog==1 and #f.reads==0 and #f.messages==0)
    f.ready();assert(#f.reads==0 and #f.messages==0)
    for i=2,101 do f.revisions[0]=i;f.event(0)end
    assert(#f.reads==0 and #f.messages==0,'unknown is not legacy even across real revisions')
    f.poll();f.ready();assert(#f.reads==0 and #f.messages==0)
    f.bound[0]=true
    local ops=assert(f.service.compact_open(0,'map'))
    assert(#ops>3 and #f.reads==0,'later compact reads current profile, no legacy HTTP')
end)

test('explicit_read_and_initial_catalog_coalesce',function(f)
    f.event(0)
    assert(f.request(0).pending and #f.reads==1)
    f.ready();assert(#f.reads==1,'initial same-hash catalog must not stale the pending read')
    f.snapshot(1);assert(#f.reads==1 and #f.messages==4 and f.callbacks==1)
    local cached=f.request(0);assert(cached.ok and cached.snapshot.tickets==9 and #f.reads==1)
    f.poll();f.ready();assert(#f.reads==1,'unchanged catalog must not refetch')
end)

test('explicit_resync_still_invalidates_old_read',function(f)
    f.event(0);f.ready();f.request(0)
    assert(f.request(0,events.LOTTERY_CACHE_RESYNC_REQUEST).pending)
    assert(#f.reads==1)
    f.snapshot(1,1);assert(#f.reads==2 and #f.messages==0 and f.callbacks==0)
    f.snapshot(2,9);assert(#f.messages==4 and f.callbacks==1)
    assert(f.request(0).snapshot.tickets==9)
end)

test('legacy_profile_change_preserves_authoritative_refresh',function(f)
    f.event(0);f.ready();f.request(0);f.snapshot(1)
    f.revisions[0]=2;f.event(0);assert(#f.reads==2)
    f.snapshot(2,12);assert(f.request(0).snapshot.tickets==12)
    assert(#f.messages==8 and f.messages[5].snapshot.snapshot_scope=='cache_patch')
end)

test('bind_during_read_drops_reply_and_callbacks',function(f)
    f.event(0);f.request(0);f.ready()
    assert(#f.reads==1)
    f.bound[0]=true
    f.snapshot(1);assert(#f.messages==0 and f.callbacks==0 and #f.reads==1)
    f.event(0);assert(#f.reads==1)
    f.bound[0]=false;f.revisions[0]=2;f.event(0)
    assert(#f.reads==1,'lost binding must not restore legacy without new explicit request')
    f.request(0);assert(#f.reads==2)
end)

test('bind_before_pending_catalog_no_legacy_http',function(f)
    f.event(0);f.request(0)
    f.bound[0]=true;f.ready();f.snapshot(1)
    assert(#f.reads==1 and #f.messages==0 and f.callbacks==0)
end)

test('compact_open_retires_legacy_even_if_binding_later_lost',function(f)
    f.event(0);f.ready();f.request(0)
    f.bound[0]=true;assert(#f.service.compact_open(0,'map')>3)
    f.bound[0]=false;f.snapshot(1);f.revisions[0]=2;f.event(0)
    assert(#f.messages==0 and f.callbacks==0 and #f.reads==1)
    f.request(0);assert(#f.reads==2)
end)

test('world_reset_same_text_session_drops_legacy_owner',function(f)
    f.event(0);f.request(0);local old=f.reads[1].done
    f.reset(true);f.event(0);f.ready()
    old({ok=true,snapshots={{selected_pool_id='map',tickets=999}}})
    assert(#f.reads==1 and #f.messages==0 and f.callbacks==0)
    f.request(0);assert(#f.reads==2)
end)

test('session_and_account_reuse_require_new_request',function(f)
    f.event(0);f.ready();f.request(0);local old=f.reads[1].done
    f.accounts[0]='102';f.revisions[0]=1;f.event(0)
    old({ok=true,snapshots={{selected_pool_id='map',tickets=999}}})
    assert(#f.reads==1 and #f.messages==0 and f.callbacks==0)
    f.request(0);f.snapshot(2);assert(#f.messages==4)
    f.session='synthetic_new_session';f.event(0);f.ready()
    assert(#f.reads==2,'new session may not inherit explicit legacy intent')
end)

test('multiple_players_negotiate_independently',function(f)
    f.event(0);f.event(1);f.ready();f.request(0);f.snapshot(1)
    f.revisions[0]=2;f.revisions[1]=2;f.event(0);f.event(1)
    assert(#f.reads==2 and f.reads[2].p.account_id=='100')
    f.snapshot(2,12);assert(#f.messages==8)
    f.bound[1]=true;assert(#f.service.compact_open(1,'map')>3 and #f.reads==2)
end)

test('real_catalog_replacement_retires_old_snapshot',function(f)
    f.event(0);f.ready();f.request(0)
    f.poll();local newer=string.rep('d',64);f.ready(nil,newer,string.rep('e',32))
    f.snapshot(1,1);assert(#f.reads==2 and #f.messages==0)
    assert(f.reads[2].p.config_hash==newer)
    f.snapshot(2,10,newer);assert(#f.messages==4 and f.callbacks==1)
end)

print('LEGACY_GATE_PASS scenarios='..#results..' stable_unknown_events=100 stable_unknown_identity_reads=0 changed_unknown_events=100 unknown_legacy_http=0 initial_catalog_duplicate_http=0 late_bound_callbacks=0 transactions=0')
