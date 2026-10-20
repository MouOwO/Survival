package.path='scripts/vscripts/?.lua;'..package.path
local handlers,subscribers,packets={},{},{}
local reads,commands={},{},{}
local hash=string.rep('a',64)
package.loaded['config/generated/archive_http_bundle']={hash=hash}
package.loaded['config/generated/lottery_catalog_manifest']={}
package.loaded['core/event_bus']={handle_request=function(k,f)handlers[k]=f end,subscribe=function(k,f)subscribers[k]=f end,
    emit=function(k,p)packets[#packets+1]={event=k,payload=p}end}
package.loaded['systems/match_setup_service']={get_session_id=function()return 'receipt_session' end,get_mode=function()return 'standard' end}
package.loaded['systems/player_profile_service']={get_provider=function()return {
    resolve_account_id=function()return '123' end,
    lottery_snapshot=function(payload,done,failed)reads[#reads+1]={done=done,failed=failed}end,
}end}
package.loaded['systems/archive_http_adapter']={submit=function(id,command,done)commands[#commands+1]={done=done}end}
local events=require('core/events')
require('systems/lottery_http_service').init()
local function snapshot(tickets,owned)
    return {selected_pool_id='map',tickets=tickets,selected_pool={id='map',revision='r1'},
        pools={{id='map',revision='r1'}},items={{id='one',owned_count=owned}}}
end
subscribers[events.PLAYER_PROFILE_CHANGED]({player_id=0})
reads[1].done({ok=true,config_hash=hash,snapshots={snapshot(5,0)}})
local first=packets[#packets].payload.snapshot
local delayed_receipt
handlers[events.LOTTERY_DRAW_REQUEST]({player_id=0,pool_id='map',count=1,request_id='draw_one',
    expected_config_hash=hash,complete=function(result)delayed_receipt=result end})
commands[1].done({ok=true,response={ok=true}})
reads[2].done({ok=true,config_hash=hash,snapshots={snapshot(4,1)}})
assert(delayed_receipt.snapshot.cache_sequence>first.cache_sequence)
local receipt_sequence=delayed_receipt.snapshot.cache_sequence
subscribers[events.PLAYER_PROFILE_CHANGED]({player_id=0,reason='independent_purchase'})
reads[3].done({ok=true,config_hash=hash,snapshots={snapshot(9,2)}})
local newer_push=packets[#packets].payload.snapshot
assert(newer_push.cache_sequence>receipt_sequence,'later authoritative push has a greater pool sequence')
assert(delayed_receipt.snapshot.tickets==4 and delayed_receipt.snapshot.items[1].owned_count==1,
    'the delayed receipt retains its original data and matching original sequence')
local main=handlers[events.LOTTERY_SNAPSHOT_REQUEST]({player_id=0,pool_id='map'}).snapshot
assert(main.cache_sequence==newer_push.cache_sequence and main.tickets==9 and main.items[1].owned_count==2)
for _,change in ipairs(newer_push.changes or {}) do
    assert(change.path[1]~='cache_sequence','transport versions must not become data diff fields')
end
main.cache_sequence=0
assert(handlers[events.LOTTERY_SNAPSHOT_REQUEST]({player_id=0,pool_id='map'}).snapshot.cache_sequence==newer_push.cache_sequence,
    'transport view is a copy and cannot corrupt the internal pool version')

handlers[events.LOTTERY_DRAW_REQUEST]({player_id=0,pool_id='map',count=1,request_id='draw_busy',expected_config_hash=hash})
local failed_read=handlers[events.LOTTERY_READ_ACK_REQUEST]({player_id=0,pool_id='map',read_action='details',revision='r1'})
assert(not failed_read.ok and failed_read.error=='lottery_player_busy')
assert(failed_read.snapshot.account_id=='123' and failed_read.snapshot.session_id=='receipt_session'
    and failed_read.snapshot.profile_mode=='standard' and failed_read.snapshot.config_hash==hash)
assert(failed_read.snapshot.cache_sequence==newer_push.cache_sequence and failed_read.snapshot.selected_pool_id=='map')
assert(failed_read.snapshot.tickets==nil,'failed read carries identity/version metadata without presenting cached balances')
print('LOTTERY_RECEIPT_SEQUENCE_PASS: delayed-v2-receipt/newer-v3-push/versioned-main/clean-diff-base/read-failure-identity')
