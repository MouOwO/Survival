package.path='scripts/vscripts/?.lua;'..package.path
local handlers,subscribers,packets,timers={},{},{},{}
local catalog_calls,private_calls,commands={},{},{}
local mode,account='standard','123'
local hash1,hash2=string.rep('a',64),string.rep('b',64)
local md51,md52=string.rep('c',32),string.rep('d',32)
local provider={resolve_account_id=function(id)return id==0 and account or '456' end}
provider.lottery_catalog=function(payload,done) catalog_calls[#catalog_calls+1]={payload=payload,done=done} end
provider.lottery_snapshot=function(payload,done) private_calls[#private_calls+1]={payload=payload,done=done} end
package.loaded['core/event_bus']={handle_request=function(k,f)handlers[k]=f end,
    subscribe=function(k,f)subscribers[k]=f end,emit=function(k,p)packets[#packets+1]={event=k,payload=p}end}
package.loaded['core/scheduler']={every=function(_,f,key)timers[key]=f end,after=function(_,f,key)timers[key]=f end}
package.loaded['systems/player_profile_service']={get_provider=function()return provider end}
package.loaded['systems/match_setup_service']={get_session_id=function()return 'catalog_session' end,get_mode=function()return mode end}
package.loaded['systems/archive_http_adapter']={submit=function(id,command,done,hash)
    commands[#commands+1]={id=id,command=command,done=done,hash=hash}
end}
local events=require('core/events')
local service=require('systems/lottery_http_service')
service.init()
assert(#catalog_calls==1 and timers.lottery_catalog_poll,'catalog sync starts independently of a UI view')
catalog_calls[1].done({ok=true,catalog_md5=md51,config_hash=hash1,catalog_json='{"schema":1,"snapshots":[]}'})
assert(service.active_config_hash()==hash1)
assert(packets[1].event==events.LOTTERY_CATALOG_CHANGED and packets[1].payload.catalog.catalog_sequence==1)
local reply
handlers[events.LOTTERY_CATALOG_REQUEST]({md5=md51,complete=function(result)reply=result end})
assert(reply.unchanged and not reply.catalog_json and reply.catalog_sequence==1 and #catalog_calls==1)
handlers[events.LOTTERY_CATALOG_REQUEST]({md5='',complete=function(result)reply=result end})
assert(not reply.unchanged and reply.catalog_json and #catalog_calls==1,'late clients use the validated local catalog')
local function snapshot(tickets)
    local pool={id='map',revision='r1',tickets=tickets,update_unread=true,notice_unread=true}
    return {selected_pool_id='map',selected_pool=pool,pools={pool},items={},tickets=tickets}
end
subscribers[events.PLAYER_PROFILE_CHANGED]({player_id=0})
subscribers[events.PLAYER_PROFILE_CHANGED]({player_id=1})
assert(#private_calls==2 and private_calls[1].payload.config_hash==hash1)
private_calls[1].done({ok=true,config_hash=hash1,snapshots={snapshot(5)}})
private_calls[2].done({ok=true,config_hash=hash1,snapshots={snapshot(8)}})
local last=packets[#packets].payload.snapshot
assert(last.account_id=='456' and last.session_id=='catalog_session' and last.profile_mode=='standard')
assert(last.catalog_md5==md51 and last.config_hash==hash1)
local result=handlers[events.LOTTERY_SNAPSHOT_REQUEST]({player_id=0,pool_id='map'})
assert(result.snapshot.tickets==5 and #private_calls==2)

-- Read receipts retain authoritative writes but do not read the full catalog/profile again.
local completed
handlers[events.LOTTERY_READ_ACK_REQUEST]({player_id=0,pool_id='map',read_action='details',revision='r1',
    complete=function(value)completed=value end})
assert(commands[1].hash==hash1 and commands[1].command.kind=='lottery_read')
subscribers[events.PLAYER_PROFILE_CHANGED]({player_id=0,reason='archive_lottery_read'})
commands[1].done({ok=true,response={ok=true}})
assert(#private_calls==2 and completed.ok and not completed.snapshot.selected_pool.update_unread)
assert(completed.snapshot.selected_pool.notice_unread,'details receipt must not mark notices read')

-- Polls with matching MD5 transfer no catalog and do not republish/reload player data.
local before=#packets
timers.lottery_catalog_poll()
assert(catalog_calls[2].payload.md5==md51)
catalog_calls[2].done({ok=true,unchanged=true,catalog_md5=md51,config_hash=hash1})
assert(#packets==before and #private_calls==2)
-- A bad remote response never changes the trusted transaction hash.
timers.lottery_catalog_poll()
catalog_calls[3].done({ok=true,catalog_md5=md52,config_hash='client supplied',catalog_json='{}'})
assert(service.active_config_hash()==hash1 and #private_calls==2)

-- New content broadcasts once and refreshes both private projections with its trusted hash.
timers.lottery_catalog_poll()
catalog_calls[4].done({ok=true,catalog_md5=md52,config_hash=hash2,catalog_json='{"schema":1,"snapshots":[]} '})
assert(service.active_config_hash()==hash2 and #private_calls==4)
assert(packets[#packets].payload.catalog.catalog_sequence==2)
assert(private_calls[3].payload.config_hash==hash2 and private_calls[4].payload.config_hash==hash2)
private_calls[3].done({ok=true,config_hash=hash2,snapshots={snapshot(6)}})
private_calls[4].done({ok=true,config_hash=hash2,snapshots={snapshot(9)}})
assert(packets[#packets].payload.snapshot.config_hash==hash2 and packets[#packets].payload.snapshot.snapshot_scope=='cache')
handlers[events.LOTTERY_DRAW_REQUEST]({player_id=0,pool_id='map',count=1,request_id='trusted_draw',expected_config_hash=hash2})
assert(commands[2].hash==hash2,'draw hash comes from the authenticated catalog, not the UI')

-- Replies for a previous account must never be published to a reused player slot.
local previous=#packets
account='789'
commands[2].done({ok=true,response={ok=true}})
assert(#packets==previous)
print('LOTTERY_CATALOG_SYNC_PASS: startup/MD5/no-view-fetch/private-stamps/read-ack/hot-update/hash-gate/account-isolation')
