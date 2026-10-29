package.path="scripts/vscripts/?.lua;"..package.path
require("tests/development_release_profile")
local function copy(v)
    if type(v)~="table" then return v end
    local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r
end
local definitions=require("config/generated/player_gameplay_stats")
local calendar=require("systems/archive_calendar")
local timestamp,game_time=1793307599,0 -- 2026-10-30 04:59:59, Beijing.
calendar.set_clock(function() return timestamp end)
local function profile(account)
    local p={account_id=account,revision=1,entitlements={},save={archive={},content_inventory={},gameplay_stats={}}}
    for _,r in ipairs(definitions.rows) do p.save.gameplay_stats[r.field_id]=r.default_value end
    return p
end
local accounts={[0]=profile("100"),[1]=profile("200")}
local writes,api_calls,requests,packets,tasks,listeners=0,0,{},{},{},{}
local readonly,memory,cloud,fail=false,false,false,false
local provider={persist_save=function() error("Persistence goes through the profile service") end}
package.loaded["systems/player_profile_service"]={
    get_account_profile=function(id) return copy(accounts[id]) end,
    -- Pure combat history is deliberately different from account eligibility.
    get_profile=function(id) local p=copy(accounts[id]);if p then p.save.archive={} end;return p end,
    get_provider=function() return provider end,
    update_save_sections=function(id,sections)
        if fail then return {ok=false,error="memory_persist_failed"} end
        for k,v in pairs(sections) do accounts[id].save[k]=copy(v) end
        accounts[id].revision=accounts[id].revision+1;writes=writes+1
        return {ok=true}
    end,
}
package.loaded["debug/mode_unlock_test"]={is_enabled=function() return readonly end}
package.loaded["debug/offline_logic_test"]={is_provider=function(value) return memory and value==provider end}
local adapter={enabled=function() return cloud end}
function adapter.submit(id,command,complete)
    api_calls=api_calls+1;requests[#requests+1]={player_id=id,command=copy(command),complete=complete}
end
package.loaded["systems/archive_http_adapter"]=adapter
package.loaded["core/scheduler"]={
    every=function(_,f,key) tasks[key]=f end,
    after=function(_,f,key) tasks[key]=f end,
    cancel=function(key) tasks[key]=nil end,
}
package.loaded["systems/archive_online_clock"]={init=function() end,observe=function() end,
    disconnect=function() end,sample=function() end,flush=function() end}
package.loaded["systems/title_presentation_service"]={init=function() end}
package.loaded["config/generated/archive_categories"]={rows={},by_id={}}
GameRules={GetGameTime=function() return game_time end,IsCheatMode=function() return false end}
PlayerResource={GetPlayer=function(_,id) if accounts[id] then return id end end,
    IsValidPlayerID=function(_,id) return accounts[id]~=nil end}
CustomGameEventManager={RegisterListener=function(_,name,f) listeners[name]=f end,
    Send_ServerToPlayer=function(_,id,name,data) packets[#packets+1]={id=id,name=name,data=copy(data)} end}
local archive=require("systems/archive_service")
archive.init()
local function last()
    for i=#packets,1,-1 do if packets[i].name=="survival_public_beta_gift_snapshot" then return packets[i].data end end
end
local function query(id)
    listeners.survival_public_beta_gift_request(nil,{PlayerID=id})
    return last()
end
local function claim(id,nonce)
    game_time=game_time+1
    listeners.survival_public_beta_gift_claim(nil,{PlayerID=id,request_id=nonce,
        count=999,day_key="future",account_id="other"})
    return last()
end
local first=query(0)
assert(first.ok and first.active==1 and first.eligible==1 and first.claimed==0)
assert(first.ticket_id=="special_lottery_ticket" and first.ticket_count==2 and first.ticket_name=="金色抽奖券")
assert(first.sequence>=1 and #first.login_key>=8 and first.revision==1)
assert(writes==0 and api_calls==0 and next(accounts[0].save.archive)==nil,"Eligibility reads cannot grant/init a bucket")
local second=query(0);assert(second.sequence>first.sequence and second.login_key==first.login_key)
local invalid=claim(0,"bad")
assert(invalid.claim_result.ok==0 and invalid.claim_result.terminal==1 and writes==0)
local granted=claim(0,"nonce_local_0001")
assert(granted.claimed==1 and granted.claim_pending==0 and granted.claim_result.ok==1)
assert(granted.claim_result.terminal==1 and granted.claim_result.pending==0)
assert(accounts[0].save.content_inventory.special_lottery_ticket==2 and writes==1)
assert(next(accounts[1].save.content_inventory)==nil and api_calls==0,"Player/account isolation")
assert(query(0).claimed==1,"Eligibility uses account profile, not pure combat projection")
local replay=query(0)
assert(replay.claim_result.request_id=="nonce_local_0001" and replay.claim_result.ok==1,
    "A query recovers a lost success ACK without replaying a claim")
claim(0,"nonce_local_0002")
assert(accounts[0].save.content_inventory.special_lottery_ticket==2 and writes==1)
local key=first.login_key
archive.init()
assert(query(0).login_key~=key and query(0).claimed==1,"New world key, same saved account day remains claimed")
timestamp=timestamp+1 -- exact 05:00 refresh.
assert(query(0).claimed==0 and query(0).eligible==1)
local nextday=claim(0,"nonce_nextday_0001")
assert(nextday.claimed==1 and accounts[0].save.content_inventory.special_lottery_ticket==4)

-- The real offline provider + real profile write gate are exercised separately
-- in test_public_beta_gift_offline.lua; this fixture does not mock that escape.
local before_api=api_calls
-- Read-only cloud test arenas never submit this exception as a real reward.
readonly,memory,cloud=true,false,true
accounts[0]=profile("100")
archive.init()
assert(query(0).eligible==0 and query(0).read_only==1)
assert(claim(0,"nonce_readonly_0001").claim_result.ok==0 and api_calls==before_api)

-- A cloud intent stays pending until BOTH a durable receipt and its profile
-- readback have been applied; retries retain exactly the same operation ID.
readonly,memory,cloud=false,false,true
archive.init()
local waiting=claim(0,"nonce_remote_0001")
assert(waiting.claim_pending==1 and waiting.claim_result.pending==1 and #requests==1)
local day=query(0).day_key
local receipt={ok=true,track="public_beta_login",tier_id="public_beta_login",period_id=day,
    rewards={{id="special_lottery_ticket",count=2,converted_points=0}}}
requests[1].complete({ok=true,terminal=true,response=receipt})
assert(last().claim_pending==1 and last().claim_result.ok==0,"An ACK without profile readback is not success")
tasks.archive_retry()
assert(#requests==2 and requests[2].command.id==requests[1].command.id)
local fresh=profile("100");fresh.revision=2
fresh.save.content_inventory.special_lottery_ticket=2
fresh.save.archive={benefits={days={[day]={claimed={public_beta_login={at=timestamp}}}}}}
requests[2].complete({ok=true,terminal=true,response=receipt,profile=copy(fresh)})
assert(last().claim_pending==1,"A received but not yet applied newer revision remains pending")
tasks.archive_retry()
assert(#requests==3 and requests[3].command.id==requests[1].command.id)
accounts[0]=copy(fresh) -- Real archive_http_adapter applies it before callback.
requests[3].complete({ok=true,terminal=true,response=receipt,profile=copy(fresh)})
local success=last()
assert(success.claimed==1 and success.claim_pending==0 and success.claim_result.ok==1)
assert(success.claim_result.request_id=="nonce_remote_0001" and success.claim_result.day_key==day)
local after_calls=api_calls
local recovered=query(0)
assert(recovered.claim_result.ok==1 and recovered.claim_result.request_id=="nonce_remote_0001")
assert(api_calls==after_calls,"Query recovery must not resubmit even the same receipt")

-- Old-day ACKs cannot fabricate today's claimed marker at the 05:00 boundary.
accounts[1]=profile("200")
local oldday=claim(1,"nonce_old_day_0001").day_key
local oldrequest=requests[#requests]
timestamp=timestamp+86400
local oldprofile=profile("200");oldprofile.revision=2
oldprofile.save.content_inventory.special_lottery_ticket=2
oldprofile.save.archive={benefits={days={[oldday]={claimed={public_beta_login={at=timestamp-86400}}}}}}
accounts[1]=copy(oldprofile)
oldrequest.complete({ok=true,terminal=true,profile=copy(oldprofile),response={ok=true,
    track="public_beta_login",tier_id="public_beta_login",period_id=oldday,
    rewards={{id="special_lottery_ticket",count=2}}}})
local late=last()
assert(late.claimed==0 and late.eligible==1 and late.claim_pending==0)
assert(late.claim_result.day_key==oldday and late.day_key~=oldday)

local row=require("config/generated/archive_benefit_rewards").by_id.public_beta_login
row.ends_at=timestamp
local stopped=query(0)
assert(stopped.active==0 and stopped.eligible==0 and stopped.ticket_count==2)
row.ends_at=0;row.starts_at=timestamp+1
assert(query(0).active==0)
row.starts_at=0;row.enabled=false
assert(query(0).active==0)
row.enabled=true
assert(query(0).active==1)
local packet_count=#packets
query(99)
assert(#packets==packet_count,"Invalid engine player slots are ignored without exposing another account")
print("public beta gift: account read-only eligibility, manual ACK, nonce recovery, 05:00, cross-session, offline/cloud isolation PASS")
