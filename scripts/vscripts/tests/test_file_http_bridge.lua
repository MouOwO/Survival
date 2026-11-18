package.path='scripts/vscripts/?.lua;'..package.path
local checks,now,think,delay,reads=0,1,nil,nil,0
local files,output={},{}
local function check(value,message) checks=checks+1;assert(value,message) end
local base='https://pay.xiaofengnet.com/ws4-web'
local boot='cfg/survival_ws4_http_bridge_bootstrap.txt'
local cursor='cfg/survival_ws4_http_bridge_cursor.txt'
local nonce='n'..string.rep('a',32)
local world={SetContextThink=function(_,name,callback,seconds) think=callback;delay=seconds end}
GameRules={GetGameModeEntity=function() return world end}
IsServer=function() return true end
IsInToolsMode=function() return false end
IsDedicatedServer=function() return false end
GetMapName=function() return 'template_map' end
Time=function() return now end
DoUniqueString=function() return 'sfb_1' end
DisconnectClient=function() end
PlayerResource={GetSteamAccountID=function() return 1 end}
LoadKeyValues=function(path) reads=reads+1;return files[path] end
local original_print=print
print=function(value) if value:sub(1,7)=='[SFB1] ' then output[#output+1]=value end end
package.loaded['config/release_profile']={channel='production'}
package.loaded['config/player_web_auth']={enabled=true}
local bridge=require('core/file_http_bridge')
check(reads==0 and not think,'import is idle')
check(not bridge.create('GET',base..'/health?x=1'),'query rejected')
check(not bridge.create('GET',base..'.evil/health'),'host suffix rejected')
check(not bridge.create('POST',base..'/v1/../admin'),'path traversal rejected')
IsInToolsMode=function() return true end
check(not bridge.create('GET',base..'/health'),'Tools rejected')
IsInToolsMode=function() return false end
files[boot]={protocol='2',kind='bootstrap',nonce=nonce}
local results={}
local first=assert(bridge.create('GET',base..'/health'))
check(first:Send(function(value) results[#results+1]=value end),'Send accepted')
check(reads==1 and delay==.2,'first native read synchronous; next delay positive')
check(not first:Send(function() end),'Send not retried')
think()
check(#output==2,'ready and exactly one request emitted')
local function metadata(serial,id,size,chunks,blocks,other_nonce)
 files[cursor]={protocol='2',kind='reply',nonce=other_nonce or nonce,epoch='sfb_1',serial=tostring(serial),id=tostring(id),status='200',bytes=tostring(size),chunks=tostring(chunks),blocks=tostring(blocks)}
end
local function block(serial,index,count,parts)
 local path='cfg/survival_ws4_http_bridge/b_'..nonce..'_sfb_1_'..serial..'_'..index..'.txt'
 files[path]={protocol='2',kind='block',nonce=nonce,epoch='sfb_1',serial=tostring(serial),block=tostring(index),chunks=tostring(count),parts=parts}
 return path
end
metadata(1,1,2,1,1,'n'..string.rep('b',32));think()
check(#results==0,'wrong nonce ignored')
metadata(1,1,2,1,1);think()
local path=block(1,1,1,{p1='b%%%%'})
think();check(#results==0,'malformed block never invokes callback')
files[path].parts.p1='bT0s='
local before=reads;think()
check(reads==before+1,'one native KV read per active reply think')
check(#results==1 and results[1].Body=='OK' and results[1].StatusCode==200,'exact response restored once')
local idle=reads
check(think()==nil and reads==idle,'completion stops all file polling')
local bad=assert(bridge.create('POST',base..'/v1/profile'))
check(not bad:SetHTTPRequestRawPostBody('text/plain','x'),'wrong content type rejected')
check(not bad:Send(function() error('never') end),'invalid setter prevents send')
local timeout=assert(bridge.create('GET',base..'/health'))
timeout:SetHTTPRequestAbsoluteTimeoutMS(100)
timeout:Send(function(value) results[#results+1]=value end)
now=2;think()
check(#results==2 and results[2].StatusCode==0,'deadline terminates once')
CreateHTTPRequestScriptVM=function() return nil end
CreateHTTPRequest=function() return nil end
local large,outcome=require('core/http_request_factory').create('GET',base..'/health')
check(large and outcome=='nn','factory uses helper after native creation failures')
large:Send(function(value) results[#results+1]=value end)
metadata(2,3,12288,64,4);think()
for index=1,4 do
 local parts={}
 for offset=1,16 do parts['p'..offset]='b'..string.rep('QUJD',64) end
 block(2,index,16,parts)
 local count=reads;think();check(reads==count+1,'bounded one KV call per 3KiB block')
end
check(#results==3 and results[3].Body==string.rep('ABC',4096),'12KiB multi-block byte exact')
check(think()==nil,'multi-block completion stops timer')
local changed=assert(bridge.create('GET',base..'/health'))
changed:Send(function() error('old world callback') end)
world={}
check(think()==nil,'world change stops old response and polling')
print=original_print
print('FILE_HTTP_KV_PASS checks='..checks..'; idle0; native_reads<=1/think; callbackonce; no console commands or mock HTTP')
