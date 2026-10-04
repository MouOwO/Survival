package.path='scripts/vscripts/?.lua;'..package.path
local sent,submitted,handlers={},{},{}
local done;local account='123';local clock=10
local provider={resolve_account_id=function()return account end,archive_enabled=function()return true end}
provider.archive_submit=function(body,callback)submitted[#submitted+1]=body;done=callback end
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,get_profile=function()return {} end}
package.loaded['systems/match_setup_service']={get_session_id=function()return 'test_session' end}
package.loaded['systems/archive_http_adapter']={enabled=function()return true end,submit=function(id,command,callback)
    submitted[#submitted+1]=command;done=callback
end}
package.loaded['core/scheduler']={after=function(_,f)f()end}
package.loaded['systems/commerce_runtime']={init=function()end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 end,IsFakeClient=function()return false end,GetPlayer=function()return {} end}
CustomGameEventManager={RegisterListener=function(_,name,f)handlers[name]=f end,Send_ServerToPlayer=function(_,p,name,result)sent[#sent+1]=result end}
Time=function()return clock end
local service=require('systems/commerce_service');service.init()
service.handle({PlayerID=0,action='catalog',request_id='catalog_001',account_id='attacker'})
assert(submitted[1].account_id=='123')
done({ok=true,products={{sku='video_p004'},{sku='video_p033'}},balances={u_coin=0}})
assert(#sent==4 and sent[1].part=='begin' and sent[4].part=='end')
clock=12
service.handle({PlayerID=0,action='purchase',request_id='purchase_001',sku='video_p004',price=0,balance=999999})
assert(submitted[2].price==nil and submitted[2].balance==nil and submitted[2].sku=='video_p004')
service.handle({PlayerID=0,action='purchase',request_id='purchase_001',sku='video_p004'})
assert(#submitted==2 and sent[#sent].terminal==false,'busy must not terminate uncertain purchase')
account='456';done({ok=true,done=true,response={title='private'}})
assert(sent[#sent].error=='commerce_busy','do not send old account response after identity change')
print('COMMERCE_GAME_SERVICE_PASS: identity, fields, chunking, busy semantics and account switch')
