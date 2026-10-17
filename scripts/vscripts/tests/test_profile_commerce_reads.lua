package.path = 'scripts/vscripts/?.lua;' .. package.path
local bus, events = require('core/event_bus'), require('core/events')
local decoder = require('core/json_decoder')
local mode, session, now = 'standard', 'commerce_reads_session_1', 100
local accounts, tasks, fetches, auth = {}, {}, {}, {}
for id=0,3 do accounts[id]=tostring(1000+id) end
package.loaded['systems/match_setup_service']={
    get_mode=function() return mode end, get_session_id=function() return session end,
    is_mode_selected=function() return mode~=nil end,
}
package.loaded['core/logger']={info=function() end,warn=function() end,error=function() end}
package.loaded['core/scheduler']={every=function(_,callback,key) tasks[key]=callback end}
package.loaded['systems/player_entitlement_service']={replace_all=function() end}
local provider={
    init=function() end,
    resolve_account_id=function(id) return accounts[id] end,
    fetch_snapshot=function(account,success,failure)
        fetches[#fetches+1]={account=account,success=success,failure=failure}
    end,
    authenticate=function(account,success,failure)
        auth[#auth+1]={account=account,success=success,failure=failure}
    end,
}
package.loaded['systems/player_profile_providers/http_fishing_provider']=provider
GameRules={GetGameModeEntity=function() return {} end,GetGameTime=function() return now end}
PlayerResource={IsValidPlayerID=function(_,id) return accounts[id]~=nil end,
    GetSteamAccountID=function(_,id) return accounts[id] end}
local profiles=require('systems/player_profile_service')
local effects=require('systems/commerce_effects')
profiles.init()
local function snapshot(id,revision,inventory)
    return {schema_version=1,account_id=accounts[id],revision=revision,
        mode=mode,match_session_id=session,progression={loaded=true,clear_counts={}},
        entitlements={},achievements={},public={},
        save={gameplay_stats={},archive={},content_inventory=inventory or {}}}
end
local function patch(id,base,count)
    return {schema_version=1,account_id=accounts[id],mode=mode,match_session_id=session,
        update_id='commerce:'..id..':'..base,base_revision=base,revision=base+1,
        changes={save={content_inventory={[effects.ids.saw]=count}}}}
end

-- An entry-authentication receipt is not a loaded, mode-scoped inventory grant.
assert(not effects.owned(0,'saw') and profiles.get_content_inventory_count(0,effects.ids.saw)==nil)
assert(profiles.authenticate_player(0).pending)
auth[1].success({authenticated=true,account_id=accounts[0],match_session_id=session,
    progression={loaded=true,clear_counts={}},save={content_inventory={[effects.ids.saw]=1}}})
assert(profiles.is_authenticated_for_account(0,accounts[0]))
assert(not effects.owned(0,'saw'),'Authentication receipt cannot grant combat inventory')
for id=0,3 do
    assert(profiles.apply_snapshot(id,snapshot(id,1,{[effects.ids.saw]=1,[effects.ids.barrier]=1})).ok)
    assert(effects.owned(id,'saw') and effects.owned(id,'barrier'))
end

-- Count top-level getter calls separately from its recursively invoked copier.
local full_getter, copier = profiles.get_profile
for index=1,20 do
    local name,value=debug.getupvalue(full_getter,index)
    if not name then break end
    if name=='copy' then copier=value end
end
assert(copier,'Locate the real copier, not a source-line proxy')
local full_reads, copy_calls, scalar_reads = 0,0,0
debug.sethook(function()
    local fn=debug.getinfo(2,'f').func
    if fn==full_getter then full_reads=full_reads+1 end
    if fn==copier then copy_calls=copy_calls+1 end
end,'c')
for tick=1,16 do
    now=100+tick/30
    for id=0,3 do
        for worker=1,26 do assert(effects.owned(id,'saw'));scalar_reads=scalar_reads+1 end
        for enemy=1,61 do assert(effects.owned(id,'barrier'));scalar_reads=scalar_reads+1 end
        for _,key in ipairs({'saw','barrier','lumberyard'}) do
            assert(effects.owned(id,key)==(key~='lumberyard'));scalar_reads=scalar_reads+1
        end
    end
    tasks.http_profile_preload()
end
debug.sethook()
assert(scalar_reads==5760 and full_reads==0 and copy_calls==0,
    '104 workers + 244 enemies + runtime checks and preload perform zero full profile/copy calls')
assert(#fetches==0,'Loaded preload checks neither copy nor refetch profiles')

-- Mutation isolation remains the public full getter contract.
local view=profiles.get_profile(0)
view.save.content_inventory[effects.ids.saw]=0
assert(effects.owned(0,'saw') and profiles.get_profile(0).save.content_inventory[effects.ids.saw]==1)
assert(profiles.get_content_inventory_count('0',effects.ids.saw)==1)
assert(profiles.get_content_inventory_count(-1,effects.ids.saw)==nil)
assert(profiles.get_content_inventory_count(0.5,effects.ids.saw)==nil)
assert(profiles.get_content_inventory_count(math.huge,effects.ids.saw)==nil)
assert(profiles.get_content_inventory_count(0,{})==nil)
assert(profiles.get_content_inventory_count(0,'')==nil)

-- No frame cache or subscriber ordering can hide an ownership receipt patch.
local dispatched={}
bus.subscribe(events.PLAYER_PROFILE_CHANGED,function(payload)
    if payload.player_id==0 and payload.reason=='incremental' and payload.revision<=3 then
        dispatched[#dispatched+1]={revision=payload.revision,owned=effects.owned(0,'saw')}
    end
end)
assert(profiles.apply_incremental(patch(0,1,0)).ok and not effects.owned(0,'saw'))
assert(profiles.apply_incremental(patch(0,2,2)).ok and effects.owned(0,'saw'))
assert(#dispatched==2 and dispatched[1].revision==2 and not dispatched[1].owned
    and dispatched[2].revision==3 and dispatched[2].owned,
    'Both same-time receipts expose the new inventory during their event')
local invalid=patch(0,1,0);invalid.update_id='new-stale-receipt'
assert(profiles.apply_incremental(invalid).error=='base_revision_mismatch')
assert(effects.owned(0,'saw'),'Rejected patch cannot invalidate authorized ownership')
assert(profiles.update_save_section(1,'content_inventory',{}).ok and not effects.owned(1,'saw'),
    'Isolated local save replacements are also immediately visible')
assert(profiles.apply_incremental(patch(2,1,decoder.null)).ok and not effects.owned(2,'saw'))
assert(profiles.apply_snapshot(2,snapshot(2,3,{[effects.ids.saw]='2.9',negative=-2,nan=0/0,inf=math.huge})).ok)
assert(profiles.get_content_inventory_count(2,effects.ids.saw)==2)
for _,key in ipairs({'negative','nan','inf','absent'}) do assert(profiles.get_content_inventory_count(2,key)==0) end

-- Account changes fail closed immediately even before a new load/event.
local account=accounts[0]
accounts[0]='replacement-account'
assert(not effects.owned(0,'saw'))
accounts[0]=nil
assert(not effects.owned(0,'saw'))
accounts[0]=account
assert(effects.owned(0,'saw'))
assert(profiles.load_player(0,'explicit_reload').pending)
assert(not effects.owned(0,'saw'),'Loading invalidates the old gameplay profile synchronously')
fetches[1].failure('unauthorized')
assert(not effects.owned(0,'saw'),'Failed authorization cannot restore old inventory')
assert(profiles.apply_snapshot(0,snapshot(0,4,{[effects.ids.saw]=1})).ok)

-- Pure combat inventory is separate from owned items in the account/UI save.
mode='pure'
assert(not effects.owned(0,'saw'),'A mode change cannot reuse a standard baseline')
local pure=snapshot(0,5,{})
local business=snapshot(0,5,{[effects.ids.saw]=1})
business.mode,business.match_session_id,business.progression=nil,nil,nil
pure.account_profile=business
assert(profiles.apply_snapshot(0,pure).ok)
assert(profiles.get_account_profile(0).save.content_inventory[effects.ids.saw]==1)
assert(not effects.owned(0,'saw') and profiles.get_content_inventory_count(0,effects.ids.saw)==0)
assert(profiles.apply_incremental(patch(0,5,1)).ok and effects.owned(0,'saw'))
session='commerce_reads_session_2'
assert(not effects.owned(0,'saw'),'Session replacement invalidates ownership without waiting for an event')
mode=nil
assert(not effects.owned(0,'saw'))
mode='standard'
assert(profiles.apply_snapshot(0,snapshot(0,7,{[effects.ids.saw]=1})).ok and effects.owned(0,'saw'))

-- Keep old independent service mocks compatible without weakening live reads.
package.loaded['systems/player_profile_service']={get_profile=function()
    return {save={content_inventory={[effects.ids.saw]=1}}}
end}
assert(effects.owned(0,'saw'))
package.loaded['systems/player_profile_service']=profiles
assert(effects.owned(0,'saw'))
print('PROFILE_COMMERCE_READS_PASS: scalar_reads='..scalar_reads..' full_get_profile='..full_reads..
    ' recursive_copy='..copy_calls..' preload=0; same-tick receipts, account/auth/mode/session, pure inventory and copied getter isolation')
