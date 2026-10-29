-- Exercise the actual offline provider, profile validation/write gate, reducer,
-- persistence and archive service. Never mock update_save_sections.
package.path="scripts/vscripts/?.lua;"..package.path
require("tests/development_release_profile")
package.loaded["config/test_access"]={enabled=false}
package.loaded["config/player_web_auth"]={enabled=false}
package.loaded["systems/player_web_auth"]={enabled=function() return false end}
local session,mode,game_time="public_beta_real_memory_session_1","rich",0
package.loaded["systems/match_setup_service"]={get_session_id=function() return session end,
    get_mode=function() return mode end,get_profile_mode=function() return "standard" end,
    is_mode_selected=function() return true end}
local tasks,packets,listeners={},{},{}
package.loaded["core/scheduler"]={every=function(_,f,key) tasks[key]=f end,
    after=function(_,f,key) tasks[key]=f end,cancel=function(key) tasks[key]=nil end}
package.loaded["core/logger"]={info=function() end,warn=function() end}
package.loaded["systems/player_entitlement_service"]={replace_all=function() end}
package.loaded["systems/archive_online_clock"]={init=function() end,observe=function() end,
    disconnect=function() end,sample=function() end,flush=function() end}
package.loaded["systems/title_presentation_service"]={init=function() end}
package.loaded["config/generated/archive_categories"]={rows={},by_id={}}
Convars={RegisterConvar=function() end,GetStr=function(_,name)
    return name=="survival_offline_logic_test" and "1" or "" end}
GameRules={GetGameTime=function() return game_time end,GetGameModeEntity=function() return {} end}
PlayerResource={IsValidPlayerID=function(_,id) return id==0 or id==1 end,
    GetSteamAccountID=function(_,id) return 1000+id end,GetPlayer=function(_,id) return id end}
