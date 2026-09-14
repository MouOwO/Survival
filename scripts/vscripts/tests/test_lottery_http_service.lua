package.path='scripts/vscripts/?.lua;'..package.path
local handlers,subscribers,packets={},{},{}
local calls,requests=0,{}
local snapshots={{selected_pool_id='map',tickets=3,pools={},items={}}}
package.loaded['core/event_bus']={handle_request=function(k,f)handlers[k]=f end,subscribe=function(k,f)subscribers[k]=f end,emit=function(k,p)packets[#packets+1]=p end}
local events=require('core/events')
local pending_http
package.loaded['systems/player_profile_service']={get_provider=function()return {
    resolve_account_id=function()return '123' end,
    lottery_snapshot=function(payload,done)calls=calls+1;pending_http=done end,
}end}
local command_done
package.loaded['systems/archive_http_adapter']={submit=function(id,command,done)requests[#requests+1]=command;command_done=done end}
require('systems/lottery_http_service').init()
subscribers[events.PLAYER_PROFILE_CHANGED]({player_id=0})
assert(calls==1);pending_http({ok=true,snapshots=snapshots})
assert(packets[1].snapshot.snapshot_scope=='cache')
local result=handlers[events.LOTTERY_SNAPSHOT_REQUEST]({player_id=0,pool_id='map'})
assert(result.ok and result.snapshot.tickets==3 and calls==1,'cached tab must not fetch HTTP')
local completed
result=handlers[events.LOTTERY_DRAW_REQUEST]({player_id=0,pool_id='map',count=1,request_id='draw_1',complete=function(r)completed=r end})
assert(result.pending and not completed and #requests==1)
assert(requests[1].kind=='lottery_draw' and requests[1].results==nil)
command_done({ok=true,response={ok=true,results={{id='reward'}}}})
assert(not completed,'wait for authoritative updated view')
pending_http({ok=true,snapshots={{selected_pool_id='map',tickets=2,pools={},items={}}}})
assert(completed.ok and completed.snapshot.tickets==2)
assert(packets[#packets].snapshot.snapshot_scope=='cache_patch')
assert(packets[#packets].snapshot.changes[1].path[1]=='tickets')
print('LOTTERY_HTTP_TRANSPORT_PASS: preload, cached tabs, asynchronous authority, incremental patches')
