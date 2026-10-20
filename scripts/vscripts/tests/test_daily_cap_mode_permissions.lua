package.path = "scripts/vscripts/?.lua;" .. package.path
local calendar=require("systems/archive_calendar")
local clock=172800
calendar.set_clock(function() return clock end)
local day=tostring(calendar.day())
local account=7000
local player={id=0}
DOTA_MAX_TEAM_PLAYERS=1
PlayerResource={IsValidPlayerID=function(_,id) return id==0 end,IsFakeClient=function() return false end,
    GetTeam=function() return 2 end,GetPlayer=function() return player end,GetConnectionState=function() return 2 end,
    GetSteamAccountID=function() return account end}
GameRules={PlayerHasCustomGameHostPrivileges=function() return true end,GetGameTime=function() return 100 end}
package.loaded["core/logger"]={info=function() end,warn=function() end}
local entitlement_updates=0
package.loaded["systems/player_entitlement_service"]={replace_all=function() entitlement_updates=entitlement_updates+1 end}
local setup=require("systems/match_setup_service")
setup.init("daily-cap-session")
local receipt={authenticated=true,account_id="7000",match_session_id="injected_fixture",
    progression={loaded=true,clear_counts={n10=1},standard_clear_counts={n10=1},rich_clear_counts={n10=1},
        cold_clear_counts={n10=1},scourge_clear_counts={}},
    daily_limits={day_key=day,by_key={
        clear={earned=20,limit=20,remaining=0,capped=0},
        mode_rich={earned=19,limit=20,remaining=1,capped=0},
        mode_cold={earned=10,limit=10,remaining=0,capped=1},
        mode_scourge={earned=0,limit=10,remaining=10,capped=0},
        secret={earned=1,limit=1,remaining=0,token="must not be copied"},
    },token="must not be copied"}}
local defer_auth, pending_auth=false,nil
local provider={init=function() end,resolve_account_id=function() return tostring(account) end,fetch_snapshot=function() end,
    authenticate=function(_,success) if defer_auth then pending_auth=success else success(receipt) end end}
local profiles=require("systems/player_profile_service")
profiles.init({provider=provider})
local result=profiles.authenticate_player(0)
assert(result.ok and result.pending==false)
assert(profiles.get_profile(0)==nil,"mode permissions do not fabricate a loaded profile")
assert(entitlement_updates==0,"entry authentication must not apply combat entitlements")
local summary=assert(profiles.get_authenticated_daily_limits(0))
assert(summary.day_key==day and summary.by_key.clear.capped==1,"remaining is authoritative over a contradictory hint")
assert(summary.token==nil and summary.by_key.secret==nil,"pre-mode cache copies only the permission allowlist")
summary.by_key.clear.remaining=999
assert(profiles.get_authenticated_daily_limits(0).by_key.clear.remaining==0,"callers cannot mutate cached authority")
local function option(id)
    for _,row in ipairs(setup.snapshot().mode_options) do if row.mode_id==id then return row end end
end
assert(option("standard").daily_capped==1 and option("pure").daily_capped==1)
assert(option("rich").unlocked==1 and option("rich").daily_key=="clear" and option("rich").daily_capped==1,
    "global clear exhaustion also closes special modes with independent quota remaining")
assert(option("cold").daily_capped==1)
assert(option("scourge").daily_capped==1)
assert(option("fishing").daily_capped==nil,"other online reward streams remain usable")
assert(setup.select_mode(0,"standard","daily-cap-session").error=="mode_daily_limit_reached")
assert(setup.select_mode(0,"rich","daily-cap-session").error=="mode_daily_limit_reached")
assert(setup.select_mode(0,"cold","daily-cap-session").error=="mode_daily_limit_reached")
assert(not setup.is_mode_selected(),"a rejected old-client request never locks in a mode")
receipt.daily_limits.by_key.clear.earned=19
receipt.daily_limits.by_key.clear.remaining=1
require("core/event_bus").reset()
profiles.init({provider=provider})
assert(profiles.authenticate_player(0).ok)
assert(option("standard").daily_capped==0 and option("rich").daily_capped==0)
assert(option("cold").daily_key=="mode_cold" and option("cold").daily_capped==1,
    "independent mode exhaustion closes entry even while global quota remains")
assert(setup.select_mode(0,"cold","daily-cap-session").error=="mode_daily_limit_reached")
account=7001
assert(profiles.get_authenticated_daily_limits(0)==nil,"permissions cannot cross account identity")
account=7000
clock=clock+86400
defer_auth=true
assert(option("standard").daily_pending==1,"stale midnight permissions trigger server reauthentication")
assert(pending_auth and setup.select_mode(0,"standard","daily-cap-session").error=="mode_daily_limits_pending",
    "the UI cannot reset a stale quota locally to enter before the authoritative refresh")
receipt.daily_limits.day_key=tostring(calendar.day())
receipt.daily_limits.by_key.clear.earned=0
receipt.daily_limits.by_key.clear.remaining=20
pending_auth(receipt)
assert(option("standard").daily_capped==0 and not option("standard").daily_pending,
    "only the new authenticated day restores entry")
assert(setup.select_mode(0,"standard","daily-cap-session").ok)
local projections=0
package.loaded["systems/archive_daily_limits"]={snapshot=function(profile,date)
    projections=projections+1
    return {by_key={shadow={remaining=profile.save.archive.test_remaining},
        clear={key="clear",remaining=profile.save.archive.test_remaining,limit=20,earned=20}}}
end}
local function install(revision,remaining)
    assert(profiles.apply_snapshot(0,{schema_version=1,account_id="7000",revision=revision,
        entitlements={},achievements={},public={},save={gameplay_stats={},archive={test_remaining=remaining}}}).ok)
end
install(1,2)
local first=profiles.get_daily_limit(0,"shadow")
first.remaining=999
assert(profiles.get_daily_limit(0,"shadow").remaining==2 and projections==1,
    "ability painting reuses a private small projection without copying full inventories")
install(2,0)
assert(profiles.get_daily_limit(0,"shadow").remaining==0 and projections==2,"authoritative revisions invalidate the quota view")
clock=clock+86400
profiles.get_daily_limit(0,"shadow")
assert(projections==3,"new days invalidate the runtime quota view")
assert(option("standard").daily_capped==1,"loaded account authority supplies today's quota when the entry receipt is stale")
print("DAILY_CAP_MODE_PERMISSIONS_PASS: authenticated allowlist, session/account binding, server double check and new-day recovery")
