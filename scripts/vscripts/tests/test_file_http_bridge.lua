package.path="scripts/vscripts/?.lua;"..package.path
local checks,commands,output,execs,now,think,scheduled_delay=0,{},{},{},1,nil,nil
local function check(value,message) checks=checks+1;assert(value,message) end
local world={SetContextThink=function(_,name,callback,delay) think=callback;scheduled_delay=delay end}
GameRules={GetGameModeEntity=function() return world end}
IsServer=function() return true end
IsInToolsMode=function() return false end
IsDedicatedServer=function() return false end
GetMapName=function() return 'template_map' end
Time=function() return now end
DoUniqueString=function() return 'sfb_1' end
DisconnectClient=function() end
PlayerResource={GetSteamAccountID=function() return 1 end}
Convars={RegisterCommand=function(_,name,callback) commands[name]=callback end,GetCommandClient=function() return nil end}
SendToServerConsole=function(value) execs[#execs+1]=value end
local original_print=print
print=function(value) if value:sub(1,7)=='[SFB1] ' then output[#output+1]=value end end
package.loaded['config/release_profile']={channel='production'}
package.loaded['config/player_web_auth']={enabled=true}
local bridge=require('core/file_http_bridge')
local base='https://pay.xiaofengnet.com/ws4-web'
check(#execs==0 and not think,'import is idle')
check(not bridge.create('GET',base..'/health?x=1'),'query rejected')
check(not bridge.create('GET',base..'.evil/health'),'host suffix rejected')
check(not bridge.create('POST',base..'/v1/../admin'),'path traversal rejected')
IsInToolsMode=function() return true end
check(not bridge.create('GET',base..'/health'),'Tools rejected')
IsInToolsMode=function() return false end
local request=assert(bridge.create('GET',base..'/health'))
local results={}
check(request:Send(function(value) results[#results+1]=value end),'Send accepted')
check(#execs==1 and scheduled_delay==0.2,'handshake starts synchronously before positive-delay think')
check(not request:Send(function() end),'Send not retried')
check(think()==0.2 and #execs==1,'one bootstrap while waiting')
local nonce=string.rep('a',32)
commands.survival_sfb_begin('survival_sfb_begin',nonce,'1')
think()
check(#output==2,'ready and one request emitted')
commands.survival_sfb_reply('survival_sfb_reply',string.rep('b',32),'sfb_1','1','1','200','2','1','1')
think()
check(execs[#execs]:find('cursor.cfg',1,true),'wrong nonce ignored')
commands.survival_sfb_reply('survival_sfb_reply',nonce,'sfb_1','1','1','200','2','1','1')
think()
check(execs[#execs]:find('b_'..nonce..'_sfb_1_1_1.cfg',1,true),'bounded block requested')
commands.survival_sfb_chunk('survival_sfb_chunk',nonce,'sfb_1','1','1','T0s=')
commands.survival_sfb_block('survival_sfb_block',nonce,'sfb_1','1','1')
check(#results==1 and results[1].StatusCode==200 and results[1].Body=='OK','exact bytes returned')
commands.survival_sfb_block('survival_sfb_block',nonce,'sfb_1','1','1')
check(#results==1 and think()==nil,'callback once; idle think stops')
local bad=assert(bridge.create('POST',base..'/v1/profile'))
check(not bad:SetHTTPRequestRawPostBody('text/plain','x'),'wrong content type rejected')
check(not bad:Send(function() error('never') end),'invalid setter prevents Send')
local timeout=assert(bridge.create('GET',base..'/health'))
timeout:SetHTTPRequestAbsoluteTimeoutMS(100)
timeout:Send(function(value) results[#results+1]=value end)
now=2;think()
check(#results==2 and results[2].StatusCode==0,'deadline terminates once')
CreateHTTPRequestScriptVM=function() return nil end
CreateHTTPRequest=function() return nil end
local large,outcome=require('core/http_request_factory').create('GET',base..'/health')
check(large and outcome=='nn','factory returns helper only after both native creation failures')
large:Send(function(value) results[#results+1]=value end)
think()
commands.survival_sfb_reply('survival_sfb_reply',nonce,'sfb_1','2','3','200','12288','64','4')
for block=1,4 do
    local before=#execs
    think()
    check(#execs==before+1,'one native exec per incoming block think')
    for index=(block-1)*16+1,block*16 do
        commands.survival_sfb_chunk('survival_sfb_chunk',nonce,'sfb_1','2',tostring(index),string.rep('QUJD',64))
    end
    commands.survival_sfb_block('survival_sfb_block',nonce,'sfb_1','2',tostring(block))
end
check(#results==3 and results[3].Body==string.rep('ABC',4096),'multi-block exact 12KiB response restored once')
check(think()==nil,'multi-block completion stops polling')
local changed=assert(bridge.create('GET',base..'/health'))
changed:Send(function() error('old world callback') end)
world={}
check(think()==nil,'world change cancels polling without old callback')
print=original_print
print('FILE_HTTP_BRIDGE_PASS checks='..checks..'; idle0; request metadata1; callbackonce; no HTTP in mock')
