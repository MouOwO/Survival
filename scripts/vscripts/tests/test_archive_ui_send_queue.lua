-- Real archive page projectors and indexed dispatcher. Synthetic accounts only.
package.path="scripts/vscripts/?.lua;"..package.path
local raw_print=print;print=function() end
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for key,child in pairs(value) do out[key]=copy(child) end;return out
end
local encoder=require("core/json_encoder")
local encode,encodes=encoder.encode,0
encoder.encode=function(value) encodes=encodes+1;return encode(value) end
local timers,listeners,packets,profiles,players={},{},{},{},{}
local game_time,wall_ms,profile_reads,page_builds,writes,http=0,0,0,0,0,0
local budget_mode,fail_chunk,reenter=false,false,nil
local provider={archive_enabled=function() return false end}
package.loaded["core/test_access_policy"]={enabled=function() return false end,allowed=function() return true end,enforce=function() return true end}
package.loaded["core/scheduler"]={every=function(_,fn,key) timers[key]=fn end,
    after=function(_,fn,key) timers[key]=fn end,cancel=function(key) timers[key]=nil end}
package.loaded["systems/player_profile_service"]={
    get_account_profile=function(id) profile_reads=profile_reads+1;return copy(profiles[id]) end,
    get_profile=function(id) profile_reads=profile_reads+1;return copy(profiles[id]) end,
    get_provider=function() return provider end,
    update_save_sections=function() writes=writes+1;error("unexpected persistence") end}
package.loaded["systems/archive_http_adapter"]={enabled=function() return false end}
package.loaded["debug/mode_unlock_test"]={is_enabled=function() return true end}
package.loaded["debug/offline_logic_test"]={is_enabled=function() return true end,is_provider=function(value) return value==provider end}
package.loaded["systems/match_setup_service"]={get_mode=function() return "standard" end,
    get_profile_mode=function() return "standard" end,get_session_id=function() return "synthetic_archive_queue" end,
    is_mode_selected=function() return true end}
GameRules={GetGameTime=function() return game_time end,IsCheatMode=function() return false end}
GetSystemTimeMS=function() return wall_ms end
IsInToolsMode=function() return false end
IsServer=function() return true end
IsClient=function() return false end
RandomInt=function(low) return low end
CreateHTTPRequestScriptVM=function() http=http+1;error("unexpected HTTP") end
PlayerResource={GetPlayer=function(_,id) return players[id] end,
    IsValidPlayerID=function(_,id) return profiles[id]~=nil end,GetConnectionState=function() return 2 end}
