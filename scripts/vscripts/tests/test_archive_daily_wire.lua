-- Real daily projectors, archive subscription handler, timer and wire queue.
-- Synthetic accounts only: no Dota, HTTP, persistence or native size/FPS claim.
package.path="scripts/vscripts/?.lua;"..package.path
local raw_print=print
print=function() end
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for key,child in pairs(value) do out[key]=copy(child) end;return out
end
local encoder=require("core/json_encoder")
local encode,encodes=encoder.encode,0
encoder.encode=function(value) encodes=encodes+1;return encode(value) end
local decode=require("core/json_decoder").decode
local timers,listeners,packets,profiles,players={},{},{},{},{}
local now,game_time,profile_reads,projections,writes,http,fail_send=1800000000,0,0,0,0,0,false
local provider={archive_enabled=function() return false end}
package.loaded["core/test_access_policy"]={enabled=function() return false end,allowed=function() return true end,enforce=function() return true end}
package.loaded["core/scheduler"]={every=function(delay,fn,key) timers[key]={fn=fn,period=delay} end,
    after=function(delay,fn,key) timers[key]={fn=fn,at=game_time+delay} end,cancel=function(key) timers[key]=nil end}
package.loaded["systems/player_profile_service"]={
    get_account_profile=function(id) profile_reads=profile_reads+1;return copy(profiles[id]) end,
    get_profile=function(id) profile_reads=profile_reads+1;return copy(profiles[id]) end,
    get_provider=function() return provider end,
    update_save_sections=function() writes=writes+1;error("unexpected persistence") end}
package.loaded["systems/archive_http_adapter"]={enabled=function() return false end}
package.loaded["debug/mode_unlock_test"]={is_enabled=function() return true end}
package.loaded["debug/offline_logic_test"]={is_enabled=function() return true end,is_provider=function(value) return value==provider end}
package.loaded["systems/match_setup_service"]={get_mode=function() return "standard" end,
    get_profile_mode=function() return "standard" end,get_session_id=function() return "synthetic_daily_wire" end,
    is_mode_selected=function() return true end}
GameRules={GetGameTime=function() return game_time end,IsCheatMode=function() return false end}
IsInToolsMode=function() return false end
IsServer=function() return true end
IsClient=function() return false end
RandomInt=function(low) return low end
CreateHTTPRequestScriptVM=function() http=http+1;error("unexpected HTTP") end
PlayerResource={GetPlayer=function(_,id) return players[id] end,
    IsValidPlayerID=function(_,id) return profiles[id]~=nil end,
    GetConnectionState=function() return 2 end}
CustomNetTables={SetTableValue=function() end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_,player,name,data)
        if name=="survival_daily_wire" and fail_send and data.chunk==2 then error("synthetic send failure") end
        packets[#packets+1]={player=player,name=name,data=copy(data)}
    end}
local bus,events=require("core/event_bus"),require("core/events")
local calendar=require("systems/archive_calendar")
local daily=require("systems/archive_daily_rewards")
local original_daily=daily.snapshot
daily.snapshot=function(...) projections=projections+1;return original_daily(...) end
local archive
local function reset()
    bus.reset();timers,listeners,packets,profiles,players={},{},{},{},{}
    now,game_time=1800000000,0
    calendar.set_clock(function() return now end)
    local day=calendar.day()
    for id=0,3 do
        players[id]={id=id}
        profiles[id]={account_id="synthetic_"..id,revision=1,entitlements={},save={gameplay_stats={},content_inventory={},
            archive={daily_rewards={first_day=day,claimed={},count=0,item_counts={}}}}}
        for _,row in ipairs(require("config/generated/player_gameplay_stats").rows) do
            if row.enabled~=false then profiles[id].save.gameplay_stats[row.field_id]=tonumber(row.default_value) or 0 end
        end
    end
    package.loaded["systems/archive_service"]=nil
    archive=require("systems/archive_service");archive.set_clock(function() return now end);archive.init()
    profile_reads,projections,encodes,writes,http,fail_send=0,0,0,0,0,false
end
local function request(id,view,opened)
    listeners.survival_daily_request(nil,{PlayerID=id,wire_v=2,view_id=view,open=opened,subscribe=opened==1 and 1 or 0})
