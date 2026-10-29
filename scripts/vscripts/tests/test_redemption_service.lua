package.path='scripts/vscripts/?.lua;'..package.path
local sent,submitted,tasks={},{},{}
local clock,account,session,complete=10,'123','redeem_test_session',nil
local provider={resolve_account_id=function()return account end}
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,get_profile=function()return {}end}
package.loaded['systems/match_setup_service']={get_session_id=function()return session end}
package.loaded['systems/archive_http_adapter']={enabled=function()return true end,submit=function(id,c,done)
 submitted[#submitted+1]=c;complete=done;return true
end}
package.loaded['core/scheduler']={after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end}
package.loaded['systems/commerce_runtime']={init=function()end}
package.loaded['systems/commerce_titan_aura_service']={init=function()end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,IsFakeClient=function()return false end,GetPlayer=function()return {}end}
CustomGameEventManager={RegisterListener=function()end,Send_ServerToPlayer=function(_,_,_,value)sent[#sent+1]=value end}
Time=function()return clock end
local service=require('systems/commerce_service');service.init()
service.handle({PlayerID=0,action='redeem',code='TEST-CODE',request_id='redeem_request_01',rewards={vip=999},account_id='attacker'})
local command=submitted[1]
assert(command.kind=='redemption_redeem' and command.id=='redeem:redeem_request_01')
assert(command.code=='TEST-CODE' and command.rewards==nil and command.account_id==nil)
service.handle({PlayerID=0,action='redeem',code='TEST-CODE',request_id='redeem_request_01'})
assert(#submitted==1 and sent[#sent].error=='commerce_busy')
complete({ok=false,error='database_unavailable'})
assert(tasks['commerce_retry_0']);tasks['commerce_retry_0']()
assert(submitted[2].request_id==command.request_id,'lost replies must reuse the request id')
complete({ok=true,done=true,response={title='test',granted=1,skipped=0}})
assert(sent[#sent].ok and sent[#sent].action=='redeem' and sent[#sent].granted==1)
clock=20
service.handle({PlayerID=0,action='redeem',code='TEST-CODE',request_id='redeem_request_02'})
session='other_session';complete({ok=true,done=true,response={title='private'}})
assert(sent[#sent].request_id=='redeem_request_01','stale session result must not be sent')
print('REDEMPTION_GAME_SERVICE_PASS: trusted fields, busy, same-request retry, private result and session isolation')
