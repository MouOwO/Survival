package.path='scripts/vscripts/?.lua;'..package.path
local handlers,subscribers,packets,timers={},{},{},{}
local catalogs,privates,commands={},{},{}
local hash1,hash2=string.rep('a',64),string.rep('b',64)
local md51,md52=string.rep('c',32),string.rep('d',32)
local match_session='catalog_room_A'
package.loaded['config/generated/archive_http_bundle']={hash=hash1}
package.loaded['config/generated/lottery_catalog_manifest']={config_hash=hash1,catalog_md5=md51}
package.loaded['core/event_bus']={handle_request=function(k,f)handlers[k]=f end,subscribe=function(k,f)subscribers[k]=f end,
    emit=function(k,p)packets[#packets+1]={event=k,payload=p}end}
package.loaded['core/scheduler']={every=function(_,f,key)timers[key]=f end,after=function(_,f,key)timers[key]=f end}
package.loaded['systems/match_setup_service']={get_session_id=function()return match_session end,get_mode=function()return 'standard' end}
local provider={resolve_account_id=function()return '123' end,
    lottery_catalog=function(payload,done)catalogs[#catalogs+1]={payload=payload,done=done}end,
    lottery_snapshot=function(payload,done)privates[#privates+1]={payload=payload,done=done}end}
package.loaded['systems/player_profile_service']={get_provider=function()return provider end}
package.loaded['systems/archive_http_adapter']={submit=function(id,command,done,hash)
    commands[#commands+1]={done=done,hash=hash,command=command}
end}
local events=require('core/events')
local service=require('systems/lottery_http_service');service.init()
assert(#catalogs==1 and catalogs[1].payload.md5==md51,'first poll validates the installed manifest without requesting 82KB')
catalogs[1].done({ok=true,unchanged=true,catalog_md5=md51,config_hash=hash1})
assert(packets[1].payload.catalog.unchanged and not packets[1].payload.catalog.catalog_json)
assert(packets[1].payload.catalog.catalog_sequence==1 and packets[1].payload.catalog.session_id==match_session)
local same,different
handlers[events.LOTTERY_CATALOG_REQUEST]({md5=md51,complete=function(r)same=r end})
assert(same.unchanged and not same.catalog_json and #catalogs==1,'same-seed client needs neither HTTP body nor chunks')
handlers[events.LOTTERY_CATALOG_REQUEST]({md5='older_seed',complete=function(r)different=r end})
assert(not different and #catalogs==2 and catalogs[2].payload.md5=='','different seed forces one complete catalog')
catalogs[2].done({ok=true,unchanged=false,catalog_md5=md51,config_hash=hash1,catalog_json='{"schema":1,"snapshots":[]}'})
assert(different.catalog_json and not different.unchanged and different.catalog_sequence==1)
assert(different.session_id==match_session)
local legacy=handlers[events.LOTTERY_DRAW_REQUEST]({player_id=0,pool_id='map',count=1,request_id='legacy_before_update'})
assert(legacy.pending and #commands==1,'unchanged initial catalog preserves legacy no-token clients')
commands[1].done({ok=false,error='lottery_ticket_insufficient',terminal=true})
assert(#privates==1)
privates[1].done({ok=true,config_hash=hash1,snapshots={{selected_pool_id='map',items={},pools={}}}})
timers.lottery_catalog_poll()
catalogs[3].done({ok=true,catalog_md5=md52,config_hash=hash2,catalog_json='{"schema":1,"snapshots":[]} '})
local latest=packets[#packets].payload.catalog
assert(latest.catalog_sequence==2 and latest.session_id==match_session)
for _,expected in ipairs({'',hash1}) do
    local draw=handlers[events.LOTTERY_DRAW_REQUEST]({player_id=0,pool_id='map',count=1,request_id='obsolete_draw',expected_config_hash=expected})
    local exchange=handlers[events.LOTTERY_EXCHANGE_REQUEST]({player_id=0,pool_id='map',item_id='one',request_id='obsolete_exchange',expected_config_hash=expected})
    assert(draw.error=='lottery_config_refresh_required' and exchange.error=='lottery_config_refresh_required')
end
assert(#commands==1,'old or missing version tokens cannot be charged using a new catalog')
local draw=handlers[events.LOTTERY_DRAW_REQUEST]({player_id=0,pool_id='map',count=1,request_id='new_draw',expected_config_hash=hash2})
assert(draw.pending and #commands==2 and commands[2].hash==hash2)
-- Start one old-room catalog check, then join a new room before it completes.
timers.lottery_catalog_poll();assert(#catalogs==4)
match_session='catalog_room_B'
local next_room
handlers[events.LOTTERY_CATALOG_REQUEST]({md5=md51,complete=function(r)next_room=r end})
assert(#catalogs==5 and catalogs[5].payload.md5==md51)
local count=#packets
catalogs[4].done({ok=true,catalog_md5=md52,config_hash=hash2,catalog_json='old room response'})
assert(#packets==count and not next_room,'old-room callback cannot publish into or finish new-room waiters')
catalogs[5].done({ok=true,unchanged=true,catalog_md5=md51,config_hash=hash1})
assert(next_room.unchanged and next_room.catalog_sequence==1 and next_room.session_id=='catalog_room_B')
assert(service.active_config_hash()==hash1,'a new room independently validates its own catalog')
print('LOTTERY_MANIFEST_CACHE_PASS: conditional-first-poll/body-on-demand/old-price-rejection/room-scope/late-reply-isolation')