end
local function drain()
    local batches,max_batch=0,0
    while true do
        local key,entry
        for name,timer in pairs(timers) do if name:match("^archive_daily_wire:")
            and (not entry or timer.at<entry.at) then key,entry=name,timer end end
        if not key then break end
        timers[key]=nil;game_time=math.max(game_time,entry.at)
        local before=#packets;entry.fn();max_batch=math.max(max_batch,#packets-before);batches=batches+1
        assert(batches<1000,"wire queue did not settle")
    end
    assert(max_batch<=2,"one callback exceeds the two-packet work budget")
    return batches
end
local function daily_packets(name)
    local out={};for _,packet in ipairs(packets) do if packet.name==(name or "survival_daily_wire") then out[#out+1]=packet end end;return out
end
local function assemble(id)
    local pieces,first={}
    for _,packet in ipairs(daily_packets()) do if packet.player==players[id] then
        local p=packet.data
        first=first or p
        assert(p.sequence==first.sequence and p.view_id==first.view_id and p.session_id==first.session_id)
        assert(#p.payload_json<=650 and not pieces[p.chunk])
        pieces[p.chunk]=p.payload_json
    end end
    assert(first and #pieces==first.chunks,"incomplete wire document")
    return decode(table.concat(pieces)),first
end
local function apply(previous,changes)
    local out=copy(previous)
    for _,change in ipairs(changes) do
        local target=out
        for i=1,#change.path-1 do
            local key=tonumber(change.path[i]) or change.path[i]
            target=assert(target[key])
        end
        local key=tonumber(change.path[#change.path]) or change.path[#change.path]
        target[key]=change.remove==1 and nil or copy(change.value)
    end
    return out
end
local function business(value) value=copy(value);value.sequence=nil;return value end
local function clear_counts() packets={};profile_reads,projections,encodes=0,0,0 end

reset()
local legacy=archive.daily_snapshot(0)
local full_json_bytes=#encode(legacy)
clear_counts()
for id=0,3 do request(id,"view_"..id,1) end
assert(projections==4,"one initial real catalogue projection per player")
local initial_batches=drain()
local full,initial=assemble(0)
assert(initial.kind=="full" and full.ok==true and full.today==calendar.day())
assert(encode(business(full))==encode(business(legacy)),"full v2 must retain every real business field")
local initial_packets=#daily_packets()
local max_fragment,max_packet_json,max_kv_estimate=0,0,0
for _,packet in ipairs(daily_packets()) do
    max_fragment=math.max(max_fragment,#packet.data.payload_json)
    max_packet_json=math.max(max_packet_json,#encode(packet.data))
    -- Flat typed-KeyValues estimate plus a conservative 128-byte message/event
    -- reserve. This is a reproducible model, never a native protobuf measurement.
    local estimate=128
    for key,value in pairs(packet.data) do
        estimate=estimate+#key+2+(type(value)=="string" and #value+1 or 8)
    end
    max_kv_estimate=math.max(max_kv_estimate,estimate)
end
clear_counts()
for _=1,120 do now=now+1;timers.archive_daily_clock.fn() end
assert(profile_reads==0 and projections==0 and encodes==0 and #packets==0,
    "stable clock must do zero profile copies/catalogue projections/JSON encodes/network calls")
local stable={seconds=120,profile_reads=profile_reads,projections=projections,encodes=encodes,sends=#packets}
archive.send_daily(0)
assert(projections==0 and encodes==0 and #packets==0,"same revision call must not project/serialize")
profiles[0].revision=2
archive.send_daily(0)
assert(projections==1 and #daily_packets()==0,"unrelated revision must not transmit identical business data")
clear_counts()
local week=require("systems/archive_benefit_rewards").week(now)
profiles[0].save.archive.benefits={days={[tostring(calendar.day())]={seconds=60}},weeks={[tostring(week)]={seconds=60}}}
profiles[0].revision=3
archive.send_daily(0);drain()
local changes,delta=assemble(0)
assert(delta.kind=="delta" and delta.base_sequence==initial.sequence)
assert(#changes<12,"one minute should not retransmit catalogue definitions")
local updated=apply(full,changes)
assert(updated.benefits.daily_time.progress==1 and updated.benefits.weekly_time.progress==1)
for _,packet in ipairs(daily_packets()) do assert(packet.player==players[0],"private update leaked to another player") end
local minute_packets,minute_json=#daily_packets(),#encode(changes)
clear_counts();request(0,"view_0",1);drain()
local reopened,reopen=assemble(0)
assert(reopen.kind=="full" and encode(business(reopened))==encode(business(updated)))
assert(projections==0,"explicit resync can reuse the current projected catalogue")

-- A closed window retains only a changed eligibility hint, never a full page.
request(0,"view_0",0);clear_counts()
profiles[0].save.archive.daily_rewards.claimed[tostring(calendar.day())]=true
profiles[0].save.archive.daily_rewards.count=1
local cfg=require("config/generated/archive_benefit_rewards")
local claimed={};for _,row in ipairs(cfg.rows) do claimed[row.reward_id]=true end
profiles[0].save.archive.benefits.days[tostring(calendar.day())].claimed=copy(claimed)
profiles[0].save.archive.benefits.weeks[tostring(week)].claimed=copy(claimed)
profiles[0].revision=4
archive.send_daily(0);drain()
assert(#daily_packets()==0 and #daily_packets("survival_daily_hint")==1)
assert(daily_packets("survival_daily_hint")[1].data.claimable==0)
clear_counts();now=now+86400;timers.archive_daily_clock.fn();drain()
for _,packet in ipairs(daily_packets()) do
    assert(packet.player~=players[0],"day reset must not restart a closed full subscription")
end
local hints=daily_packets("survival_daily_hint")
local hint0;for _,packet in ipairs(hints) do if packet.player==players[0] then hint0=packet.data end end
assert(hint0 and hint0.claimable==1,"closed entry hint must refresh at the real day boundary")

-- Partial transfers cannot survive a close/reopen or a reused player handle.
reset();request(0,"old_view",1)
local pending=timers["archive_daily_wire:0"].fn
timers["archive_daily_wire:0"]=nil;pending();assert(#daily_packets()==2)
request(0,"old_view",0);clear_counts();pending();drain();assert(#daily_packets()==0)
request(0,"new_view",1);drain()
local _,fresh=assemble(0);assert(fresh.kind=="full" and fresh.view_id=="new_view")
clear_counts();request(0,"new_view",1)
local stale=timers["archive_daily_wire:0"].fn
players[0]={id=0,reused=true};stale();assert(#daily_packets()==0)
request(0,"replacement",1);drain();assert(select(2,assemble(0)).view_id=="replacement")
clear_counts()
profiles[0].account_id="different_account_same_slot"
profiles[0].save.archive.daily_rewards.claimed[tostring(calendar.day())]=true
profiles[0].save.archive.daily_rewards.count=1
archive.send_daily(0);drain()
local rebound,rebound_packet=assemble(0)
assert(rebound_packet.kind=="full" and rebound.claimed==1,"same revision from another account cannot reuse the old base")

-- Pass expiry has one guarded deadline, with no per-second account copying.
reset();profiles[0].entitlements.archive_pass={active=true,expires_at=now+30}
request(0,"expiring",1);drain();local pass_full=assemble(0);assert(pass_full.has_pass==1)
clear_counts()
for _=1,29 do now=now+1;timers.archive_daily_clock.fn() end
assert(profile_reads==0 and projections==0 and #packets==0)
now=now+1
local deadline=assert(timers["archive_pass_deadline:0"]);timers["archive_pass_deadline:0"]=nil;deadline.fn();drain()
local pass_changes,pass_packet=assemble(0)
assert(pass_packet.kind=="delta" and apply(pass_full,pass_changes).has_pass==0)

reset();request(0,"failure",1)
fail_send=true
local task=timers["archive_daily_wire:0"].fn;timers["archive_daily_wire:0"]=nil
assert(not pcall(task),"fixture native send failure should propagate")
fail_send=false;clear_counts();request(0,"failure",1);drain()
assert(select(2,assemble(0)).kind=="full","failed transfer cannot become a delta base")

reset();request(0,"before_reset",1)
local stale_reset=timers["archive_daily_wire:0"].fn
bus.reset();archive.init();clear_counts();stale_reset();assert(#packets==0,"reset must invalidate old callbacks")
request(0,"after_reset",1);drain();local _,new_session=assemble(0)
assert(new_session.sequence==1,"session reset must reset transport counters")
clear_counts();request(0,"after_reset",1)
local stale_disconnect=timers["archive_daily_wire:0"].fn
bus.emit(events.PLAYER_DISCONNECTED,{player_id=0});clear_counts();stale_disconnect();drain();assert(#daily_packets()==0)
assert(writes==0 and http==0,"test must never mutate persistence or use HTTP")
-- The same real service now routes negotiated v3 through the shared dispatcher,
-- leaving the retained v2 compatibility branch inactive for that client.
local views,published,opened={},{},{}
local registered_views=0
local static_lookup=assert(loadfile("output/ui_static_catalog_20261103/scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"))()
package.loaded["config/generated/ui_static_catalog_lookup"]=static_lookup
package.loaded["ui/compact_ui_transport"]={register_view=function(id,handler) registered_views=registered_views+1;views[id]=handler;return true end,
    is_open=function(id) return opened[id]==true end,
    publish=function(id,view,ops,settings) published[#published+1]={id=id,view=view,ops=copy(ops),settings=copy(settings)};return true end}
local ready=true
package.loaded["systems/startup_loading_service"]={is_player_ready=function() return ready end}
reset();local v3=assert(views[3]);assert(v3.probe(0))
assert(#published==1 and #published[1].ops==2 and published[1].settings.full)
opened[0]=true;local full_v3=assert(v3.open(0));assert(#full_v3>80)
published={};clear_counts()
local date=calendar.day();local current_week=require("systems/archive_benefit_rewards").week(now)
profiles[0].save.archive.benefits={days={[tostring(date)]={seconds=60}},weeks={[tostring(current_week)]={seconds=60}}}
profiles[0].revision=2
require("ui/compact_profile_context").with(0,{compact_daily_changes={benefit_tracks={"daily_time","weekly_time"}}},function()
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_online_checkpoint"})
end)
assert(#published==1 and #published[1].ops==2 and not published[1].settings.full)
for _,packet in ipairs(packets) do assert(packet.name~="survival_daily_wire" and packet.name~="survival_daily_snapshot") end
opened[0]=false;v3.close(0);published={}
profiles[0].save.archive.daily_rewards.claimed[tostring(date)]=true;profiles[0].save.archive.daily_rewards.count=1;profiles[0].revision=3
require("ui/compact_profile_context").with(0,{compact_daily_changes={daily_state=true,daily_claimed_days={date}}},function()
    bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=0,reason="archive_daily_claim"})
end)
assert(#published==1 and #published[1].ops==2 and #v3.snapshot(0)==2,"closed v3 must publish only its hint")
opened[0]=true;assert(#v3.open(0)>80)
local requests=0
archive.daily_claim=function(id,target) requests=requests+1;assert(id==0 and target==date);return {ok=false,terminal=true,error="synthetic private backend detail"} end
game_time=game_time+1
assert(v3.intent(0,"daily_claim",{arg_a=date,request_token=1}));assert(requests==1)
assert(v3.intent(0,"daily_claim",{arg_a=date,arg_b=9,request_token=2})==nil and requests==1)
ready=false
assert(v3.intent(0,"daily_claim",{arg_a=date,request_token=3})==nil and requests==1)
-- The real event bus is reset while the same archive module remains loaded.
-- New transport handlers register once; saved callbacks from the old world
-- cannot reopen, publish, acknowledge or invoke the original claim authority.
ready=true
local old_view=v3;local registrations_before=registered_views
bus.reset();published={};archive.init()
assert(registered_views==registrations_before+1 and views[3]~=old_view,"new bus world must register daily view3")
assert(old_view.open(0)==nil and old_view.snapshot(0)==nil and old_view.probe(0)==nil and old_view.close(0)==nil)
assert(old_view.intent(0,"daily_claim",{arg_a=date,request_token=4})==nil and requests==1 and #published==0,"old world callback performed work")
opened[0]=true;assert(#views[3].open(0)>80)
local same_world_view=views[3];archive.init()
assert(registered_views==registrations_before+1 and views[3]==same_world_view,"same bus world must not duplicate registration")
assert(writes==0 and http==0)
raw_print(encode({status="PASS_REAL_DAILY_WIRE_SYNTHETIC_NOT_NATIVE",players=4,
    original_full_json_bytes=full_json_bytes,initial_wire_packets=initial_packets,initial_callbacks=initial_batches,
    max_utf8_fragment_bytes=max_fragment,max_packet_json_bytes=max_packet_json,
    max_flat_keyvalues_estimate_bytes=max_kv_estimate,native_size_measured=false,
    stable=stable,minute_delta_packets=minute_packets,minute_delta_json_bytes=minute_json,
    close_hint_day_reset=true,partial_failure_recovery=true,reused_player_reset_disconnect_isolated=true,
    compact_v3_shared_dispatcher=true,compact_v3_closed_hint_only=true,compact_v3_ready_and_intent_gate=true,
    compact_v3_real_bus_world_reset=true,compact_v3_old_callbacks_rejected=true,
    native_calls=0,http_calls=http,persistence_calls=writes}))
