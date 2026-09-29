package.path='scripts/vscripts/?.lua;'..package.path
local handlers,sent,requests={},{},{}
local loaded=true
local refreshed=0
local profile={save={content_inventory={}}}
local provider={resolve_account_id=function(id)return id==0 and '123' or '456' end}
package.loaded['systems/player_profile_service']={get_provider=function()return provider end,
 get_profile=function()return loaded and profile or nil end,
 load_player=function(id,reason,done)refreshed=refreshed+1;done();return {ok=true} end}
package.loaded['systems/match_setup_service']={get_session_id=function()return 'safe_session' end}
PlayerResource={IsValidPlayerID=function(_,id)return id==0 or id==1 end,IsFakeClient=function()return false end,
 GetPlayer=function(_,id)return {id=id} end}
CustomGameEventManager={RegisterListener=function(_,name,f)handlers[name]=f end,
 Send_ServerToPlayer=function(_,player,name,body)sent[#sent+1]=body end}
Convars={GetStr=function()return 'server_only_test_token' end}
local clock=0
Time=function()clock=clock+2;return clock end
CreateHTTPRequestScriptVM=function(method,url)
 local r={method=method,url=url};requests[#requests+1]=r
 function r:SetHTTPRequestHeaderValue(name,value)r.header=value end
 function r:SetHTTPRequestRawPostBody(kind,body)r.body=body end
 function r:Send(done)r.done=done end
 return r
end
local service=require('systems/payment_service');service.init();service.init()
local handle=handlers.survival_payment_request
handle(0,{PlayerID=0,action='create',account_id='attacker',amount=1})
local body=require('core/json_decoder').decode(requests[1].body)
assert(body.account_id=='123' and body.amount==nil and body.match_session_id=='safe_session')
handle(0,{PlayerID=0,action='create'});assert(#requests==1,'in-flight duplicate blocked')
requests[1].done({StatusCode=200,Body='{"ok":true,"order_id":"WX111111111111111111111111111111","state":"pending"}'})
handle(0,{PlayerID=0,action='status',order_id='other_player_order'})
body=require('core/json_decoder').decode(requests[2].body)
assert(body.order_id=='WX111111111111111111111111111111')
requests[2].done({StatusCode=200,Body='{"ok":true,"order_id":"WX111111111111111111111111111111","state":"delivered"}'})
assert(refreshed==1)
handle(0,{PlayerID=0,action='status'})
requests[3].done({StatusCode=200,Body='{"ok":true,"order_id":"WX111111111111111111111111111111","state":"delivered"}'})
assert(refreshed==1,'duplicate success must not grant or repeatedly reload')
loaded=false;handle(0,{PlayerID=0,action='create'});assert(#requests==3)
print('PAYMENT_GAME_SERVICE_PASS: trusted identity, fixed fields, duplicate requests, authoritative refresh')