CustomNetTables={SetTableValue=function() end}
CustomGameEventManager={RegisterListener=function(_,name,fn) listeners[name]=fn end,
    Send_ServerToPlayer=function(_,player,name,data)
        if name~="survival_archive_snapshot" then return end
        if fail_chunk and data.category_id=="clear" and data.chunk==2 then error("synthetic native failure") end
        packets[#packets+1]={player=player,data=copy(data)}
        if budget_mode then wall_ms=wall_ms+3 end
        if reenter then local fn=reenter;reenter=nil;fn() end
    end}
local bus,events=require("core/event_bus"),require("core/events")
local quota=require("systems/archive_daily_limits")
local real_quota=quota.snapshot
quota.snapshot=function(...)
    page_builds=page_builds+1
    if budget_mode then wall_ms=wall_ms+3 end
    return real_quota(...)
end
local archive
local function reset()
    bus.reset();timers,listeners,packets,profiles,players={},{},{},{},{}
    game_time,wall_ms,budget_mode,fail_chunk,reenter=0,0,false,false,nil
    for id=0,3 do
        players[id]={id=id}
        profiles[id]={account_id="synthetic_"..id,revision=1,entitlements={},save={gameplay_stats={},content_inventory={},archive={}}}
        for _,row in ipairs(require("config/generated/player_gameplay_stats").rows) do
            if row.enabled~=false then profiles[id].save.gameplay_stats[row.field_id]=tonumber(row.default_value) or 0 end
        end
    end
    package.loaded["systems/archive_service"]=nil
    archive=require("systems/archive_service");archive.set_clock(function() return 1800000000 end);archive.init()
    profile_reads,page_builds,encodes,writes,http=0,0,0,0,0
end
local callbacks,max_sends,max_builds=0,0,0
local function step()
    local fn=timers.archive_ui_queue
    if not fn then return false end
    timers.archive_ui_queue=nil
    local before,before_builds=#packets,page_builds
    game_time=game_time+0.05;fn();callbacks=callbacks+1
    local sends,builds=#packets-before,page_builds-before_builds
    max_sends,max_builds=math.max(max_sends,sends),math.max(max_builds,builds)
    assert(sends<=2 and builds<=2,"global callback exceeded bounded work")
    return true
end
local function pump() local count=0;while step() do count=count+1;assert(count<2000) end;return count end
local function request(id,category,prefetch,resync)
    listeners.survival_archive_request(nil,{PlayerID=id,category_id=category,prefetch=prefetch or 0,resync=resync})
end
local function changed(id) bus.emit(events.PLAYER_PROFILE_CHANGED,{player_id=id,reason="synthetic_queue_change"}) end
local function clear_counts() packets={};profile_reads,page_builds,encodes=0,0,0 end

reset();request(0,"endless",1)
assert(page_builds==0 and #packets==0,"request must not synchronously project 945 rows")
step();assert(packets[1].data.category_id=="endless","requested page is first")
local first_sequence=packets[1].data.sequence
for _=1,12 do game_time=game_time+0.2;request(0,"endless",1) end
assert(page_builds<=2 and profile_reads==1,"same-source prefetch must not copy/profile/project again")
pump()
local initial_count,rows,seen=0,0,{}
for _,packet in ipairs(packets) do
    initial_count=initial_count+1;rows=rows+#packet.data.rows;seen[packet.data.category_id]=true
    if packet.data.category_id=="endless" then assert(packet.data.sequence==first_sequence,"retry restarted the same full page") end
end
local categories=0;for _ in pairs(seen) do categories=categories+1 end
assert(initial_count==108 and rows==945 and categories==20,"bounded queue retains complete current catalogue")
clear_counts();for _=1,12 do game_time=game_time+0.2;request(0,"endless",1) end
assert(not timers.archive_ui_queue and #packets==0 and page_builds==0 and encodes==0 and profile_reads==0,
    "completed same-source prefetch must be O(1), without rebuilding/replaying all pages")

-- Fast real selections bypass the duplicate throttle and move the final page
-- in O(1), including a page whose rows are already queued in the background.
reset();request(0,"clear",1);request(0,"points");request(0,"titles")
step();assert(packets[1].data.category_id=="titles","last quick category selection was lost")
pump();clear_counts();game_time=game_time+0.2;request(0,"clear",0,1);pump()
for _,packet in ipairs(packets) do assert(packet.data.category_id=="clear" and packet.data.delta==nil) end
assert(#packets>0,"explicit missing-baseline recovery must replay only requested full page")

-- A changed source cancels an incomplete full page. Its new version cannot
-- be a delta against the abandoned half, but completed pages retain baselines.
reset();request(0,"clear",1);step()
local partial=packets[1].data.sequence
profiles[0].save.content_inventory.commerce_p026=1;profiles[0].revision=2
changed(0);clear_counts();game_time=game_time+0.2;request(0,"clear");pump()
local fresh=false
for _,packet in ipairs(packets) do if packet.data.category_id=="clear" then
    assert(packet.data.sequence~=partial and packet.data.delta==nil);fresh=true
end end
assert(fresh)

-- One synchronous send may reenter a profile update. Do not commit the now
-- cancelled document after the native call returns.
reset();request(0,"clear",1)
reenter=function() profiles[0].revision=2;changed(0) end
step();clear_counts();game_time=game_time+0.2;request(0,"clear");pump()
for _,packet in ipairs(packets) do if packet.data.category_id=="clear" then assert(packet.data.delta==nil) end end

reset();request(0,"clear",1);fail_chunk=true;pump()
fail_chunk=false;clear_counts();changed(0);pump()
for _,packet in ipairs(packets) do assert(packet.data.category_id=="clear" and packet.data.delta==nil) end
assert(#packets>0,"failed page did not remain retryable")

-- The engine wall clock, rather than GameTime, gates between cooperative work
-- units. A synthetic slow projector defers sending until the next callback.
reset();budget_mode=true;request(0,"clear",1)
step();assert(page_builds==1 and #packets==0)
step();assert(#packets==1,"3ms native operation should stop before a second send")
budget_mode=false;pump()

reset();for id=0,3 do request(id,"clear",1) end
pump();local counts={}
for _,packet in ipairs(packets) do counts[packet.player.id]=(counts[packet.player.id] or 0)+1 end
for id=0,3 do assert(counts[id]==108,"four-player queue lost or cross-sent a private page") end
clear_counts();game_time=game_time+0.2;request(0,"clear",0,1)
local old=timers.archive_ui_queue;bus.emit(events.PLAYER_DISCONNECTED,{player_id=0});pump()
assert(#packets==0,"disconnect must cancel queued private pages")
request(1,"clear",0,1);old=timers.archive_ui_queue
bus.reset();archive.init();clear_counts();old();assert(#packets==0 and not timers.archive_ui_queue,"old generation callback survived reset")
assert(writes==0 and http==0)
raw_print(encode({status="PASS_REAL_ARCHIVE_INDEXED_QUEUE_SYNTHETIC_NOT_NATIVE",initial_packets=initial_count,
    initial_rows=rows,categories=categories,max_packets_per_callback=max_sends,max_page_builds_per_callback=max_builds,
    same_source_prefetch_reads=0,same_source_prefetch_projections=0,same_source_prefetch_encodes=0,
    selected_priority=true,explicit_single_page_resync=true,partial_reentrant_failure_base_safe=true,
    real_clock_gate_simulated=true,four_player_reset_disconnect_safe=true,native_calls=0,http_calls=http,persistence_calls=writes}))