CustomGameEventManager={RegisterListener=function(_,name,f) listeners[name]=f end,
    Send_ServerToPlayer=function(_,id,name,data) packets[#packets+1]={id=id,name=name,data=data} end}
local external_calls=0
CreateHTTPRequestScriptVM=function() external_calls=external_calls+1;error("Offline must never call HTTP") end
local offline=require("debug/offline_logic_test")
assert(offline.configure() and offline.is_enabled())
local mode_test=require("debug/mode_unlock_test")
mode_test.reset(session)
assert(mode_test.is_enabled(),"Test must exercise the real readonly guard")
local profiles=require("systems/player_profile_service")
local options=assert(offline.profile_options())
profiles.init(options)
assert(offline.is_provider(profiles.get_provider()),"Exact actual provider identity required")
local function load(id)
    assert(profiles.authenticate_player(id,"public_beta_fixture").ok)
    assert(profiles.load_player(id,"public_beta_fixture").ok)
    assert(profiles.get_account_profile(id))
end
load(0);load(1)
local calendar=require("systems/archive_calendar")
local timestamp=1793307599
calendar.set_clock(function() return timestamp end)
local archive=require("systems/archive_service")
archive.init()
local function last()
    for i=#packets,1,-1 do if packets[i].name=="survival_public_beta_gift_snapshot" then return packets[i].data end end
end
local function tickets(id)
    return profiles.get_account_profile(id).save.content_inventory.special_lottery_ticket or 0
end
local function intent(id)
    return {id=id or "readonly:public_beta_gift:accepted",kind="benefit_claim",
        track="public_beta_login",tier_id="public_beta_login"}
end
local original_revision=profiles.get_account_profile(0).revision
assert(archive.public_beta_gift_snapshot(0).eligible==1 and tickets(0)==0)
-- Reason strings or an extra options argument cannot bypass the public API.
for _,reason in ipairs({"ordinary_write","archive_benefit_claim"}) do
    assert(profiles.update_save_sections(0,{content_inventory={special_lottery_ticket=999}},reason,
        {offline_public_beta=true}).error=="mode_unlock_test_read_only")
end
assert(profiles.get_account_profile(0).revision==original_revision and tickets(0)==0)
for _,field in ipairs({"count","item_id","today","event_at","content_inventory"}) do
    local command=intent();command[field]=999
    assert(profiles.apply_offline_public_beta_gift(0,command).error=="offline_public_beta_intent_invalid")
end
local wrong=intent();wrong.tier_id="daily_time_0"
assert(profiles.apply_offline_public_beta_gift(0,wrong).error=="offline_public_beta_intent_invalid")
assert(tickets(0)==0 and profiles.get_account_profile(0).revision==original_revision)
local claim=archive.public_beta_gift_claim(0,"real_memory_nonce_0001")
assert(claim.ok and claim.terminal and not claim.pending,"Real profile write must ACK the controlled gift")
assert(tickets(0)==2 and tickets(1)==0 and not archive.has_pending(0))
assert(profiles.get_account_profile(0).revision==original_revision+1)
assert(profiles.refresh_player(0,"verify_actual_memory_persistence").ok and tickets(0)==2,
    "Reload from the actual offline provider proves persistence, not only cached profile mutation")
assert(not archive.public_beta_gift_claim(0,"real_memory_nonce_0002").ok and tickets(0)==2)
-- The underlying readonly guard remains intact after a successful gift.
assert(profiles.update_save_sections(0,{content_inventory={special_lottery_ticket=999}}).error=="mode_unlock_test_read_only")
assert(tickets(0)==2)

-- A real persist failure leaves all sections/revision unchanged and the same
-- activity operation pending. Restoring the provider permits the bounded retry.
local real_provider=profiles.get_provider()
local persist=real_provider.persist_save
real_provider.persist_save=function() return false,"actual_memory_persist_failure" end
local failed=archive.public_beta_gift_claim(1,"real_memory_failure_0001")
assert(failed.pending and tickets(1)==0 and archive.has_pending(1))
real_provider.persist_save=persist
tasks.archive_retry()
assert(tickets(1)==2 and not archive.has_pending(1) and last().claim_result.ok==1)
assert(profiles.refresh_player(1,"verify_failed_then_retried").ok and tickets(1)==2)
timestamp=timestamp+1
assert(archive.public_beta_gift_snapshot(0).eligible==1,"05:00 boundary enables a new memory-only day")
assert(archive.public_beta_gift_claim(0,"real_memory_nextday_0001").ok and tickets(0)==4)
assert(external_calls==0)

-- A new actual offline session discards all preview inventory and claim days.
session="public_beta_real_memory_session_2"
mode_test.reset(session)
require("core/event_bus").reset()
profiles.init(assert(offline.profile_options()))
load(0)
archive.init()
assert(tickets(0)==0 and archive.public_beta_gift_snapshot(0).eligible==1)
assert(archive.public_beta_gift_claim(0,"real_memory_newworld_0001").ok and tickets(0)==2)

-- An injected HTTP-like provider is not the strict offline provider and cannot
-- use the private capability even if it exposes an identically named method.
local fake_writes=0
local fake={init=function() end,resolve_account_id=function() return "1000" end,
    fetch_snapshot=function(_,success) success({schema_version=1,account_id="1000",revision=1,
        entitlements={},achievements={},public={},save={gameplay_stats={},archive={},content_inventory={}}}) end,
    persist_save=function() fake_writes=fake_writes+1;return true end,
    archive_enabled=function() return true end}
require("core/event_bus").reset()
profiles.init({provider=fake})
assert(profiles.load_player(0,"injected_http_readonly").ok)
assert(not offline.is_provider(profiles.get_provider()))
assert(profiles.apply_offline_public_beta_gift(0,intent()).error=="offline_public_beta_provider_required")
assert(profiles.update_save_sections(0,{content_inventory={special_lottery_ticket=999}}).error=="mode_unlock_test_read_only")
assert(fake_writes==0 and tickets(0)==0 and external_calls==0)
print("PUBLIC_BETA_REAL_OFFLINE_PASS: real profile gate/provider/reducer/persist, private fixed-intent capability, atomic failure/retry, account/day/world isolation, readonly HTTP denied")
