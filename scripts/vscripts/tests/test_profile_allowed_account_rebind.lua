-- Two admitted Steam accounts must never inherit the same slot's old cache.
package.path="scripts/vscripts/?.lua;"..package.path
package.loaded["config/test_access"]={enabled=true,allowed_steamids={
    "76561197960265829","76561197960265830","76561197960265831","76561197960265832"}}
local account,public,rights,fetches,persisted,changed=101,{}, {}, {}, {},0
IsServer=function()return true end
DisconnectClient=function()error("both fixture accounts are admitted")end
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,
    GetSteamAccountID=function()return account end,GetPlayer=function()return {} end}
package.loaded["core/logger"]={info=function()end,warn=function()end}
package.loaded["core/scheduler"]={every=function()end}
package.loaded["systems/player_entitlement_service"]={replace_all=function(id,value)rights[id]=value end}
CustomNetTables={SetTableValue=function(_,_,id,value)public[id]=value end}
local fail_resolver=false
local provider={init=function()end,resolve_account_id=function()
    if fail_resolver then error("identity unavailable")end
    return tostring(account)
end,fetch_snapshot=function(id,success,failure)fetches[#fetches+1]={id=id,success=success,failure=failure}end,
persist_save=function(id,save,revision)persisted[#persisted+1]={id=id,save=save,revision=revision};return true end}
local profiles=require("systems/player_profile_service")
profiles.init({provider=provider})
local bus,events=require("core/event_bus"),require("core/events")
bus.subscribe(events.PLAYER_PROFILE_CHANGED,function()changed=changed+1 end)
local function snapshot(id,revision)
    return {schema_version=1,account_id=tostring(id),revision=revision,
        entitlements={vip={active=id==101}},achievements={},public={},
        save={gameplay_stats={initial_wood=id},archive={marker="account_"..id},
            content_inventory={binding_probe=id}}}
end
local function commit(id,revision)
    account=id;assert(profiles.apply_snapshot(0,snapshot(id,revision)).ok)
end
local function old_patch(base)
    return {schema_version=1,account_id="101",update_id="old_"..base,base_revision=base,revision=base+1,
        changes={save={archive={marker="must_not_write"}}}}
end
commit(101,1)
assert(profiles.get_profile(0).account_id=="101" and profiles.get_account_profile(0).account_id=="101")
assert(profiles.is_loaded_for_account(0,"101") and profiles.get_content_inventory_count(0,"binding_probe")==101)
assert(profiles.update_save_section(0,"archive",{marker="authorized_A"}).ok and #persisted==1)
assert(profiles.apply_incremental(old_patch(2)).ok)
-- Both accounts pass the Steam admission policy. Only the cached binding changed.
account=102
assert(require("core/test_access_policy").allowed(0))
local before=changed
assert(profiles.get_profile(0)==nil and profiles.get_account_profile(0)==nil and profiles.get_public_profile(0)==nil)
assert(not profiles.is_loaded_for_account(0,"101") and not profiles.is_loaded_for_account(0,"102"))
assert(profiles.get_content_inventory_count(0,"binding_probe")==nil and profiles.get_daily_limit(0,"clear")==nil)
assert(changed==before+1 and next(rights[0])==nil and public["0"].revision==0,
    "account replacement invalidates private, public and entitlement projections once")
assert(not profiles.update_save_section(0,"archive",{marker="blocked_B"}).ok and #persisted==1)
assert(not profiles.apply_incremental(old_patch(2)).ok,"even an old duplicate receipt must fail closed")
assert(not profiles.apply_snapshot(0,snapshot(101,99)).ok,"a late A snapshot cannot bind to admitted B")
commit(102,1)
assert(profiles.get_profile(0).account_id=="102" and profiles.get_profile(0).save.archive.marker=="account_102")
assert(profiles.get_content_inventory_count(0,"binding_probe")==102)
assert(not profiles.apply_snapshot(0,snapshot(101,100)).ok)
assert(profiles.get_profile(0).account_id=="102","rejecting old A must not invalidate a valid B cache")
-- Exercise each writer as the first observer of the account replacement.
commit(101,4);account=102
assert(not profiles.update_save_section(0,"archive",{marker="blocked_write_first"}).ok and #persisted==1)
commit(101,5);account=102
assert(not profiles.apply_incremental(old_patch(5)).ok and profiles.get_profile(0)==nil)
commit(101,6);account=102
assert(profiles.get_public_profile(0)==nil and public["0"].revision==0)
commit(101,7);account=102
assert(not profiles.is_loaded_for_account(0,"101") and profiles.get_profile(0)==nil)
-- Reverse real profile transport callbacks. A must not clear or overwrite B.
account=101;assert(profiles.load_player(0).pending)
account=102;assert(profiles.load_player(0).pending)
assert(fetches[1].id=="101" and fetches[2].id=="102")
fetches[2].success(snapshot(102,20))
fetches[1].success(snapshot(101,101))
assert(profiles.get_profile(0).account_id=="102" and profiles.get_profile(0).revision==20)
-- A refresh may keep its original account loaded, but never across a rebind.
assert(profiles.refresh_player(0).pending)
account=101;fetches[3].success(snapshot(102,21))
assert(profiles.get_profile(0)==nil)
account=102;assert(profiles.get_profile(0)==nil,"returning to a retired account requires a new snapshot")
commit(102,22);fail_resolver=true
assert(profiles.get_profile(0)==nil and not profiles.is_loaded_for_account(0,"102"))
fail_resolver=false;assert(profiles.get_profile(0)==nil)
commit(102,23)
assert(profiles.update_save_section(0,"archive",{marker="authorized_B"}).ok and #persisted==2)
assert(persisted[2].id=="102" and profiles.get_profile(0).save.archive.marker=="authorized_B")
print("PROFILE_ALLOWED_ACCOUNT_REBIND_PASS: admitted A/B isolation, cache/permissions/public invalidation, all write paths, duplicate and late receipts, reversed transport, identity failure, legitimate rebind")
